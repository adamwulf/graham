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

    func testSheetsSetRequiresArgumentsAndAtLeastOneRow() {
        XCTAssertThrowsError(try Sheets.Set.parse([]))
        XCTAssertThrowsError(try Sheets.Set.parse(["sheet-1", "A1:B2"]))
        XCTAssertThrowsError(try Sheets.Set.parse(["sheet-1", "--row", "A,1"]))
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
