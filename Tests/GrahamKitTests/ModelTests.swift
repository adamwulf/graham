import XCTest
@testable import GrahamKit

final class ModelTests: XCTestCase {
    // MARK: - Sheets

    func testCellValueDecodesAllScalarTypes() throws {
        let json = #"[["text", 1.5, 2, true, null]]"#
        let rows = try GoogleJSON.decoder.decode([[CellValue]].self, from: Data(json.utf8))

        XCTAssertEqual(rows, [[
            .string("text"),
            .number(1.5),
            .number(2),
            .bool(true),
            .null,
        ]])
    }

    func testCellValueDisplay() {
        XCTAssertEqual(CellValue.string("a").display, "a")
        XCTAssertEqual(CellValue.number(1.5).display, "1.5")
        XCTAssertEqual(CellValue.number(2).display, "2")
        XCTAssertEqual(CellValue.bool(true).display, "TRUE")
        XCTAssertEqual(CellValue.null.display, "")
    }

    func testSpreadsheetDecodes() throws {
        let json = #"""
        {
            "spreadsheetId": "sheet-1",
            "properties": {"title": "Budget"},
            "spreadsheetUrl": "https://docs.google.com/spreadsheets/d/sheet-1",
            "sheets": [
                {"properties": {"sheetId": 0, "title": "Tab A", "index": 0,
                    "gridProperties": {"rowCount": 100, "columnCount": 26}}}
            ]
        }
        """#
        let spreadsheet = try GoogleJSON.decoder.decode(Spreadsheet.self, from: Data(json.utf8))

        XCTAssertEqual(spreadsheet.properties?.title, "Budget")
        XCTAssertEqual(spreadsheet.sheets?.count, 1)
        XCTAssertEqual(spreadsheet.sheets?.first?.properties?.title, "Tab A")
        XCTAssertEqual(spreadsheet.sheets?.first?.properties?.gridProperties?.rowCount, 100)
    }

    // MARK: - Docs

    func testDocumentPlainTextJoinsParagraphsAndTables() throws {
        let json = #"""
        {
            "documentId": "doc-1",
            "title": "Test",
            "body": {"content": [
                {"sectionBreak": {}},
                {"paragraph": {"elements": [
                    {"textRun": {"content": "Hello "}},
                    {"textRun": {"content": "world.\n"}}
                ]}},
                {"table": {"tableRows": [
                    {"tableCells": [
                        {"content": [{"paragraph": {"elements": [{"textRun": {"content": "A\n"}}]}}]},
                        {"content": [{"paragraph": {"elements": [{"textRun": {"content": "B\n"}}]}}]}
                    ]}
                ]}}
            ]}
        }
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))

        XCTAssertEqual(document.plainText, "Hello world.\nA\tB\n")
    }

    func testDocumentWithUnknownElementsStillDecodes() throws {
        let json = #"""
        {"documentId": "doc-1", "body": {"content": [
            {"tableOfContents": {"something": 1}},
            {"paragraph": {"elements": [{"textRun": {"content": "Text.\n"}}]}}
        ]}}
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))

        XCTAssertEqual(document.plainText, "Text.\n")
    }

    // MARK: - Slides

    func testSlidePlainTextReadsShapes() throws {
        let json = #"""
        {
            "presentationId": "p-1",
            "title": "Deck",
            "slides": [
                {"objectId": "s1", "pageElements": [
                    {"objectId": "e1", "shape": {"text": {"textElements": [
                        {"paragraphMarker": {}},
                        {"textRun": {"content": "Slide title\n"}}
                    ]}}},
                    {"objectId": "e2"}
                ]}
            ]
        }
        """#
        let presentation = try GoogleJSON.decoder.decode(Presentation.self, from: Data(json.utf8))

        XCTAssertEqual(presentation.title, "Deck")
        XCTAssertEqual(presentation.slides?.first?.plainText, "Slide title")
    }

    // MARK: - Drive

    func testDriveFileShortType() {
        func file(_ mime: String?) -> DriveFile {
            DriveFile(id: "x", name: "n", mimeType: mime)
        }
        XCTAssertEqual(file("application/vnd.google-apps.document").shortType, "doc")
        XCTAssertEqual(file("application/vnd.google-apps.spreadsheet").shortType, "sheet")
        XCTAssertEqual(file("application/vnd.google-apps.presentation").shortType, "slides")
        XCTAssertEqual(file("application/vnd.google-apps.folder").shortType, "folder")
        XCTAssertEqual(file("application/pdf").shortType, "pdf")
        XCTAssertEqual(file(nil).shortType, "")
    }
}
