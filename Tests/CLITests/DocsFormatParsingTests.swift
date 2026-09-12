import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for the two formatting reads, `docs paragraph-style`
/// and `docs text-style`, and the range / segment / tab / format option group
/// they share.
final class DocsFormatParsingTests: XCTestCase {
    func testDocsRegistersTheFormatReadSubcommands() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("ParagraphStyle"), "docs should list ParagraphStyle: \(names)")
        XCTAssertTrue(names.contains("TextStyle"), "docs should list TextStyle: \(names)")
        XCTAssertEqual(Docs.ParagraphStyle.configuration.commandName, "paragraph-style")
        XCTAssertEqual(Docs.TextStyle.configuration.commandName, "text-style")
    }

    // MARK: - paragraph-style

    func testParagraphStyleDefaultsToTheWholeBodyAsATable() throws {
        let command = try Docs.ParagraphStyle.parse(["doc-1"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertNil(command.options.from)
        XCTAssertNil(command.options.to)
        XCTAssertNil(command.options.at)
        XCTAssertNil(command.options.segment)
        XCTAssertNil(command.options.tab)
        XCTAssertEqual(command.options.format, .table)
        XCTAssertNil(command.options.bounds.from)
        XCTAssertNil(command.options.bounds.to)
    }

    func testParagraphStyleParsesARange() throws {
        let command = try Docs.ParagraphStyle.parse(
            ["doc-1", "--from", "565", "--to", "722", "--format", "jsonl"])
        XCTAssertEqual(command.options.from, 565)
        XCTAssertEqual(command.options.to, 722)
        XCTAssertEqual(command.options.format, .jsonl)
        XCTAssertEqual(command.options.bounds.from, 565)
        XCTAssertEqual(command.options.bounds.to, 722)
    }

    func testParagraphStyleParsesOneOpenBound() throws {
        let fromOnly = try Docs.ParagraphStyle.parse(["doc-1", "--from", "10"])
        XCTAssertEqual(fromOnly.options.bounds.from, 10)
        XCTAssertNil(fromOnly.options.bounds.to)

        let toOnly = try Docs.ParagraphStyle.parse(["doc-1", "--to", "10"])
        XCTAssertNil(toOnly.options.bounds.from)
        XCTAssertEqual(toOnly.options.bounds.to, 10)
    }

    func testParagraphStyleAtReadsAsAOneIndexRange() throws {
        let command = try Docs.ParagraphStyle.parse(["doc-1", "--at", "622"])
        XCTAssertEqual(command.options.at, 622)
        XCTAssertEqual(command.options.bounds.from, 622)
        XCTAssertEqual(command.options.bounds.to, 623)
    }

    func testParagraphStyleRejectsAtWithFromOrTo() {
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--at", "5", "--from", "1"]))
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--at", "5", "--to", "9"]))
    }

    func testParagraphStyleRejectsAnEmptyOrNegativeRange() {
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--from", "9", "--to", "9"]))
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--from", "9", "--to", "3"]))
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--from", "-1"]))
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--to", "-1"]))
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--at", "-1"]))
    }

    func testParagraphStyleParsesSegmentAndTabButNotTogether() throws {
        let segment = try Docs.ParagraphStyle.parse(["doc-1", "--segment", "kix.h1"])
        XCTAssertEqual(segment.options.segment, "kix.h1")

        let tab = try Docs.ParagraphStyle.parse(["doc-1", "--tab", "t.0", "--at", "3"])
        XCTAssertEqual(tab.options.tab, "t.0")

        XCTAssertThrowsError(
            try Docs.ParagraphStyle.parse(["doc-1", "--tab", "t.0", "--segment", "kix.h1"]))
    }

    func testParagraphStyleRequiresADocumentIDAndAKnownFormat() {
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse([]))
        XCTAssertThrowsError(try Docs.ParagraphStyle.parse(["doc-1", "--format", "yaml"]))
    }

    // MARK: - text-style

    func testTextStyleSharesTheSameOptions() throws {
        let command = try Docs.TextStyle.parse(
            ["doc-1", "--from", "1", "--to", "6", "--segment", "kix.f1", "--format", "id"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.options.bounds.from, 1)
        XCTAssertEqual(command.options.bounds.to, 6)
        XCTAssertEqual(command.options.segment, "kix.f1")
        XCTAssertEqual(command.options.format, .id)

        let at = try Docs.TextStyle.parse(["doc-1", "--at", "7"])
        XCTAssertEqual(at.options.bounds.from, 7)
        XCTAssertEqual(at.options.bounds.to, 8)

        XCTAssertThrowsError(try Docs.TextStyle.parse(["doc-1", "--at", "7", "--to", "9"]))
        XCTAssertThrowsError(try Docs.TextStyle.parse(["doc-1", "--tab", "t.0", "--segment", "s"]))
        XCTAssertThrowsError(try Docs.TextStyle.parse([]))
    }
}
