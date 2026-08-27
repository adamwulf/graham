import XCTest
@testable import GrahamKit

/// Tests for trashing (`files.update` with `trashed = true`) and permanently
/// deleting (`files.delete`, HTTP 204) a Drive file.
final class DriveTrashDeleteTests: XCTestCase {

    // MARK: - Trash

    func testTrashPatchesTheFileWithTrashedTrue() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"id":"f1","name":"Report","mimeType":"application/vnd.google-apps.document"}"#
        )

        let file = try await client.trash(fileId: "f1")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        // Method and endpoint: a PATCH to the file resource (no /copy, no /export).
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // The one and only query item is supportsAllDrives=true; nothing else.
        XCTAssertEqual(Self.queryItems(request.url), [URLQueryItem(name: "supportsAllDrives", value: "true")])
        // The body is exactly the trashed flag.
        let data = try XCTUnwrap(request.body, "the trash request should have a JSON body")
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"trashed":true}"#)
        // The updated file is decoded and returned.
        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(file.name, "Report")
    }

    func testTrashEscapesTheFileIDInThePath() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files/", json: #"{"id":"x","name":"n"}"#)

        _ = try await client.trash(fileId: "a b/c")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/").first)
        // The id is percent-escaped as one path component.
        XCTAssertTrue(request.url.absoluteString.contains("/files/a%20b%2Fc?"))
    }

    func testTrashRequestEncodesTrashedTrue() throws {
        let data = try GoogleJSON.encoder.encode(DriveTrashRequest(trashed: true))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"trashed":true}"#)
    }

    // MARK: - Delete

    func testDeleteSendsDeleteAndToleratesAnEmpty204Body() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        // A real files.delete replies with HTTP 204 and an empty body.
        transport.stub(urlContains: "/drive/v3/files/f1", responses: [
            HTTPResponse(statusCode: 204, body: Data()),
        ])

        try await client.delete(fileId: "f1")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1")
        // No JSON body is sent for a delete.
        XCTAssertNil(request.body)
        // The one and only query item is supportsAllDrives=true; nothing else.
        XCTAssertEqual(Self.queryItems(request.url), [URLQueryItem(name: "supportsAllDrives", value: "true")])
    }

    func testDeleteEscapesTheFileIDInThePath() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files/", responses: [
            HTTPResponse(statusCode: 204, body: Data()),
        ])

        try await client.delete(fileId: "a b/c")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/").first)
        XCTAssertTrue(request.url.absoluteString.contains("/files/a%20b%2Fc?"))
    }

    func testDeletePropagatesAGoogleError() async {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"error":{"code":404,"message":"File not found.","status":"NOT_FOUND"}}"#,
            status: 404
        )

        do {
            try await client.delete(fileId: "f1")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 404)
            XCTAssertEqual(status, "NOT_FOUND")
        }
    }

    // MARK: - Helpers

    /// The path of a URL, with no query, for endpoint assertions.
    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }

    /// The decoded query items of a URL, for exact query assertions.
    private static func queryItems(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }
}
