import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham drive convert`.
final class DriveConvertParsingTests: XCTestCase {
    func testConvertParsesTheFileIDAndTargetType() throws {
        let command = try Drive.Convert.parse(["deck.pptx", "--to", "slides"])
        XCTAssertEqual(command.fileID, "deck.pptx")
        XCTAssertEqual(command.to, .slides)
        XCTAssertNil(command.name)
        XCTAssertNil(command.parent)
    }

    func testConvertParsesTheOptionalNameAndParent() throws {
        let command = try Drive.Convert.parse(
            ["doc.docx", "--to", "doc", "--name", "My Doc", "--parent", "folder-7"])
        XCTAssertEqual(command.to, .doc)
        XCTAssertEqual(command.name, "My Doc")
        XCTAssertEqual(command.parent, "folder-7")
    }

    func testConvertRequiresATargetType() {
        // Without --to there is no valid target, so parsing fails.
        XCTAssertThrowsError(try Drive.Convert.parse(["deck.pptx"]))
    }

    func testConvertRejectsANonEditableTargetType() {
        // folder and the plural listing spellings are not convert targets.
        XCTAssertThrowsError(try Drive.Convert.parse(["f1", "--to", "folder"]))
        XCTAssertThrowsError(try Drive.Convert.parse(["f1", "--to", "docs"]))
    }

    func testConvertRequiresAFileID() {
        XCTAssertThrowsError(try Drive.Convert.parse(["--to", "slides"]))
    }

    func testDriveRegistersTheConvertSubcommand() {
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Convert"), "drive should list a Convert subcommand: \(names)")
    }
}
