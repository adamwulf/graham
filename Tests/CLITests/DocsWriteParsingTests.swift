import XCTest
import GrahamKit
@testable import graham

final class DocsWriteParsingTests: XCTestCase {
    func testDocsCreateParsesTheTitle() throws {
        let command = try Docs.Create.parse(["My New Doc"])
        XCTAssertEqual(command.title, "My New Doc")
    }

    func testDocsCreateRequiresATitle() {
        XCTAssertThrowsError(try Docs.Create.parse([]))
    }

    func testDocsRegistersTheCreateSubcommand() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Create"), "docs should list a Create subcommand: \(names)")
    }

    func testDocsInsertParsesTextAndIndex() throws {
        let command = try Docs.Insert.parse([
            "doc-1",
            "--text", "Hello, world",
            "--at", "5",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.text, "Hello, world")
        XCTAssertEqual(command.at, 5)
    }

    func testDocsInsertRequiresDocumentTextAndIndex() {
        XCTAssertThrowsError(try Docs.Insert.parse([]))
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1", "--text", "hi"]))
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1", "--at", "1"]))
    }

    func testDocsInsertParsesRequireRevision() throws {
        let command = try Docs.Insert.parse([
            "doc-1", "--text", "hi", "--at", "1", "--require-revision", "rev-7",
        ])
        XCTAssertEqual(command.requireRevision, "rev-7")
    }

    func testDocsInsertDefaultsRequireRevisionToNil() throws {
        let command = try Docs.Insert.parse(["doc-1", "--text", "hi", "--at", "1"])
        XCTAssertNil(command.requireRevision)
    }

    func testDocsDeleteParsesRequireRevision() throws {
        let command = try Docs.Delete.parse([
            "doc-1", "--from", "1", "--to", "4", "--require-revision", "rev-8",
        ])
        XCTAssertEqual(command.requireRevision, "rev-8")
    }

    func testDocsReplaceParsesRequireRevision() throws {
        let command = try Docs.Replace.parse([
            "doc-1", "--find", "a", "--replace", "b", "--require-revision", "rev-9",
        ])
        XCTAssertEqual(command.requireRevision, "rev-9")
    }

    func testDocsDeleteParsesRange() throws {
        let command = try Docs.Delete.parse([
            "doc-1",
            "--from", "3",
            "--to", "9",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 3)
        XCTAssertEqual(command.to, 9)
    }

    func testDocsDeleteRequiresDocumentAndBothBounds() {
        XCTAssertThrowsError(try Docs.Delete.parse([]))
        XCTAssertThrowsError(try Docs.Delete.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Delete.parse(["doc-1", "--from", "3"]))
        XCTAssertThrowsError(try Docs.Delete.parse(["doc-1", "--to", "9"]))
    }

    func testDocsReplaceParsesFindReplaceAndMatchCase() throws {
        let command = try Docs.Replace.parse([
            "doc-1",
            "--find", "old",
            "--replace", "new",
            "--match-case",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.find, "old")
        XCTAssertEqual(command.replace, "new")
        XCTAssertTrue(command.matchCase)
    }

    func testDocsReplaceDefaultsMatchCaseOff() throws {
        let command = try Docs.Replace.parse([
            "doc-1", "--find", "old", "--replace", "new",
        ])
        XCTAssertFalse(command.matchCase)
    }

    func testDocsReplaceRequiresDocumentFindAndReplace() {
        XCTAssertThrowsError(try Docs.Replace.parse([]))
        XCTAssertThrowsError(try Docs.Replace.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Replace.parse(["doc-1", "--find", "old"]))
        XCTAssertThrowsError(try Docs.Replace.parse(["doc-1", "--replace", "new"]))
    }
}
