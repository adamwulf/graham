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
}
