import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 document-tab writes: `addDocumentTab`,
/// `deleteTab`, and `updateDocumentTabProperties`. Every fixture is static JSON;
/// no test touches the network, and the request bodies are asserted exactly (the
/// shared encoder sorts keys, so the strings are deterministic).
final class DocsTabsWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - addDocumentTab

    func testAddDocumentTabTranslatesPositionAndReturnsNewTabId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"addDocumentTab":{"tabProperties":{"tabId":"t.new","index":1,"title":"Notes"}}}]}"#
        )

        let (_, tabId) = try await client.addDocumentTab(
            documentId: "doc-1", title: "Notes", position: 2, parentTabId: "t.parent")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        // Position 2 (one-based) becomes API index 1 (zero-based).
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addDocumentTab":{"tabProperties":{"index":1,"parentTabId":"t.parent","title":"Notes"}}}]}"#
        )
        XCTAssertEqual(tabId, "t.new")
    }

    func testAddDocumentTabWithNoOptionsSendsEmptyTabProperties() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        let (_, tabId) = try await client.addDocumentTab(documentId: "doc-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addDocumentTab":{"tabProperties":{}}}]}"#
        )
        // An empty reply carries no tab id.
        XCTAssertNil(tabId)
    }

    func testAddDocumentTabEncodesIconEmoji() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.addDocumentTab(documentId: "doc-1", title: "T", iconEmoji: "📓")

        let body = Self.bodyString(try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first))
        XCTAssertTrue(body.contains(#""iconEmoji":"📓""#), "unexpected body: \(body)")
    }

    func testAddDocumentTabRejectsNonPositivePositionWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.addDocumentTab(documentId: "doc-1", position: 0)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - deleteTab

    func testDeleteTabEncodesTabId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.deleteTab(documentId: "doc-1", tabId: "t.1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteTab":{"tabId":"t.1"}}]}"#
        )
    }

    func testDeleteTabRejectsEmptyTabIdWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.deleteTab(documentId: "doc-1", tabId: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - updateDocumentTabProperties

    func testUpdateTabRenameAndMoveEncodesMaskAndTranslatesPosition() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.updateDocumentTabProperties(
            documentId: "doc-1", tabId: "t.1", title: "Renamed", position: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // The mask lists title,index in fixed order; position 3 becomes index 2.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDocumentTabProperties":{"fields":"title,index","tabProperties":{"index":2,"tabId":"t.1","title":"Renamed"}}}]}"#
        )
    }

    func testUpdateTabReparentOnlyEmitsMinimalMask() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.updateDocumentTabProperties(
            documentId: "doc-1", tabId: "t.1", parentTabId: "t.p")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDocumentTabProperties":{"fields":"parentTabId","tabProperties":{"parentTabId":"t.p","tabId":"t.1"}}}]}"#
        )
    }

    func testUpdateTabRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // An empty tab id.
        await assertInvalidArgument {
            _ = try await client.updateDocumentTabProperties(
                documentId: "doc-1", tabId: "", title: "x")
        }
        // No property to change.
        await assertInvalidArgument {
            _ = try await client.updateDocumentTabProperties(documentId: "doc-1", tabId: "t.1")
        }
        // A non-positive position.
        await assertInvalidArgument {
            _ = try await client.updateDocumentTabProperties(
                documentId: "doc-1", tabId: "t.1", position: 0)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Union discriminators

    func testEachTabRequestEncodesUnderItsOwnKey() throws {
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .addDocumentTab(DocsAddDocumentTabRequest(
                    tabProperties: DocsTabProperties(title: "T"))),
                #"{"addDocumentTab":{"tabProperties":{"title":"T"}}}"#
            ),
            (
                .deleteTab(DocsDeleteTabRequest(tabId: "t.1")),
                #"{"deleteTab":{"tabId":"t.1"}}"#
            ),
            (
                .updateDocumentTabProperties(DocsUpdateDocumentTabPropertiesRequest(
                    tabProperties: DocsTabProperties(tabId: "t.1", title: "T"), fields: "title")),
                #"{"updateDocumentTabProperties":{"fields":"title","tabProperties":{"tabId":"t.1","title":"T"}}}"#
            ),
        ]
        for (request, expected) in cases {
            let data = try GoogleJSON.encoder.encode(request)
            XCTAssertEqual(String(data: data, encoding: .utf8), expected)
        }
    }

    private func assertInvalidArgument(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
        }
    }

    private static func bodyString(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
