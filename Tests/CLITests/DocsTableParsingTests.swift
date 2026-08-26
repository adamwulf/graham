import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the `docs table` command group. These tests parse
/// arguments and never touch the network; the client behavior is covered by
/// `DocsTableWriteTests`. Mirrors `SlidesTableParsingTests`.
final class DocsTableParsingTests: XCTestCase {
    func testDocsRegistersTheTableSubcommand() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Table"), "docs should list a Table subcommand: \(names)")
    }

    func testDocsTableListsEverySubcommandInOrder() {
        let names = Docs.Table.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, [
            "create", "add-row", "add-column", "delete-row", "delete-column",
            "merge", "unmerge", "pin-headers",
        ])
    }

    // MARK: - create

    func testCreateParsesDimensionsAndAt() throws {
        let command = try Docs.Table.Create.parse([
            "doc-1", "--rows", "2", "--columns", "3", "--at", "5",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.rows, 2)
        XCTAssertEqual(command.columns, 3)
        XCTAssertEqual(command.at, 5)
        XCTAssertFalse(command.end)
        XCTAssertNil(command.segment)
    }

    func testCreateParsesEndSegmentAndRequireRevision() throws {
        let command = try Docs.Table.Create.parse([
            "doc-1", "--rows", "1", "--columns", "1", "--end",
            "--segment", "hdr-1", "--require-revision", "rev-1",
        ])
        XCTAssertTrue(command.end)
        XCTAssertNil(command.at)
        XCTAssertEqual(command.segment, "hdr-1")
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testCreateRejectsMissingDimensionsAndTarget() {
        // No rows/columns.
        XCTAssertThrowsError(try Docs.Table.Create.parse(["doc-1", "--at", "1"]))
        // Neither --at nor --end.
        XCTAssertThrowsError(try Docs.Table.Create.parse([
            "doc-1", "--rows", "2", "--columns", "2",
        ]))
        // Both --at and --end conflict.
        XCTAssertThrowsError(try Docs.Table.Create.parse([
            "doc-1", "--rows", "2", "--columns", "2", "--at", "1", "--end",
        ]))
        // rows/columns below one.
        XCTAssertThrowsError(try Docs.Table.Create.parse([
            "doc-1", "--rows", "0", "--columns", "2", "--at", "1",
        ]))
        XCTAssertThrowsError(try Docs.Table.Create.parse([
            "doc-1", "--rows", "2", "--columns", "0", "--at", "1",
        ]))
    }

    // MARK: - add-row / add-column

    func testAddRowParsesBelowAndAbove() throws {
        let below = try Docs.Table.AddRow.parse([
            "doc-1", "--table", "10", "--row", "2", "--column", "3", "--below",
        ])
        XCTAssertEqual(below.table, 10)
        XCTAssertEqual(below.row, 2)
        XCTAssertEqual(below.column, 3)
        XCTAssertTrue(below.below)
        XCTAssertFalse(below.above)

        let above = try Docs.Table.AddRow.parse([
            "doc-1", "--table", "10", "--row", "2", "--column", "3", "--above",
        ])
        XCTAssertTrue(above.above)
        XCTAssertFalse(above.below)
    }

    func testAddRowRejectsExclusivePairAndOneBasedErrors() {
        // Neither direction.
        XCTAssertThrowsError(try Docs.Table.AddRow.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "1",
        ]))
        // Both directions.
        XCTAssertThrowsError(try Docs.Table.AddRow.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "1", "--below", "--above",
        ]))
        // Row below one.
        XCTAssertThrowsError(try Docs.Table.AddRow.parse([
            "doc-1", "--table", "10", "--row", "0", "--column", "1", "--below",
        ]))
    }

    func testAddColumnParsesRightAndLeft() throws {
        let right = try Docs.Table.AddColumn.parse([
            "doc-1", "--table", "10", "--row", "2", "--column", "3", "--right",
        ])
        XCTAssertTrue(right.right)
        XCTAssertFalse(right.left)

        let left = try Docs.Table.AddColumn.parse([
            "doc-1", "--table", "10", "--row", "2", "--column", "3", "--left",
        ])
        XCTAssertTrue(left.left)
        XCTAssertFalse(left.right)
    }

    func testAddColumnRejectsExclusivePairAndOneBasedErrors() {
        XCTAssertThrowsError(try Docs.Table.AddColumn.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "1",
        ]))
        XCTAssertThrowsError(try Docs.Table.AddColumn.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "1", "--right", "--left",
        ]))
        XCTAssertThrowsError(try Docs.Table.AddColumn.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "0", "--right",
        ]))
    }

    // MARK: - delete-row / delete-column

    func testDeleteRowAndColumnParseAndRejectZero() throws {
        let row = try Docs.Table.DeleteRow.parse([
            "doc-1", "--table", "10", "--row", "2", "--column", "3",
        ])
        XCTAssertEqual(row.table, 10)
        XCTAssertEqual(row.row, 2)
        XCTAssertEqual(row.column, 3)

        let column = try Docs.Table.DeleteColumn.parse([
            "doc-1", "--table", "10", "--row", "2", "--column", "3",
        ])
        XCTAssertEqual(column.row, 2)
        XCTAssertEqual(column.column, 3)

        XCTAssertThrowsError(try Docs.Table.DeleteRow.parse([
            "doc-1", "--table", "10", "--row", "0", "--column", "1",
        ]))
        XCTAssertThrowsError(try Docs.Table.DeleteColumn.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "0",
        ]))
    }

    // MARK: - merge / unmerge

    func testMergeAndUnmergeParseFullRanges() throws {
        let arguments = [
            "doc-1", "--table", "10", "--row", "2", "--column", "3",
            "--row-span", "4", "--column-span", "5",
        ]
        let merge = try Docs.Table.Merge.parse(arguments)
        XCTAssertEqual(merge.table, 10)
        XCTAssertEqual(merge.row, 2)
        XCTAssertEqual(merge.column, 3)
        XCTAssertEqual(merge.rowSpan, 4)
        XCTAssertEqual(merge.columnSpan, 5)

        let unmerge = try Docs.Table.Unmerge.parse(arguments)
        XCTAssertEqual(unmerge.row, 2)
        XCTAssertEqual(unmerge.column, 3)
        XCTAssertEqual(unmerge.rowSpan, 4)
        XCTAssertEqual(unmerge.columnSpan, 5)
    }

    func testMergeAndUnmergeRejectNonPositiveSpans() {
        XCTAssertThrowsError(try Docs.Table.Merge.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "1",
            "--row-span", "0", "--column-span", "1",
        ]))
        XCTAssertThrowsError(try Docs.Table.Unmerge.parse([
            "doc-1", "--table", "10", "--row", "1", "--column", "1",
            "--row-span", "1", "--column-span", "0",
        ]))
    }

    // MARK: - pin-headers

    func testPinHeadersParsesCountIncludingZero() throws {
        let pin = try Docs.Table.PinHeaders.parse([
            "doc-1", "--table", "10", "--count", "2",
        ])
        XCTAssertEqual(pin.table, 10)
        XCTAssertEqual(pin.count, 2)

        // 0 unpins and is valid.
        let unpin = try Docs.Table.PinHeaders.parse([
            "doc-1", "--table", "10", "--count", "0",
        ])
        XCTAssertEqual(unpin.count, 0)
    }

    func testPinHeadersRejectsNegativeCount() {
        XCTAssertThrowsError(try Docs.Table.PinHeaders.parse([
            "doc-1", "--table", "10", "--count", "-1",
        ]))
    }
}
