import XCTest
@testable import GrahamKit

final class GrahamRowTests: XCTestCase {
    func testSheetChartRowContract() {
        let row = SheetChart(chartId: 314, spec: .init(title: "Sales"))

        XCTAssertEqual(SheetChart.tableColumns, ["CHART_ID", "TITLE"])
        XCTAssertEqual(row.tableValues, ["314", "Sales"])
        XCTAssertEqual(row.idValue, "314")
    }

    func testSheetRowContract() {
        let grid = Sheet.Properties.GridProperties(
            rowCount: 100,
            columnCount: 26,
            frozenRowCount: 1,
            frozenColumnCount: 2
        )
        let properties = Sheet.Properties(
            sheetId: 7,
            title: "Budget",
            index: 0,
            gridProperties: grid
        )
        let row = Sheet(properties: properties, charts: nil)

        XCTAssertEqual(
            Sheet.tableColumns,
            ["SHEET_ID", "ROWS", "COLS", "FROZEN_R", "FROZEN_C", "TITLE"]
        )
        XCTAssertEqual(row.tableValues, ["7", "100", "26", "1", "2", "Budget"])
        XCTAssertEqual(row.idValue, "7")
    }

    func testNamedRangeRowContract() {
        let range = GridRange(
            sheetId: 7,
            startRowIndex: 1,
            endRowIndex: 5,
            startColumnIndex: 0,
            endColumnIndex: 3
        )
        let row = NamedRange(namedRangeId: "range-1", name: "Summary", range: range)

        XCTAssertEqual(
            NamedRange.tableColumns,
            ["NAMED_RANGE_ID", "NAME", "SHEET_ID", "RANGE"]
        )
        XCTAssertEqual(row.tableValues, ["range-1", "Summary", "7", "A2:C5"])
        XCTAssertEqual(row.idValue, "range-1")
    }

    func testDriveFileRowContract() {
        let row = DriveFile(
            id: "file-1",
            name: "Quarterly plan",
            mimeType: "application/vnd.google-apps.document",
            modifiedTime: "2026-08-27T12:34:56Z"
        )

        XCTAssertEqual(DriveFile.tableColumns, ["ID", "TYPE", "MODIFIED", "NAME"])
        XCTAssertEqual(
            row.tableValues,
            ["file-1", "doc", "2026-08-27T12:34:56Z", "Quarterly plan"]
        )
        XCTAssertEqual(row.idValue, "file-1")
    }

    func testDocTabRowContract() {
        let tab = DocTab(
            tabProperties: DocsTabProperties(
                tabId: "tab-2",
                title: "Appendix",
                index: 1,
                parentTabId: "tab-1"
            ),
            documentTab: nil,
            childTabs: nil
        )
        let row = DocTabRow(tab: tab, depth: 1)

        XCTAssertEqual(DocTabRow.tableColumns, ["TAB_ID", "TITLE", "POS", "PARENT"])
        XCTAssertEqual(row.tableValues, ["tab-2", "  Appendix", "2", "tab-1"])
        XCTAssertEqual(row.idValue, "tab-2")
    }

    func testDocBlockRowContract() throws {
        let row = try decode(
            DocBlockRow.self,
            #"{"startIndex":14,"endIndex":31,"kind":"listItem","depth":1,"namedStyleType":"HEADING_2","headingLevel":2,"listId":"list-1","nestingLevel":1,"objectIds":["image-1","image-2"],"preview":"Quarterly plan"}"#
        )

        XCTAssertEqual(
            DocBlockRow.tableColumns,
            ["RANGE", "KIND", "STYLE", "LIST", "NEST", "OBJECTS", "TEXT"]
        )
        XCTAssertEqual(
            row.tableValues,
            [
                "14-31", "  listItem", "HEADING_2", "list-1", "1",
                "image-1,image-2", "Quarterly plan",
            ]
        )
        XCTAssertEqual(row.idValue, "14")
    }

    func testDocImageRowContract() throws {
        let row = try decode(
            DocImageRow.self,
            #"{"objectId":"image-1","origin":"positioned","width":120.4,"height":60.4,"widthUnit":"PT","heightUnit":"PT","sourceUri":"https://example.com/source.png","contentUri":"https://example.com/content.png"}"#
        )

        XCTAssertEqual(
            DocImageRow.tableColumns,
            ["ORIGIN", "OBJECT", "SIZE(pt)", "SOURCE_URI", "CONTENT_URI"]
        )
        XCTAssertEqual(
            row.tableValues,
            [
                "positioned", "image-1", "120x60", "https://example.com/source.png",
                "https://example.com/content.png",
            ]
        )
        XCTAssertEqual(row.idValue, "image-1")
    }

    func testDocNamedRangeRowContract() throws {
        let row = try decode(
            DocNamedRangeRow.self,
            #"{"namedRangeId":"range-1","name":"Summary","ranges":[{"startIndex":14,"endIndex":31},{"startIndex":37,"endIndex":44}]}"#
        )

        XCTAssertEqual(DocNamedRangeRow.tableColumns, ["ID", "NAME", "RANGES"])
        XCTAssertEqual(row.tableValues, ["range-1", "Summary", "14-31,37-44"])
        XCTAssertEqual(row.idValue, "range-1")
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try GoogleJSON.decoder.decode(type, from: Data(json.utf8))
    }
}
