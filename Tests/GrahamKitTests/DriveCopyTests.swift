import XCTest
@testable import GrahamKit

/// Tests for copying a Drive file (`files.copy`) and the
/// ``DriveFileCopyRequest`` body, including the omitted-name case.
final class DriveCopyTests: XCTestCase {

    // MARK: - Request shape

    func testCopyPostsToTheCopyEndpointWithTheNameInTheBody() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1/copy",
            json: #"{"id":"copy-1","name":"My Copy","mimeType":"application/vnd.google-apps.document"}"#
        )

        let file = try await client.copy(fileId: "f1", name: "My Copy")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1/copy").first)
        // Method and endpoint: a POST to the file's /copy sub-resource.
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1/copy")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // The one and only query item is supportsAllDrives=true; nothing else.
        XCTAssertEqual(Self.queryItems(request.url), [URLQueryItem(name: "supportsAllDrives", value: "true")])
        // The name is carried in the body, never in the URL.
        let body = try Self.body(request)
        XCTAssertEqual(body.name, "My Copy")
        XCTAssertNil(body.parents)
        // The response is decoded and returned as the new file.
        XCTAssertEqual(file.id, "copy-1")
        XCTAssertEqual(file.name, "My Copy")
        XCTAssertEqual(file.shortType, "doc")
    }

    func testCopyOmitsTheNameKeyWhenNoNameIsGiven() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1/copy",
            json: #"{"id":"copy-2","name":"Copy of Report"}"#
        )

        _ = try await client.copy(fileId: "f1")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1/copy").first)
        // With no name, the JSON body is an empty object, so Drive keeps its
        // default "Copy of <original>" naming.
        let data = try XCTUnwrap(request.body)
        XCTAssertEqual(String(data: data, encoding: .utf8), "{}")
        let body = try Self.body(request)
        XCTAssertNil(body.name)
    }

    func testCopyEscapesTheFileIDInThePath() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/copy", json: #"{"id":"x","name":"n"}"#)

        _ = try await client.copy(fileId: "a b/c")

        let request = try XCTUnwrap(transport.requests(urlContains: "/copy").first)
        // The id is percent-escaped as one path component; the "/" does not
        // open a new path segment.
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/a b/c/copy")
        XCTAssertTrue(request.url.absoluteString.contains("/files/a%20b%2Fc/copy"))
    }

    func testCopyWithParentEncodesTheDestinationInTheBody() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1/copy",
            json: #"{"id":"copy-1","name":"My Copy"}"#
        )

        _ = try await client.copy(fileId: "f1", name: "My Copy", parent: "folder-7")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1/copy").first)
        XCTAssertEqual(try Self.body(request).parents, ["folder-7"])
        XCTAssertFalse(request.url.absoluteString.contains("folder-7"))
    }

    func testCopyReturnsTheNewFilesId() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1/copy",
            json: #"{"id":"copy-99","name":"Deck copy","mimeType":"application/vnd.google-apps.presentation"}"#
        )

        let file = try await client.copy(fileId: "f1", name: "Deck copy")

        // The `copy` command prints exactly this id, ready to pipe.
        XCTAssertEqual(file.id, "copy-99")
    }

    // MARK: - Safe encoding

    func testCopyEncodesTrickyNamesSafely() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files/f1/copy", json: #"{"id":"x","name":"n"}"#)

        // Quotes, a backslash, a newline, and a non-ASCII character.
        let tricky = "Q3 \"Report\"\n\\path — café"
        _ = try await client.copy(fileId: "f1", name: tricky)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1/copy").first)
        // The name round-trips exactly through the JSON body, so no character
        // breaks the request. It is never placed in the URL.
        let body = try Self.body(request)
        XCTAssertEqual(body.name, tricky)
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/f1/copy")
    }

    // MARK: - DriveFileCopyRequest

    func testCopyRequestEncodesTheNameWithSortedKeys() throws {
        let body = DriveFileCopyRequest(name: "Budget copy")
        let data = try GoogleJSON.encoder.encode(body)

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"name":"Budget copy"}"#)
    }

    func testCopyRequestOmitsANilName() throws {
        let body = DriveFileCopyRequest(name: nil)
        let data = try GoogleJSON.encoder.encode(body)

        // A nil name is omitted entirely, leaving an empty object.
        XCTAssertEqual(String(data: data, encoding: .utf8), "{}")
    }

    // MARK: - Helpers

    /// Decodes the JSON request body into a ``DriveFileCopyRequest``.
    private static func body(_ request: HTTPRequest) throws -> DriveFileCopyRequest {
        let data = try XCTUnwrap(request.body, "the copy request should have a JSON body")
        return try GoogleJSON.decoder.decode(DriveFileCopyRequest.self, from: data)
    }

    /// The path of a URL, with no query, for endpoint assertions.
    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }

    /// The decoded query items of a URL, for exact query assertions.
    private static func queryItems(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }
}
