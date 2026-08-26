import XCTest
@testable import GrahamKit

/// Tests for the `files.update`-backed operations (rename, star/unstar, move,
/// restore from trash) and shortcut creation.
final class DriveUpdateTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DriveClient {
        transport.stubTokenEndpoint()
        return DriveClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Rename

    func testRenamePatchesTheNameOnly() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"id":"f1","name":"New Name"}"#
        )

        let file = try await client.rename(fileId: "f1", name: "New Name")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // The full field set is requested and the request spans shared drives.
        XCTAssertTrue(request.url.absoluteString.contains("fields=id,name,mimeType"))
        XCTAssertTrue(Self.queryItems(request.url).contains(URLQueryItem(name: "supportsAllDrives", value: "true")))
        // The body is exactly the new name — no starred, no trashed.
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"name":"New Name"}"#)
        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(file.name, "New Name")
    }

    func testRenameEncodesTrickyNamesInTheBodyNotTheURL() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files/f1", json: #"{"id":"f1","name":"n"}"#)

        let tricky = "Q3 \"Report\"\n\\path — café"
        _ = try await client.rename(fileId: "f1", name: tricky)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        let body = try GoogleJSON.decoder.decode(DriveUpdateRequest.self, from: try XCTUnwrap(request.body))
        XCTAssertEqual(body.name, tricky)
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1")
    }

    // MARK: - Star

    func testStarPatchesStarredTrue() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files/f1", json: #"{"id":"f1","name":"n"}"#)

        _ = try await client.setStarred(fileId: "f1", starred: true)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"starred":true}"#)
    }

    func testUnstarPatchesStarredFalse() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files/f1", json: #"{"id":"f1","name":"n"}"#)

        _ = try await client.setStarred(fileId: "f1", starred: false)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"starred":false}"#)
    }

    // MARK: - Untrash

    func testUntrashPatchesTrashedFalseAndMirrorsTrash() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"id":"f1","name":"Report"}"#
        )

        let file = try await client.untrash(fileId: "f1")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1")
        // Like trash, the only query item is supportsAllDrives=true; no fields.
        XCTAssertEqual(Self.queryItems(request.url), [URLQueryItem(name: "supportsAllDrives", value: "true")])
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"trashed":false}"#)
        XCTAssertEqual(file.id, "f1")
    }

    func testUntrashRequestEncodesTrashedFalse() throws {
        let data = try GoogleJSON.encoder.encode(DriveTrashRequest(trashed: false))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"trashed":false}"#)
    }

    // MARK: - Move

    func testMoveReadsCurrentParentsThenReparents() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        // First response: the current file with one parent. Second: the moved file.
        transport.stub(urlContains: "/drive/v3/files/f1", responses: [
            StubTransport.json(#"{"id":"f1","name":"Report","parents":["old-1"]}"#),
            StubTransport.json(#"{"id":"f1","name":"Report","parents":["folder-9"]}"#),
        ])

        let file = try await client.move(fileId: "f1", to: "folder-9")

        let requests = transport.requests(urlContains: "/drive/v3/files/f1")
        XCTAssertEqual(requests.count, 2)
        // The first call reads the current parents.
        XCTAssertEqual(requests[0].method, "GET")
        // The second call is the reparenting PATCH.
        let patch = requests[1]
        XCTAssertEqual(patch.method, "PATCH")
        let items = Self.queryItems(patch.url)
        XCTAssertTrue(items.contains(URLQueryItem(name: "addParents", value: "folder-9")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "removeParents", value: "old-1")))
        // The parent change is entirely in the URL; the body is empty.
        XCTAssertEqual(String(data: try XCTUnwrap(patch.body), encoding: .utf8), "{}")
        XCTAssertEqual(file.id, "f1")
    }

    func testMoveExcludesTheDestinationFromRemoveParents() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        // The file is already in folder-9 alongside old-1; moving to folder-9 must
        // not add and remove folder-9 in the same request.
        transport.stub(urlContains: "/drive/v3/files/f1", responses: [
            StubTransport.json(#"{"id":"f1","name":"n","parents":["old-1","folder-9"]}"#),
            StubTransport.json(#"{"id":"f1","name":"n"}"#),
        ])

        _ = try await client.move(fileId: "f1", to: "folder-9")

        let patch = transport.requests(urlContains: "/drive/v3/files/f1")[1]
        let items = Self.queryItems(patch.url)
        XCTAssertTrue(items.contains(URLQueryItem(name: "addParents", value: "folder-9")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "removeParents", value: "old-1")))
    }

    func testMoveWithNoCurrentParentsSendsNoRemoveParents() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files/f1", responses: [
            StubTransport.json(#"{"id":"f1","name":"n"}"#),
            StubTransport.json(#"{"id":"f1","name":"n"}"#),
        ])

        _ = try await client.move(fileId: "f1", to: "folder-9")

        let patch = transport.requests(urlContains: "/drive/v3/files/f1")[1]
        let names = Self.queryItems(patch.url).map(\.name)
        XCTAssertTrue(names.contains("addParents"))
        XCTAssertFalse(names.contains("removeParents"))
    }

    // MARK: - Shortcut

    func testCreateShortcutPostsTheShortcutMimeAndTarget() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files",
            json: #"{"id":"short-1","name":"Link","mimeType":"application/vnd.google-apps.shortcut"}"#
        )

        let file = try await client.createShortcut(name: "Link", targetId: "target-7")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files")
        let body = try GoogleJSON.decoder.decode(DriveShortcutCreateRequest.self, from: try XCTUnwrap(request.body))
        XCTAssertEqual(body.name, "Link")
        XCTAssertEqual(body.mimeType, "application/vnd.google-apps.shortcut")
        XCTAssertEqual(body.shortcutDetails.targetId, "target-7")
        XCTAssertNil(body.parents)
        // The target id never rides in the URL.
        XCTAssertFalse(request.url.absoluteString.contains("target-7"))
        XCTAssertEqual(file.id, "short-1")
        XCTAssertEqual(file.shortType, "shortcut")
    }

    func testCreateShortcutWithParentEncodesOneParent() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files", json: #"{"id":"x","name":"n"}"#)

        _ = try await client.createShortcut(name: "Link", targetId: "target-7", parent: "folder-3")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
        let body = try GoogleJSON.decoder.decode(DriveShortcutCreateRequest.self, from: try XCTUnwrap(request.body))
        XCTAssertEqual(body.parents, ["folder-3"])
        XCTAssertFalse(request.url.absoluteString.contains("folder-3"))
    }

    // MARK: - Error propagation

    func testRenamePropagatesAGoogleError() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"error":{"code":404,"message":"File not found.","status":"NOT_FOUND"}}"#,
            status: 404
        )

        do {
            _ = try await client.rename(fileId: "f1", name: "n")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 404)
            XCTAssertEqual(status, "NOT_FOUND")
        }
    }

    // MARK: - Request encoding

    func testUpdateRequestOmitsNilFields() throws {
        // A pure move sends an empty object; the parent change is in the URL.
        XCTAssertEqual(
            String(data: try GoogleJSON.encoder.encode(DriveUpdateRequest()), encoding: .utf8), "{}")
        XCTAssertEqual(
            String(data: try GoogleJSON.encoder.encode(DriveUpdateRequest(name: "n")), encoding: .utf8),
            #"{"name":"n"}"#)
    }

    // MARK: - Helpers

    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }

    private static func queryItems(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }
}
