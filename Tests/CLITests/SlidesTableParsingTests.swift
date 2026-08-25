import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the `slides table` command group.
final class SlidesTableParsingTests: XCTestCase {
    func testSlidesRegistersTableAfterStyle() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        let style = names.firstIndex(of: "style")
        let table = names.firstIndex(of: "table")
        XCTAssertNotNil(style)
        XCTAssertEqual(table, style.map { $0 + 1 })
    }

    func testSlidesTableListsEverySubcommand() {
        let names = Slides.Table.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, [
            "insert-rows", "insert-columns", "delete-row", "delete-column",
            "merge", "unmerge", "style-cells", "row-height", "column-width", "borders",
        ])
    }

    func testInsertRowsParsesBelowDefaultAndAboveFull() throws {
        let defaults = try Slides.Table.InsertRows.parse([
            "deck", "table", "--below", "2",
        ])
        XCTAssertEqual(defaults.below, 2)
        XCTAssertNil(defaults.above)
        XCTAssertEqual(defaults.count, 1)

        let full = try Slides.Table.InsertRows.parse([
            "deck", "table", "--above", "3", "--count", "20",
        ])
        XCTAssertNil(full.below)
        XCTAssertEqual(full.above, 3)
        XCTAssertEqual(full.count, 20)
    }

    func testInsertRowsRejectsExclusivePairCountAndOneBasedErrors() {
        XCTAssertThrowsError(try Slides.Table.InsertRows.parse(["deck", "table"]))
        XCTAssertThrowsError(try Slides.Table.InsertRows.parse([
            "deck", "table", "--below", "1", "--above", "2",
        ]))
        XCTAssertThrowsError(try Slides.Table.InsertRows.parse([
            "deck", "table", "--below", "0",
        ]))
        XCTAssertThrowsError(try Slides.Table.InsertRows.parse([
            "deck", "table", "--below", "1", "--count", "21",
        ]))
    }

    func testInsertColumnsParsesRightDefaultAndLeftFull() throws {
        let defaults = try Slides.Table.InsertColumns.parse([
            "deck", "table", "--right-of", "2",
        ])
        XCTAssertEqual(defaults.rightOf, 2)
        XCTAssertNil(defaults.leftOf)
        XCTAssertEqual(defaults.count, 1)

        let full = try Slides.Table.InsertColumns.parse([
            "deck", "table", "--left-of", "3", "--count", "4",
        ])
        XCTAssertNil(full.rightOf)
        XCTAssertEqual(full.leftOf, 3)
        XCTAssertEqual(full.count, 4)
    }

    func testInsertColumnsRejectsExclusivePairAndCountErrors() {
        XCTAssertThrowsError(try Slides.Table.InsertColumns.parse(["deck", "table"]))
        XCTAssertThrowsError(try Slides.Table.InsertColumns.parse([
            "deck", "table", "--right-of", "1", "--left-of", "2",
        ]))
        XCTAssertThrowsError(try Slides.Table.InsertColumns.parse([
            "deck", "table", "--right-of", "1", "--count", "0",
        ]))
    }

    func testDeleteRowAndColumnParseAndRejectZero() throws {
        let row = try Slides.Table.DeleteRow.parse(["deck", "table", "--row", "2"])
        XCTAssertEqual(row.presentationID, "deck")
        XCTAssertEqual(row.tableID, "table")
        XCTAssertEqual(row.row, 2)
        let column = try Slides.Table.DeleteColumn.parse([
            "deck", "table", "--column", "3",
        ])
        XCTAssertEqual(column.column, 3)
        XCTAssertThrowsError(try Slides.Table.DeleteRow.parse([
            "deck", "table", "--row", "0",
        ]))
        XCTAssertThrowsError(try Slides.Table.DeleteColumn.parse([
            "deck", "table", "--column", "0",
        ]))
    }

    func testMergeAndUnmergeParseFullRanges() throws {
        let arguments = [
            "deck", "table", "--row", "2", "--column", "3",
            "--row-span", "4", "--column-span", "5",
        ]
        let merge = try Slides.Table.Merge.parse(arguments)
        XCTAssertEqual(merge.row, 2)
        XCTAssertEqual(merge.column, 3)
        XCTAssertEqual(merge.rowSpan, 4)
        XCTAssertEqual(merge.columnSpan, 5)
        let unmerge = try Slides.Table.Unmerge.parse(arguments)
        XCTAssertEqual(unmerge.row, 2)
        XCTAssertEqual(unmerge.column, 3)
        XCTAssertEqual(unmerge.rowSpan, 4)
        XCTAssertEqual(unmerge.columnSpan, 5)
    }

    func testMergeAndUnmergeRequirePositiveCompleteRanges() {
        XCTAssertThrowsError(try Slides.Table.Merge.parse([
            "deck", "table", "--row", "1", "--column", "1",
            "--row-span", "0", "--column-span", "1",
        ]))
        XCTAssertThrowsError(try Slides.Table.Unmerge.parse([
            "deck", "table", "--row", "1", "--column", "1",
            "--row-span", "1",
        ]))
    }

    func testStyleCellsParsesWholeTableDefaults() throws {
        let command = try Slides.Table.StyleCells.parse([
            "deck", "table", "--align", "top",
        ])
        XCTAssertNil(command.range.row)
        XCTAssertNil(command.range.column)
        XCTAssertNil(command.range.rowSpan)
        XCTAssertNil(command.range.columnSpan)
        XCTAssertEqual(command.align?.contentAlignment, .top)
        XCTAssertFalse(command.noFill)
    }

    func testStyleCellsParsesEveryFlagAndRange() throws {
        let command = try Slides.Table.StyleCells.parse([
            "deck", "table", "--row", "2", "--column", "3",
            "--row-span", "4", "--column-span", "5",
            "--fill", "#FF0000", "--fill-alpha", "0.5", "--align", "middle",
        ])
        XCTAssertEqual(command.range.row, 2)
        XCTAssertEqual(command.range.column, 3)
        XCTAssertEqual(command.range.rowSpan, 4)
        XCTAssertEqual(command.range.columnSpan, 5)
        XCTAssertEqual(command.fill, "#FF0000")
        XCTAssertEqual(command.fillAlpha, 0.5)
        XCTAssertEqual(command.align?.contentAlignment, .middle)
    }

    func testStyleCellsRejectsNoFlagsExclusiveFillAndBadRanges() {
        XCTAssertThrowsError(try Slides.Table.StyleCells.parse(["deck", "table"]))
        XCTAssertThrowsError(try Slides.Table.StyleCells.parse([
            "deck", "table", "--no-fill", "--fill", "#F00",
        ]))
        XCTAssertThrowsError(try Slides.Table.StyleCells.parse([
            "deck", "table", "--row-span", "2", "--no-fill",
        ]))
        XCTAssertThrowsError(try Slides.Table.StyleCells.parse([
            "deck", "table", "--row", "1", "--column", "1",
            "--column-span", "0", "--no-fill",
        ]))
    }

    func testRowHeightParsesDefaultAndMultipleRows() throws {
        let defaults = try Slides.Table.RowHeight.parse([
            "deck", "table", "--min-height", "20",
        ])
        XCTAssertEqual(defaults.minHeight, 20)
        XCTAssertEqual(defaults.rows, [])
        let full = try Slides.Table.RowHeight.parse([
            "deck", "table", "--min-height", "24", "--rows", "1", "3", "5",
        ])
        XCTAssertEqual(full.rows, [1, 3, 5])
        XCTAssertThrowsError(try Slides.Table.RowHeight.parse([
            "deck", "table", "--min-height", "0",
        ]))
    }

    func testColumnWidthParsesDefaultAndMultipleColumns() throws {
        let defaults = try Slides.Table.ColumnWidth.parse([
            "deck", "table", "--width", "32",
        ])
        XCTAssertEqual(defaults.width, 32)
        XCTAssertEqual(defaults.columns, [])
        let full = try Slides.Table.ColumnWidth.parse([
            "deck", "table", "--width", "72", "--columns", "1", "2", "4",
        ])
        XCTAssertEqual(full.columns, [1, 2, 4])
        XCTAssertThrowsError(try Slides.Table.ColumnWidth.parse([
            "deck", "table", "--width", "31",
        ]))
    }

    func testBordersParsesWholeTableDefaults() throws {
        let command = try Slides.Table.Borders.parse([
            "deck", "table", "--dash", "solid",
        ])
        XCTAssertNil(command.range.row)
        XCTAssertEqual(command.position.borderPosition, .all)
        XCTAssertEqual(command.dash?.dashStyle, .solid)
    }

    func testBordersParsesEveryFlagAndKebabPosition() throws {
        let command = try Slides.Table.Borders.parse([
            "deck", "table", "--row", "2", "--column", "3",
            "--row-span", "4", "--column-span", "5",
            "--position", "inner-horizontal", "--color", "accent1",
            "--alpha", "0.5", "--weight", "2", "--dash", "long-dash-dot",
        ])
        XCTAssertEqual(command.range.row, 2)
        XCTAssertEqual(command.range.column, 3)
        XCTAssertEqual(command.position.borderPosition, .innerHorizontal)
        XCTAssertEqual(command.color, "accent1")
        XCTAssertEqual(command.alpha, 0.5)
        XCTAssertEqual(command.weight, 2)
        XCTAssertEqual(command.dash?.dashStyle, .longDashDot)
    }

    func testBordersRejectsNoStyleBadRangeAndBadValues() {
        XCTAssertThrowsError(try Slides.Table.Borders.parse(["deck", "table"]))
        XCTAssertThrowsError(try Slides.Table.Borders.parse([
            "deck", "table", "--row", "1", "--color", "#F00",
        ]))
        XCTAssertThrowsError(try Slides.Table.Borders.parse([
            "deck", "table", "--alpha", "2",
        ]))
        XCTAssertThrowsError(try Slides.Table.Borders.parse([
            "deck", "table", "--weight", "0",
        ]))
        XCTAssertThrowsError(try Slides.Table.Borders.parse([
            "deck", "table", "--dash", "DASH_DOT",
        ]))
    }

    func testTableBorderPositionArgumentMapsAllKebabCases() throws {
        let cases: [(String, TableBorderPosition)] = [
            ("all", .all), ("bottom", .bottom), ("inner", .inner),
            ("inner-horizontal", .innerHorizontal), ("inner-vertical", .innerVertical),
            ("left", .left), ("outer", .outer), ("right", .right), ("top", .top),
        ]
        for (name, expected) in cases {
            let command = try Slides.Table.Borders.parse([
                "deck", "table", "--position", name, "--dash", "solid",
            ])
            XCTAssertEqual(command.position.borderPosition, expected)
        }
    }
}
