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

    // MARK: - Grid shape

    func testSheetsRegistersFreezeAndResizeSubcommands() {
        let names = Sheets.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Freeze"), "sheets should list Freeze: \(names)")
        XCTAssertTrue(names.contains("Resize"), "sheets should list Resize: \(names)")
    }

    func testSheetsFreezeParsesCountsAndSelector() throws {
        let command = try Sheets.Freeze.parse([
            "sheet-1", "--rows", "1", "--columns", "2", "--sheet-id", "0",
        ])
        XCTAssertEqual(command.rows, 1)
        XCTAssertEqual(command.columns, 2)
        XCTAssertEqual(command.sheetId, 0)
    }

    func testSheetsFreezeRequiresACountAndAtMostOneSelector() {
        // No counts is rejected.
        XCTAssertThrowsError(try Sheets.Freeze.parse(["sheet-1"]))
        // Two selectors are rejected.
        XCTAssertThrowsError(try Sheets.Freeze.parse([
            "sheet-1", "--rows", "1", "--sheet-id", "0", "--sheet", "Data",
        ]))
        // No selector is allowed (defaults to the first sheet).
        XCTAssertNoThrow(try Sheets.Freeze.parse(["sheet-1", "--rows", "1"]))
    }

    func testSheetsResizeParsesDimensionRangeAndPixels() throws {
        let command = try Sheets.Resize.parse([
            "sheet-1", "--dimension", "columns", "--from", "2", "--to", "3", "--pixels", "120",
        ])
        XCTAssertEqual(command.dimension, .columns)
        XCTAssertEqual(command.from, 2)
        XCTAssertEqual(command.to, 3)
        XCTAssertEqual(command.pixels, 120)

        let single = try Sheets.Resize.parse([
            "sheet-1", "--dimension", "rows", "--from", "2", "--pixels", "40",
        ])
        XCTAssertNil(single.to)
    }

    func testSheetsResizeRejectsMissingOptionsAndUnknownDimension() {
        XCTAssertThrowsError(try Sheets.Resize.parse(["sheet-1", "--from", "1", "--pixels", "10"]))
        XCTAssertThrowsError(try Sheets.Resize.parse([
            "sheet-1", "--dimension", "diagonal", "--from", "1", "--pixels", "10",
        ]))
        XCTAssertThrowsError(try Sheets.Resize.parse([
            "sheet-1", "--dimension", "rows", "--pixels", "10",
        ]))
    }

    // MARK: - Cell formatting

    func testSheetsRegistersFormatSubcommand() {
        let names = Sheets.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Format"), "sheets should list Format: \(names)")
    }

    func testSheetsFormatParsesEveryAspect() throws {
        let command = try Sheets.Format.parse([
            "sheet-1", "Sheet1!A1:B1",
            "--bold", "--background", "#FFCC00",
            "--number-format", "#,##0.00", "--align", "center",
        ])
        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.range, "Sheet1!A1:B1")
        XCTAssertEqual(command.bold, true)
        XCTAssertEqual(command.background, "#FFCC00")
        XCTAssertEqual(command.numberFormat, "#,##0.00")
        XCTAssertEqual(command.align, .center)
    }

    func testSheetsFormatParsesNoBoldAndTextAndNumberType() throws {
        let command = try Sheets.Format.parse([
            "sheet-1", "A1:B1",
            "--no-bold",
            "--text-color", "#202124",
            "--font", "Roboto",
            "--font-size", "14",
            "--number-type", "currency",
        ])
        XCTAssertEqual(command.bold, false)
        XCTAssertEqual(command.textColor, "#202124")
        XCTAssertEqual(command.font, "Roboto")
        XCTAssertEqual(command.fontSize, 14)
        XCTAssertEqual(command.numberType, .currency)
    }

    func testSheetsFormatParsesClearFlags() throws {
        let command = try Sheets.Format.parse([
            "sheet-1", "A1:B1",
            "--clear-background", "--clear-number-format", "--clear-align",
        ])
        XCTAssertTrue(command.clearBackground)
        XCTAssertTrue(command.clearNumberFormat)
        XCTAssertTrue(command.clearAlign)
        XCTAssertNil(command.bold)
    }

    func testSheetsFormatRequiresAtLeastOneAspectAndAValidAlignment() {
        XCTAssertThrowsError(try Sheets.Format.parse(["sheet-1", "A1:B1"]))
        XCTAssertThrowsError(try Sheets.Format.parse([
            "sheet-1", "A1:B1", "--align", "middle",
        ]))
    }

    func testSheetsFormatRejectsSettingAndClearingTheSameAspect() {
        XCTAssertThrowsError(try Sheets.Format.parse([
            "sheet-1", "A1:B1", "--background", "#FFCC00", "--clear-background",
        ]))
        XCTAssertThrowsError(try Sheets.Format.parse([
            "sheet-1", "A1:B1", "--align", "left", "--clear-align",
        ]))
    }

    func testSheetsRegistersBorderSubcommand() {
        let names = Sheets.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Border"), "sheets should list Border: \(names)")
    }

    func testSheetsBorderParsesSidesStyleAndColor() throws {
        let command = try Sheets.Border.parse([
            "sheet-1", "Sheet1!A1:B4",
            "--all", "--style", "solid_thick", "--color", "#000000",
        ])
        XCTAssertEqual(command.spreadsheetID, "sheet-1")
        XCTAssertEqual(command.range, "Sheet1!A1:B4")
        XCTAssertTrue(command.all)
        XCTAssertEqual(command.style, .solidThick)
        XCTAssertEqual(command.color, "#000000")
    }

    func testSheetsBorderRequiresAStyleAndAtLeastOneSide() {
        // Missing --style.
        XCTAssertThrowsError(try Sheets.Border.parse(["sheet-1", "A1:B4", "--top"]))
        // A style but no side.
        XCTAssertThrowsError(try Sheets.Border.parse(["sheet-1", "A1:B4", "--style", "solid"]))
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
        // pie is not a --type; it is the --pie flag.
        XCTAssertThrowsError(try Sheets.Chart.Add.parse([
            "sheet-1", "--range", "A1:B2", "--type", "pie",
        ]))
    }

    func testSheetsChartAddParsesComboPieAndOverlay() throws {
        let combo = try Sheets.Chart.Add.parse([
            "sheet-1", "--range", "A1:C4", "--type", "combo",
        ])
        XCTAssertEqual(combo.type, .combo)

        let overlay = try Sheets.Chart.Add.parse([
            "sheet-1", "--range", "A1:B4", "--pie",
            "--anchor", "Sheet2!D2", "--width", "300", "--height", "200",
        ])
        XCTAssertTrue(overlay.pie)
        XCTAssertEqual(overlay.anchor, "Sheet2!D2")
        XCTAssertEqual(overlay.width, 300)
        XCTAssertEqual(overlay.height, 200)
    }

    func testSheetsChartAddRejectsSizeWithoutAnchor() {
        XCTAssertThrowsError(try Sheets.Chart.Add.parse([
            "sheet-1", "--range", "A1:B4", "--width", "300",
        ]))
    }

    func testSheetsChartUpdateAndDeleteParse() throws {
        let update = try Sheets.Chart.Update.parse([
            "sheet-1", "--chart-id", "42", "--range", "A1:B4", "--title", "New",
        ])
        XCTAssertEqual(update.chartId, 42)
        XCTAssertEqual(update.range, "A1:B4")
        XCTAssertEqual(update.title, "New")

        let delete = try Sheets.Chart.Delete.parse(["sheet-1", "--chart-id", "42"])
        XCTAssertEqual(delete.chartId, 42)

        // chartId is required for both.
        XCTAssertThrowsError(try Sheets.Chart.Delete.parse(["sheet-1"]))
        XCTAssertThrowsError(try Sheets.Chart.Update.parse(["sheet-1", "--range", "A1:B4"]))
    }

    func testSheetsChartRegistersAddUpdateDelete() {
        let names = Sheets.Chart.configuration.subcommands.map { String(describing: $0) }
        XCTAssertEqual(Set(names), ["Add", "Update", "Delete"])
    }
}
