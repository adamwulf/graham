import XCTest
@testable import GrahamKit

/// Tests for creating empty Drive files (`files.create`), the
/// ``DriveCreateType`` mapping, and the ``DriveFileCreateRequest`` body.
final class DriveCreateTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DriveClient {
        transport.stubTokenEndpoint()
        return DriveClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Request shape

    func testCreatePostsToFilesWithNameAndMimeInTheBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files",
            json: #"{"id":"new-1","name":"My Doc","mimeType":"application/vnd.google-apps.document"}"#
        )

        let file = try await client.create(name: "My Doc", type: .docs)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
        // Method and endpoint: a POST to the collection, with no id path.
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // The body carries the name and the MIME type.
        let body = try Self.body(request)
        XCTAssertEqual(body.name, "My Doc")
        XCTAssertEqual(body.mimeType, "application/vnd.google-apps.document")
        XCTAssertNil(body.parents)
        // The response is decoded and returned.
        XCTAssertEqual(file.id, "new-1")
        XCTAssertEqual(file.name, "My Doc")
        XCTAssertEqual(file.shortType, "doc")
    }

    func testCreateRequestsTheFullFieldSet() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files", json: #"{"id":"x","name":"n"}"#)

        _ = try await client.create(name: "n", type: .sheets)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
        // The same fields as a metadata fetch, so JSON/table output is populated.
        XCTAssertTrue(request.url.absoluteString.contains("fields=id,name,mimeType"))
        // Spans shared drives, so `create --parent <shared-drive-folder>` works.
        XCTAssertTrue(request.url.absoluteString.contains("supportsAllDrives=true"))
    }

    func testCreateMapsEachTypeToItsMime() async throws {
        let expected: [(DriveCreateType, String)] = [
            (.docs, "application/vnd.google-apps.document"),
            (.sheets, "application/vnd.google-apps.spreadsheet"),
            (.slides, "application/vnd.google-apps.presentation"),
            (.folder, "application/vnd.google-apps.folder"),
        ]
        for (type, mime) in expected {
            let transport = StubTransport()
            let client = makeClient(transport: transport)
            transport.stub(urlContains: "/drive/v3/files", json: #"{"id":"x","name":"n"}"#)

            _ = try await client.create(name: "n", type: type)

            let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
            let body = try Self.body(request)
            XCTAssertEqual(body.mimeType, mime, "type \(type) should map to \(mime)")
        }
    }

    func testCreatedFileRendersJustItsIdByDefault() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files",
            json: #"{"id":"new-99","name":"Deck","mimeType":"application/vnd.google-apps.presentation"}"#
        )

        let file = try await client.create(name: "Deck", type: .slides)

        // The `create` command prints with the `.id` format by default, so the
        // output is exactly the new file's id, ready to pipe.
        XCTAssertEqual(try OutputFormatter.render([file], format: .id), "new-99")
    }

    // MARK: - Safe encoding

    func testCreateEncodesTrickyNamesSafely() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files", json: #"{"id":"x","name":"n"}"#)

        // Quotes, a backslash, a newline, and a non-ASCII character.
        let tricky = "Q3 \"Report\"\n\\path — café"
        _ = try await client.create(name: tricky, type: .slides)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
        // The name round-trips exactly through the JSON body, so no character
        // breaks the request. It is never placed in the URL.
        let body = try Self.body(request)
        XCTAssertEqual(body.name, tricky)
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files")
    }

    func testCreateWithParentEncodesOneParentInTheBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files", json: #"{"id":"x","name":"n"}"#)

        _ = try await client.create(name: "Inside", type: .slides, parent: "folder-7")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files").first)
        XCTAssertEqual(try Self.body(request).parents, ["folder-7"])
        XCTAssertFalse(request.url.absoluteString.contains("folder-7"))
    }

    // MARK: - DriveCreateType

    func testDriveCreateTypeMimeTypes() {
        XCTAssertEqual(DriveCreateType.docs.mimeType, "application/vnd.google-apps.document")
        XCTAssertEqual(DriveCreateType.sheets.mimeType, "application/vnd.google-apps.spreadsheet")
        XCTAssertEqual(DriveCreateType.slides.mimeType, "application/vnd.google-apps.presentation")
        XCTAssertEqual(DriveCreateType.folder.mimeType, "application/vnd.google-apps.folder")
    }

    func testDriveCreateTypeShortNamesRoundTrip() {
        XCTAssertEqual(DriveCreateType.docs.shortName, "docs")
        XCTAssertEqual(DriveCreateType(shortName: "sheets"), .sheets)
        XCTAssertEqual(DriveCreateType(shortName: "slides"), .slides)
        XCTAssertEqual(DriveCreateType(shortName: "folder"), .folder)
        // "all" and the plural listing spelling are not creatable types.
        XCTAssertNil(DriveCreateType(shortName: "all"))
        XCTAssertNil(DriveCreateType(shortName: "folders"))
        XCTAssertNil(DriveCreateType(shortName: "images"))
    }

    func testDriveCreateTypeCoversDocsSheetsSlidesAndFolder() {
        XCTAssertEqual(
            DriveCreateType.allCases.map(\.shortName),
            ["docs", "sheets", "slides", "folder"]
        )
    }

    // MARK: - DriveFileCreateRequest

    func testCreateRequestEncodesWithSortedKeys() throws {
        let body = DriveFileCreateRequest(name: "Budget", mimeType: "application/vnd.google-apps.spreadsheet")
        let data = try GoogleJSON.encoder.encode(body)

        // Keys are sorted (mimeType before name), and the shared encoder escapes
        // the "/" in the MIME as "\/", like every other JSON output.
        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            #"{"mimeType":"application\/vnd.google-apps.spreadsheet","name":"Budget"}"#
        )
    }

    // MARK: - Helpers

    /// Decodes the JSON request body into a ``DriveFileCreateRequest``.
    private static func body(_ request: HTTPRequest) throws -> DriveFileCreateRequest {
        let data = try XCTUnwrap(request.body, "the create request should have a JSON body")
        return try GoogleJSON.decoder.decode(DriveFileCreateRequest.self, from: data)
    }

    /// The path of a URL, with no query, for endpoint assertions.
    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
}
