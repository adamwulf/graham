import XCTest
import GrahamKit
@testable import graham

final class SheetsWriteParsingTests: XCTestCase {
    func testSheetsSetParsesRepeatedRows() throws {
        let command = try Sheets.Set.parse([
            "sheet-1",
            "'My Sheet'!A1:B3",
            "--row", "Label,Value",
            "--row", "A,10",
            "--row", "B,20",
        ])

        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.range, "'My Sheet'!A1:B3")
        XCTAssertEqual(command.row, ["Label,Value", "A,10", "B,20"])
    }

    func testSheetsSetRequiresArgumentsAndExactlyOneInputMode() {
        XCTAssertThrowsError(try Sheets.Set.parse([]))
        XCTAssertThrowsError(try Sheets.Set.parse(["sheet-1", "A1:B2"]))
        XCTAssertThrowsError(try Sheets.Set.parse(["sheet-1", "--row", "A,1"]))
        // Two input modes at once are rejected.
        XCTAssertThrowsError(try Sheets.Set.parse([
            "sheet-1", "A1:B2", "--row", "A,1", "--tsv",
        ]))
        XCTAssertThrowsError(try Sheets.Set.parse([
            "sheet-1", "A1:B2", "--json-rows", "[[\"a\"]]", "--tsv",
        ]))
    }

    func testSheetsSetParsesJSONRowsAndTsvModes() throws {
        let jsonCommand = try Sheets.Set.parse([
            "sheet-1", "A1:B2", "--json-rows", #"[["a","b"]]"#,
        ])
        XCTAssertEqual(jsonCommand.jsonRows, #"[["a","b"]]"#)
        XCTAssertTrue(jsonCommand.row.isEmpty)
        XCTAssertFalse(jsonCommand.tsv)

        let tsvCommand = try Sheets.Set.parse(["sheet-1", "A1:B2", "--tsv"])
        XCTAssertTrue(tsvCommand.tsv)
    }

    func testSheetsAppendParsesArgumentsAndInputMode() throws {
        let command = try Sheets.Append.parse([
            "sheet-1", "Sheet1!A1", "--row", "A,10", "--row", "B,20",
        ])
        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.range, "Sheet1!A1")
        XCTAssertEqual(command.row, ["A,10", "B,20"])
    }

    func testSheetsAppendRequiresExactlyOneInputMode() {
        XCTAssertThrowsError(try Sheets.Append.parse(["sheet-1", "A1"]))
        XCTAssertThrowsError(try Sheets.Append.parse([
            "sheet-1", "A1", "--row", "A,1", "--json-rows", "[[\"a\"]]",
        ]))
    }

    func testSheetsClearParsesArguments() throws {
        let command = try Sheets.Clear.parse(["sheet-1", "Sheet1!A1:B10"])
        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.range, "Sheet1!A1:B10")
    }

    func testSheetsClearRequiresSpreadsheetAndRange() {
        XCTAssertThrowsError(try Sheets.Clear.parse([]))
        XCTAssertThrowsError(try Sheets.Clear.parse(["sheet-1"]))
    }

    func testSheetsValuesParsesMultipleRangesAndRenderFlags() throws {
        let command = try Sheets.Values.parse([
            "sheet-1", "A1:B2", "C1:D2", "--raw",
        ])
        XCTAssertEqual(command.ranges, ["A1:B2", "C1:D2"])
        XCTAssertTrue(command.raw)
        XCTAssertFalse(command.formulas)
    }

    func testSheetsValuesRejectsRawAndFormulasTogether() {
        XCTAssertThrowsError(try Sheets.Values.parse([
            "sheet-1", "A1:B2", "--raw", "--formulas",
        ]))
        XCTAssertThrowsError(try Sheets.Values.parse(["sheet-1"]))
    }

    func testSheetsRegistersAppendAndClearSubcommands() {
        let names = Sheets.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Append"), "sheets should list Append: \(names)")
        XCTAssertTrue(names.contains("Clear"), "sheets should list Clear: \(names)")
    }

    // MARK: - Tabs

    func testSheetsRegistersTabSubcommandWithAddDeleteRename() {
        let names = Sheets.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Tab"), "sheets should list Tab: \(names)")
        let tabNames = Sheets.Tab.configuration.subcommands.map { String(describing: $0) }
        XCTAssertEqual(Set(tabNames), ["Add", "Delete", "Rename"])
    }

    func testSheetsTabAddParsesTitleAndIndex() throws {
        let command = try Sheets.Tab.Add.parse(["sheet-1", "New Tab", "--index", "2"])
        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.title, "New Tab")
        XCTAssertEqual(command.index, 2)

        let noIndex = try Sheets.Tab.Add.parse(["sheet-1", "New Tab"])
        XCTAssertNil(noIndex.index)
    }

    func testSheetsTabDeleteRequiresExactlyOneSelector() throws {
        let byId = try Sheets.Tab.Delete.parse(["sheet-1", "--sheet-id", "3"])
        XCTAssertEqual(byId.sheetId, 3)

        let byTitle = try Sheets.Tab.Delete.parse(["sheet-1", "--sheet", "Old"])
        XCTAssertEqual(byTitle.sheet, "Old")

        // Neither selector, and both selectors, are rejected.
        XCTAssertThrowsError(try Sheets.Tab.Delete.parse(["sheet-1"]))
        XCTAssertThrowsError(try Sheets.Tab.Delete.parse([
            "sheet-1", "--sheet-id", "3", "--sheet", "Old",
        ]))
    }

    func testSheetsTabRenameParsesSelectorAndNewTitle() throws {
        let command = try Sheets.Tab.Rename.parse([
            "sheet-1", "--sheet", "Old", "--to", "New",
        ])
        XCTAssertEqual(command.sheet, "Old")
        XCTAssertEqual(command.to, "New")

        // --to is required, and exactly one selector is required.
        XCTAssertThrowsError(try Sheets.Tab.Rename.parse(["sheet-1", "--sheet", "Old"]))
        XCTAssertThrowsError(try Sheets.Tab.Rename.parse(["sheet-1", "--to", "New"]))
    }

    func testSheetsChartAddParsesOptions() throws {
        let command = try Sheets.Chart.Add.parse([
            "sheet-1",
            "--range", "Sheet1!A1:C4",
            "--title", "Quarterly sales",
            "--type", "scatter",
        ])

        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.range, "Sheet1!A1:C4")
        XCTAssertEqual(command.title, "Quarterly sales")
        XCTAssertEqual(command.type, .scatter)
    }

    func testSheetsChartAddDefaultsToColumn() throws {
        let command = try Sheets.Chart.Add.parse([
            "sheet-1", "--range", "A1:B2",
        ])
        XCTAssertEqual(command.type, .column)
        XCTAssertNil(command.title)
    }

    func testSheetsChartAddRequiresSpreadsheetAndRange() {
        XCTAssertThrowsError(try Sheets.Chart.Add.parse([]))
        XCTAssertThrowsError(try Sheets.Chart.Add.parse(["sheet-1"]))
        XCTAssertThrowsError(try Sheets.Chart.Add.parse(["--range", "A1:B2"]))
    }

    func testSheetsChartAddRejectsUnknownType() {
        XCTAssertThrowsError(try Sheets.Chart.Add.parse([
            "sheet-1", "--range", "A1:B2", "--type", "pie",
        ]))
    }
}
