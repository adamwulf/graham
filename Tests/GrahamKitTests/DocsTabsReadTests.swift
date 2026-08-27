import XCTest
@testable import GrahamKit

/// Tests for the tab-aware read surface: the `includeTabsContent` query
/// parameter, the decoded `Document.tabs` tree, `Document.tabRows` (flattened
/// for `docs tab list`), `Document.tab(withId:)`, and a tab's `blockRows` /
/// `plainText`. Every fixture is static JSON; no test touches the network.
final class DocsTabsReadTests: XCTestCase {
    private static let tabbedJSON = #"""
    {
      "documentId": "doc-1",
      "title": "Tabbed",
      "tabs": [
        {
          "tabProperties": {"tabId": "t.0", "title": "First", "index": 0},
          "documentTab": {"body": {"content": [
            {"endIndex": 1, "sectionBreak": {}},
            {"startIndex": 1, "endIndex": 7, "paragraph": {
              "elements": [{"startIndex": 1, "endIndex": 7, "textRun": {
                "content": "Hello\n", "textStyle": {}}}]
            }}
          ]}}
        },
        {
          "tabProperties": {"tabId": "t.1", "title": "Second", "index": 1},
          "documentTab": {"body": {"content": [
            {"startIndex": 1, "endIndex": 5, "paragraph": {
              "elements": [{"startIndex": 1, "endIndex": 5, "textRun": {
                "content": "Bye\n", "textStyle": {}}}]
            }}
          ]}},
          "childTabs": [
            {
              "tabProperties": {"tabId": "t.1.0", "title": "Nested", "index": 0, "parentTabId": "t.1"},
              "documentTab": {"body": {"content": []}}
            }
          ]
        }
      ]
    }
    """#

    private func decodeTabbed() throws -> Document {
        try GoogleJSON.decoder.decode(Document.self, from: Data(Self.tabbedJSON.utf8))
    }

    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - includeTabsContent query

    func testDocumentWithTabsContentAddsQueryAndDecodesTabs() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/documents/doc-1", json: Self.tabbedJSON)

        let document = try await client.document(id: "doc-1", includeTabsContent: true)

        let request = try XCTUnwrap(transport.requests(urlContains: "/documents/doc-1").first)
        XCTAssertTrue(
            request.url.absoluteString.contains("includeTabsContent=true"),
            "unexpected url: \(request.url.absoluteString)")
        XCTAssertEqual(document.tabs?.count, 2)
    }

    func testDocumentWithoutTabsContentOmitsTheQuery() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/documents/doc-1", json: #"{"documentId":"doc-1"}"#)

        _ = try await client.document(id: "doc-1")

        let request = try XCTUnwrap(transport.requests(urlContains: "/documents/doc-1").first)
        XCTAssertFalse(
            request.url.absoluteString.contains("includeTabsContent"),
            "unexpected url: \(request.url.absoluteString)")
    }

    // MARK: - tabRows

    func testTabRowsFlattenTreeWithOneBasedPositionAndNesting() throws {
        let rows = try decodeTabbed().tabRows
        XCTAssertEqual(rows.map(\.tabId), ["t.0", "t.1", "t.1.0"])
        XCTAssertEqual(rows.map(\.depth), [0, 0, 1])
        // The API index is zero-based; the row shows the one-based position.
        XCTAssertEqual(rows.map(\.position), [1, 2, 1])
        XCTAssertEqual(rows[2].parentTabId, "t.1")
    }

    func testTabRowRenderIndentsNestedTitle() throws {
        let rows = try decodeTabbed().tabRows
        XCTAssertEqual(rows[0].tableValues, ["t.0", "First", "1", ""])
        XCTAssertEqual(rows[2].tableValues, ["t.1.0", "  Nested", "1", "t.1"])
    }

    func testEmptyDocumentYieldsNoTabRows() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(#"{"documentId":"doc-1"}"#.utf8))
        XCTAssertTrue(document.tabRows.isEmpty)
        XCTAssertNil(document.tab(withId: "t.0"))
    }

    // MARK: - tab(withId:) and per-tab reads

    func testTabFinderRecursesIntoChildTabs() throws {
        let document = try decodeTabbed()
        XCTAssertEqual(document.tab(withId: "t.1.0")?.tabProperties?.title, "Nested")
        XCTAssertNil(document.tab(withId: "t.missing"))
    }

    func testTabBlockRowsAndPlainText() throws {
        let document = try decodeTabbed()
        let first = try XCTUnwrap(document.tab(withId: "t.0"))
        // The section break plus one paragraph.
        XCTAssertEqual(first.blockRows.count, 2)
        XCTAssertEqual(first.plainText, "Hello\n")

        let second = try XCTUnwrap(document.tab(withId: "t.1"))
        XCTAssertEqual(second.plainText, "Bye\n")
    }
}
