import ArgumentParser
import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for the two formatting reads, `docs paragraph get`
/// and `docs style get`, the get/set group shape they share with the setters,
/// and the range / segment / tab / format option group.
final class DocsFormatParsingTests: XCTestCase {
    func testParagraphAndStyleAreGetSetGroups() {
        // A formatting noun is a group with `get` (read) and `set` (write).
        let groups: [(any ParsableCommand.Type, String)] = [
            (Docs.Paragraph.self, "paragraph"), (Docs.Style.self, "style"),
        ]
        for (group, name) in groups {
            XCTAssertEqual(group.configuration.commandName, name)
            let subcommands = group.configuration.subcommands.map { $0.configuration.commandName }
            XCTAssertEqual(subcommands, ["get", "set"], "\(name) should be a get/set group")
        }
        XCTAssertEqual(Docs.Paragraph.Get.configuration.commandName, "get")
        XCTAssertEqual(Docs.Paragraph.Set.configuration.commandName, "set")
        XCTAssertEqual(Docs.Style.Get.configuration.commandName, "get")
        XCTAssertEqual(Docs.Style.Set.configuration.commandName, "set")
        // The old flat read names are gone.
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertFalse(names.contains("ParagraphStyle"), names.joined(separator: ","))
        XCTAssertFalse(names.contains("TextStyle"), names.joined(separator: ","))
    }

    func testGetAndSetParseThroughTheGroup() throws {
        let get = try Docs.Paragraph.parseAsRoot(["get", "doc-1", "--at", "5"])
        XCTAssertTrue(get is Docs.Paragraph.Get, "\(type(of: get))")
        let set = try Docs.Paragraph.parseAsRoot(["set", "doc-1", "--from", "1", "--to", "9", "--align", "center"])
        XCTAssertTrue(set is Docs.Paragraph.Set, "\(type(of: set))")
        let styleGet = try Docs.Style.parseAsRoot(["get", "doc-1"])
        XCTAssertTrue(styleGet is Docs.Style.Get, "\(type(of: styleGet))")
        let styleSet = try Docs.Style.parseAsRoot(["set", "doc-1", "--from", "1", "--to", "9", "--bold"])
        XCTAssertTrue(styleSet is Docs.Style.Set, "\(type(of: styleSet))")
        // Without a verb the group has nothing to run: no implicit default.
        XCTAssertThrowsError(try Docs.Paragraph.parseAsRoot(["doc-1", "--at", "5"]))
    }

    // MARK: - paragraph get

    func testParagraphStyleDefaultsToTheWholeBodyAsATable() throws {
        let command = try Docs.Paragraph.Get.parse(["doc-1"])
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
        let command = try Docs.Paragraph.Get.parse(
            ["doc-1", "--from", "565", "--to", "722", "--format", "jsonl"])
        XCTAssertEqual(command.options.from, 565)
        XCTAssertEqual(command.options.to, 722)
        XCTAssertEqual(command.options.format, .jsonl)
        XCTAssertEqual(command.options.bounds.from, 565)
        XCTAssertEqual(command.options.bounds.to, 722)
    }

    func testParagraphStyleParsesOneOpenBound() throws {
        let fromOnly = try Docs.Paragraph.Get.parse(["doc-1", "--from", "10"])
        XCTAssertEqual(fromOnly.options.bounds.from, 10)
        XCTAssertNil(fromOnly.options.bounds.to)

        let toOnly = try Docs.Paragraph.Get.parse(["doc-1", "--to", "10"])
        XCTAssertNil(toOnly.options.bounds.from)
        XCTAssertEqual(toOnly.options.bounds.to, 10)
    }

    func testParagraphStyleAtReadsAsAOneIndexRange() throws {
        let command = try Docs.Paragraph.Get.parse(["doc-1", "--at", "622"])
        XCTAssertEqual(command.options.at, 622)
        XCTAssertEqual(command.options.bounds.from, 622)
        XCTAssertEqual(command.options.bounds.to, 623)
    }

    func testParagraphStyleRejectsAtWithFromOrTo() {
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--at", "5", "--from", "1"]))
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--at", "5", "--to", "9"]))
    }

    func testParagraphStyleRejectsAnEmptyOrNegativeRange() {
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--from", "9", "--to", "9"]))
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--from", "9", "--to", "3"]))
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--from", "-1"]))
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--to", "-1"]))
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--at", "-1"]))
    }

    func testParagraphStyleParsesSegmentAndTabButNotTogether() throws {
        let segment = try Docs.Paragraph.Get.parse(["doc-1", "--segment", "kix.h1"])
        XCTAssertEqual(segment.options.segment, "kix.h1")

        let tab = try Docs.Paragraph.Get.parse(["doc-1", "--tab", "t.0", "--at", "3"])
        XCTAssertEqual(tab.options.tab, "t.0")

        XCTAssertThrowsError(
            try Docs.Paragraph.Get.parse(["doc-1", "--tab", "t.0", "--segment", "kix.h1"]))
    }

    func testParagraphStyleRequiresADocumentIDAndAKnownFormat() {
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse([]))
        XCTAssertThrowsError(try Docs.Paragraph.Get.parse(["doc-1", "--format", "yaml"]))
    }

    // MARK: - style get

    func testTextStyleSharesTheSameOptions() throws {
        let command = try Docs.Style.Get.parse(
            ["doc-1", "--from", "1", "--to", "6", "--segment", "kix.f1", "--format", "id"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.options.bounds.from, 1)
        XCTAssertEqual(command.options.bounds.to, 6)
        XCTAssertEqual(command.options.segment, "kix.f1")
        XCTAssertEqual(command.options.format, .id)

        let at = try Docs.Style.Get.parse(["doc-1", "--at", "7"])
        XCTAssertEqual(at.options.bounds.from, 7)
        XCTAssertEqual(at.options.bounds.to, 8)

        XCTAssertThrowsError(try Docs.Style.Get.parse(["doc-1", "--at", "7", "--to", "9"]))
        XCTAssertThrowsError(try Docs.Style.Get.parse(["doc-1", "--tab", "t.0", "--segment", "s"]))
        XCTAssertThrowsError(try Docs.Style.Get.parse([]))
    }
}
