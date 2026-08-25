import XCTest
import GrahamKit
@testable import graham

final class DocsWriteParsingTests: XCTestCase {
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
