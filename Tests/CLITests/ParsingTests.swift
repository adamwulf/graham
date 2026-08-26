import XCTest
import GrahamKit
@testable import graham

final class ParsingTests: XCTestCase {
    func testRootListsAllSubcommands() {
        let names = Graham.configuration.subcommands.map { $0.configuration.commandName ?? "\($0)" }
        XCTAssertEqual(Graham.configuration.subcommands.count, 5)
        XCTAssertEqual(Graham.configuration.commandName, "graham")
        XCTAssertFalse(names.isEmpty)
    }

    func testDriveListDefaults() throws {
        let command = try Drive.List.parse([])
        XCTAssertNil(command.id)
        XCTAssertEqual(command.type, .all)
        XCTAssertNil(command.query)
        XCTAssertNil(command.orderBy)
        XCTAssertEqual(command.limit, 100)
        XCTAssertEqual(command.format, .table)
    }

    func testDriveListParsesPositionalIDAndType() throws {
        let command = try Drive.List.parse(["folder-123", "--type", "sheets", "--limit", "5"])
        XCTAssertEqual(command.id, "folder-123")
        XCTAssertEqual(command.type, .sheets)
        XCTAssertEqual(command.limit, 5)
    }

    func testDriveListRejectsAnUnknownType() {
        XCTAssertThrowsError(try Drive.List.parse(["--type", "images"]))
    }

    func testDriveListOptions() throws {
        let command = try Drive.List.parse([
            "--query", "name contains 'report'",
            "--order-by", "modifiedTime desc",
            "--limit", "5",
            "--format", "json",
        ])
        XCTAssertEqual(command.query, "name contains 'report'")
        XCTAssertEqual(command.orderBy, "modifiedTime desc")
        XCTAssertEqual(command.limit, 5)
        XCTAssertEqual(command.format, .json)
    }

    func testDriveGetRequiresAFileID() {
        XCTAssertThrowsError(try Drive.Get.parse([]))
        XCTAssertNoThrow(try Drive.Get.parse(["file-id-123"]))
    }

    func testDriveExportDefaultsToPlainText() throws {
        let command = try Drive.Export.parse(["file-id-123"])
        XCTAssertEqual(command.mime, "text/plain")
        XCTAssertNil(command.output)
    }

    func testSheetsValuesParsesArguments() throws {
        let command = try Sheets.Values.parse(["sheet-id", "Tab!A1:C10", "--json"])
        XCTAssertEqual(command.spreadsheetID, "sheet-id")
        XCTAssertEqual(command.ranges, ["Tab!A1:C10"])
        XCTAssertTrue(command.json)
    }

    func testDocsCatParsesArguments() throws {
        let command = try Docs.Cat.parse(["doc-id"])
        XCTAssertEqual(command.documentID, "doc-id")
        XCTAssertFalse(command.json)
    }

    func testSlidesCatParsesArguments() throws {
        let command = try Slides.Cat.parse(["deck-id", "--json"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertTrue(command.json)
    }

    func testAuthLoginAcceptsRepeatedScopes() throws {
        let command = try Auth.Login.parse(["--scope", "drive", "--scope", "docs"])
        XCTAssertEqual(command.scope, ["drive", "docs"])
    }

    func testUnknownFormatFailsToParse() {
        XCTAssertThrowsError(try Drive.List.parse(["--format", "xml"]))
    }
}
