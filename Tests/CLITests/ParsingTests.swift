import XCTest
import SergeyKit
@testable import sergey

final class ParsingTests: XCTestCase {
    func testRootListsAllSubcommands() {
        let names = Sergey.configuration.subcommands.map { $0.configuration.commandName ?? "\($0)" }
        XCTAssertEqual(Sergey.configuration.subcommands.count, 5)
        XCTAssertEqual(Sergey.configuration.commandName, "sergey")
        XCTAssertFalse(names.isEmpty)
    }

    func testDriveListDefaults() throws {
        let command = try Drive.List.parse([])
        XCTAssertNil(command.query)
        XCTAssertNil(command.orderBy)
        XCTAssertEqual(command.limit, 100)
        XCTAssertEqual(command.format, .table)
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
        XCTAssertEqual(command.range, "Tab!A1:C10")
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
