import XCTest
@testable import GrahamKit

/// Tests for the import-converting copy (`files.copy` with a target
/// `mimeType`), the ``DriveConvertType`` mapping, and the `mimeType` field on
/// ``DriveFileCopyRequest``.
final class DriveConvertTests: XCTestCase {

    // MARK: - Request shape

    func testConvertPostsToTheCopyEndpointWithTheMimeInTheBody() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/deck.pptx/copy",
            json: #"{"id":"slides-1","name":"Deck","mimeType":"application/vnd.google-apps.presentation"}"#
        )

        let file = try await client.copy(
            fileId: "deck.pptx", name: "Deck",
            mimeType: DriveConvertType.slides.mimeType)

        let request = try XCTUnwrap(
            transport.requests(urlContains: "/drive/v3/files/deck.pptx/copy").first)
        // A convert is a POST to the source file's /copy sub-resource.
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/drive/v3/files/deck.pptx/copy")
        // The target type travels in the body, never in the URL.
        let body = try Self.body(request)
        XCTAssertEqual(body.mimeType, "application/vnd.google-apps.presentation")
        XCTAssertEqual(body.name, "Deck")
        XCTAssertFalse(request.url.absoluteString.contains("presentation"))
        // The new Google Slides file is decoded and returned.
        XCTAssertEqual(file.id, "slides-1")
        XCTAssertEqual(file.shortType, "slides")
    }

    func testConvertMapsEachTypeToItsGoogleMime() async throws {
        let expected: [(DriveConvertType, String)] = [
            (.doc, "application/vnd.google-apps.document"),
            (.sheet, "application/vnd.google-apps.spreadsheet"),
            (.slides, "application/vnd.google-apps.presentation"),
        ]
        for (type, mime) in expected {
            let transport = StubTransport()
            let client = TestSupport.driveClient(transport)
            transport.stub(urlContains: "/copy", json: #"{"id":"x","name":"n"}"#)

            _ = try await client.copy(fileId: "f1", mimeType: type.mimeType)

            let request = try XCTUnwrap(transport.requests(urlContains: "/copy").first)
            XCTAssertEqual(try Self.body(request).mimeType, mime, "type \(type) should map to \(mime)")
        }
    }

    func testCopyOmitsTheMimeKeyWhenNoTargetTypeIsGiven() async throws {
        // A plain copy (no mimeType) keeps the source type and sends no mimeType.
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/copy", json: #"{"id":"x","name":"n"}"#)

        _ = try await client.copy(fileId: "f1", name: "Plain copy")

        let request = try XCTUnwrap(transport.requests(urlContains: "/copy").first)
        XCTAssertNil(try Self.body(request).mimeType)
    }

    // MARK: - DriveConvertType

    func testDriveConvertTypeMimeTypes() {
        XCTAssertEqual(DriveConvertType.doc.mimeType, "application/vnd.google-apps.document")
        XCTAssertEqual(DriveConvertType.sheet.mimeType, "application/vnd.google-apps.spreadsheet")
        XCTAssertEqual(DriveConvertType.slides.mimeType, "application/vnd.google-apps.presentation")
    }

    func testDriveConvertTypeShortNamesRoundTrip() {
        XCTAssertEqual(DriveConvertType.doc.shortName, "doc")
        XCTAssertEqual(DriveConvertType(shortName: "sheet"), .sheet)
        XCTAssertEqual(DriveConvertType(shortName: "slides"), .slides)
        // Convert targets only the three editable types: no folder, no plurals.
        XCTAssertNil(DriveConvertType(shortName: "folder"))
        XCTAssertNil(DriveConvertType(shortName: "docs"))
        XCTAssertNil(DriveConvertType(shortName: "sheets"))
    }

    func testDriveConvertTypeCoversDocSheetAndSlides() {
        XCTAssertEqual(DriveConvertType.allCases.map(\.shortName), ["doc", "sheet", "slides"])
    }

    // MARK: - DriveFileCopyRequest

    func testCopyRequestEncodesMimeTypeWithSortedKeys() throws {
        let body = DriveFileCopyRequest(
            name: "My Slides", mimeType: "application/vnd.google-apps.presentation")
        let data = try GoogleJSON.encoder.encode(body)

        // Keys are sorted (mimeType before name), and the shared encoder escapes
        // the "/" in the MIME as "\/", like every other JSON output.
        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            #"{"mimeType":"application\/vnd.google-apps.presentation","name":"My Slides"}"#
        )
    }

    func testCopyRequestOmitsANilMimeType() throws {
        let body = DriveFileCopyRequest(name: "Plain")
        let data = try GoogleJSON.encoder.encode(body)

        // With no target type, mimeType is omitted, leaving just the name.
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"name":"Plain"}"#)
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
}
