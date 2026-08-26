import XCTest
@testable import GrahamKit

/// Offline coverage for the `sheets set` / `sheets append` input parsers. Both
/// forms must let a cell keep a comma, which the legacy comma-split form cannot.
final class SheetsRowInputTests: XCTestCase {
    // MARK: - JSON

    func testFromJSONParsesArrayOfArrays() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromJSON(#"[["Label","Value"],["A","10"]]"#),
            [["Label", "Value"], ["A", "10"]])
    }

    func testFromJSONKeepsCommasInsideCells() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromJSON(#"[["a, b","c"]]"#),
            [["a, b", "c"]])
    }

    func testFromJSONRejectsMalformedJSON() {
        assertInvalidArgument { _ = try SheetsRowInput.fromJSON("not json") }
        assertInvalidArgument { _ = try SheetsRowInput.fromJSON(#"["flat","array"]"#) }
        assertInvalidArgument { _ = try SheetsRowInput.fromJSON(#"[[1,2]]"#) }
    }

    func testFromJSONRejectsEmptyRowsAndEmptyCellsList() {
        assertInvalidArgument { _ = try SheetsRowInput.fromJSON("[]") }
        assertInvalidArgument { _ = try SheetsRowInput.fromJSON(#"[["ok"],[]]"#) }
    }

    // MARK: - Comma rows

    func testFromCommaRowsSplitsEachRowOnCommas() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromCommaRows(["Label,Value", "A,10"]),
            [["Label", "Value"], ["A", "10"]])
    }

    func testFromCommaRowsKeepsEmptyCellsAndSingleCells() throws {
        XCTAssertEqual(try SheetsRowInput.fromCommaRows(["A,,C"]), [["A", "", "C"]])
        XCTAssertEqual(try SheetsRowInput.fromCommaRows(["solo"]), [["solo"]])
    }

    func testFromCommaRowsRejectsNoRows() {
        assertInvalidArgument { _ = try SheetsRowInput.fromCommaRows([]) }
    }

    // MARK: - TSV

    func testFromTSVSplitsRowsOnNewlinesAndCellsOnTabs() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromTSV("a\tb\nc\td"),
            [["a", "b"], ["c", "d"]])
    }

    func testFromTSVKeepsCommasAndEmptyCells() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromTSV("a, b\tc\n\td"),
            [["a, b", "c"], ["", "d"]])
    }

    func testFromTSVDropsTrailingNewlineAndBlankLines() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromTSV("a\tb\n\nc\td\n"),
            [["a", "b"], ["c", "d"]])
    }

    func testFromTSVNormalizesCarriageReturns() throws {
        XCTAssertEqual(
            try SheetsRowInput.fromTSV("a\tb\r\nc\td"),
            [["a", "b"], ["c", "d"]])
    }

    func testFromTSVRejectsEmptyInput() {
        assertInvalidArgument { _ = try SheetsRowInput.fromTSV("") }
        assertInvalidArgument { _ = try SheetsRowInput.fromTSV("\n\n") }
    }

    // MARK: - Helper

    private func assertInvalidArgument(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
        }
    }
}
