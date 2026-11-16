import ArgumentParser
import XCTest
import GrahamKit
@testable import graham

final class ParsingTests: XCTestCase {
    func testRootListsAllSubcommands() {
        let names = Graham.configuration.subcommands.map { $0._commandName }
        XCTAssertEqual(names, ["auth", "drive", "sheets", "docs", "slides", "ro"])
        XCTAssertEqual(Graham.configuration.commandName, "graham")
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
        XCTAssertEqual(command.options.fileID, "file-id-123")
        XCTAssertNil(command.options.type)
        XCTAssertNil(command.options.mime)
        XCTAssertEqual(command.options.resolvedMimeType, "text/plain")
        XCTAssertNil(command.output)
    }

    func testDriveExportTypeMapsToMimeType() throws {
        let pdf = try Drive.Export.parse(["file-id-123", "--type", "pdf"])
        XCTAssertEqual(pdf.options.resolvedMimeType, "application/pdf")

        let docx = try Drive.Export.parse(["file-id-123", "--type", "docx"])
        XCTAssertEqual(
            docx.options.resolvedMimeType,
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )

        let md = try Drive.Export.parse(["file-id-123", "--type", "md"])
        XCTAssertEqual(md.options.resolvedMimeType, "text/markdown")

        let csv = try Drive.Export.parse(["file-id-123", "--type", "csv"])
        XCTAssertEqual(csv.options.resolvedMimeType, "text/csv")
    }

    func testDriveExportRawMimeStillWorks() throws {
        let command = try Drive.Export.parse(["file-id-123", "--mime", "application/rtf"])
        XCTAssertEqual(command.options.resolvedMimeType, "application/rtf")
    }

    func testDriveExportRejectsBothTypeAndMime() {
        XCTAssertThrowsError(
            try Drive.Export.parse(["file-id-123", "--type", "pdf", "--mime", "text/csv"])
        )
    }

    func testDriveExportRejectsUnknownType() {
        XCTAssertThrowsError(try Drive.Export.parse(["file-id-123", "--type", "bogus"]))
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
