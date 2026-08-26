import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the Phase 7 `docs header`, `docs footer`, and
/// `docs footnote` commands. These tests parse arguments and never touch the
/// network; the client behavior is covered by `DocsWriteTests`. Mirrors
/// `DocsStructureParsingTests` and `DocsWriteParsingTests`.
final class DocsHeaderFooterParsingTests: XCTestCase {
    func testDocsRegistersTheHeaderFooterFootnoteSubcommands() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        for expected in ["Header", "Footer", "Footnote"] {
            XCTAssertTrue(names.contains(expected), "docs should list \(expected): \(names)")
        }
    }

    // MARK: - header

    func testDocsHeaderListsCreateAndDelete() {
        let names = Docs.Header.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["create", "delete"])
    }

    func testHeaderCreateParsesAtAndRequireRevision() throws {
        let command = try Docs.Header.Create.parse([
            "doc-1", "--at", "12", "--require-revision", "rev-1",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.at, 12)
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testHeaderCreateDefaultsAtToNil() throws {
        let command = try Docs.Header.Create.parse(["doc-1"])
        XCTAssertNil(command.at)
        XCTAssertNil(command.requireRevision)
    }

    func testHeaderCreateRequiresADocumentId() {
        XCTAssertThrowsError(try Docs.Header.Create.parse([]))
    }

    func testHeaderDeleteParsesArguments() throws {
        let command = try Docs.Header.Delete.parse([
            "doc-1", "kix.hdr1", "--require-revision", "rev-3",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.headerID, "kix.hdr1")
        XCTAssertEqual(command.requireRevision, "rev-3")
    }

    func testHeaderDeleteRequiresANonEmptyId() {
        XCTAssertThrowsError(try Docs.Header.Delete.parse([]))
        XCTAssertThrowsError(try Docs.Header.Delete.parse(["doc-1"]))
        // Empty header id.
        XCTAssertThrowsError(try Docs.Header.Delete.parse(["doc-1", ""]))
    }

    // MARK: - footer

    func testDocsFooterListsCreateAndDelete() {
        let names = Docs.Footer.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["create", "delete"])
    }

    func testFooterCreateParsesAtAndRequireRevision() throws {
        let command = try Docs.Footer.Create.parse([
            "doc-1", "--at", "7", "--require-revision", "rev-2",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.at, 7)
        XCTAssertEqual(command.requireRevision, "rev-2")
    }

    func testFooterCreateDefaultsAtToNil() throws {
        let command = try Docs.Footer.Create.parse(["doc-1"])
        XCTAssertNil(command.at)
        XCTAssertNil(command.requireRevision)
    }

    func testFooterDeleteParsesArguments() throws {
        let command = try Docs.Footer.Delete.parse([
            "doc-1", "kix.ftr1", "--require-revision", "rev-4",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.footerID, "kix.ftr1")
        XCTAssertEqual(command.requireRevision, "rev-4")
    }

    func testFooterDeleteRequiresANonEmptyId() {
        XCTAssertThrowsError(try Docs.Footer.Delete.parse([]))
        XCTAssertThrowsError(try Docs.Footer.Delete.parse(["doc-1"]))
        // Empty footer id.
        XCTAssertThrowsError(try Docs.Footer.Delete.parse(["doc-1", ""]))
    }

    // MARK: - footnote

    func testFootnoteParsesAt() throws {
        let command = try Docs.Footnote.parse(["doc-1", "--at", "5"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.at, 5)
        XCTAssertFalse(command.end)
        XCTAssertNil(command.text)
    }

    func testFootnoteParsesEndAndText() throws {
        let command = try Docs.Footnote.parse([
            "doc-1", "--end", "--text", "See note", "--require-revision", "rev-6",
        ])
        XCTAssertTrue(command.end)
        XCTAssertNil(command.at)
        XCTAssertEqual(command.text, "See note")
        XCTAssertEqual(command.requireRevision, "rev-6")
    }

    func testFootnoteRejectsBothAtAndEndAndNeither() {
        // Both --at and --end.
        XCTAssertThrowsError(try Docs.Footnote.parse(["doc-1", "--at", "5", "--end"]))
        // Neither --at nor --end.
        XCTAssertThrowsError(try Docs.Footnote.parse(["doc-1"]))
    }

    func testFootnoteRejectsEmptyText() {
        XCTAssertThrowsError(try Docs.Footnote.parse(["doc-1", "--at", "5", "--text", ""]))
    }
}
