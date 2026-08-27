import XCTest
import GrahamKit
@testable import graham

final class DocsReadParsingTests: XCTestCase {
    func testDocsRegistersTheStructureSubcommand() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(
            names.contains("Structure"), "docs should list a Structure subcommand: \(names)")
    }

    func testDocsStructureParsesTheDocumentID() throws {
        let command = try Docs.Structure.parse(["doc-1"])
        XCTAssertEqual(command.documentID, "doc-1")
    }

    func testDocsStructureDefaultsFormatToTable() throws {
        let command = try Docs.Structure.parse(["doc-1"])
        XCTAssertEqual(command.format, .table)
    }

    func testDocsStructureParsesTheFormat() throws {
        let command = try Docs.Structure.parse(["doc-1", "--format", "jsonl"])
        XCTAssertEqual(command.format, .jsonl)
    }

    func testDocsStructureRequiresADocumentID() {
        XCTAssertThrowsError(try Docs.Structure.parse([]))
    }

    // MARK: - Images

    func testDocsRegistersTheImagesSubcommand() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(
            names.contains("Images"), "docs should list an Images subcommand: \(names)")
    }

    func testDocsImagesDefaultsToListing() throws {
        let command = try Docs.Images.parse(["doc-1"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertNil(command.download)
        XCTAssertEqual(command.format, .table)
    }

    func testDocsImagesParsesDownloadDirectoryLongAndShort() throws {
        let long = try Docs.Images.parse(["doc-1", "--download", "/tmp/out"])
        XCTAssertEqual(long.download, "/tmp/out")

        let short = try Docs.Images.parse(["doc-1", "-d", "/tmp/out"])
        XCTAssertEqual(short.download, "/tmp/out")
    }

    func testDocsImagesParsesFormat() throws {
        let command = try Docs.Images.parse(["doc-1", "--format", "id"])
        XCTAssertEqual(command.format, .id)
    }

    func testDocsImagesRequiresADocumentID() {
        XCTAssertThrowsError(try Docs.Images.parse([]))
    }

    // MARK: - docs cat

    func testDocsCatDefaultsToPlainText() throws {
        let command = try Docs.Cat.parse(["doc-1"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertFalse(command.json)
        XCTAssertFalse(command.markdown)
    }

    func testDocsCatParsesTheMarkdownFlag() throws {
        let command = try Docs.Cat.parse(["doc-1", "--markdown"])
        XCTAssertTrue(command.markdown)
        XCTAssertFalse(command.json)
    }

    func testDocsCatRejectsJsonAndMarkdownTogether() {
        XCTAssertThrowsError(try Docs.Cat.parse(["doc-1", "--json", "--markdown"]))
    }

    // MARK: - tab-aware reads

    func testDocsStructureParsesTabId() throws {
        let command = try Docs.Structure.parse(["doc-1", "--tab", "t.0"])
        XCTAssertEqual(command.tab, "t.0")
    }

    func testDocsCatParsesTabId() throws {
        let command = try Docs.Cat.parse(["doc-1", "--tab", "t.0"])
        XCTAssertEqual(command.tab, "t.0")
    }

    func testDocsCatRejectsMarkdownWithTab() {
        XCTAssertThrowsError(try Docs.Cat.parse(["doc-1", "--markdown", "--tab", "t.0"]))
    }

    func testDocsTabListParsesDocumentAndFormat() throws {
        let command = try Docs.Tab.List.parse(["doc-1", "--format", "json"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.format, .json)
    }
}
