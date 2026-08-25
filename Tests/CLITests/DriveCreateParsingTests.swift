import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham drive create`.
final class DriveCreateParsingTests: XCTestCase {
    func testDriveCreateParsesNameAndType() throws {
        let command = try Drive.Create.parse(["Quarterly Report", "--type", "docs"])
        XCTAssertEqual(command.name, "Quarterly Report")
        XCTAssertEqual(command.type, .docs)
        // The default output is just the id, so scripts can capture it directly.
        XCTAssertEqual(command.format, .id)
    }

    func testDriveCreateParsesEachType() throws {
        XCTAssertEqual(try Drive.Create.parse(["n", "--type", "docs"]).type, .docs)
        XCTAssertEqual(try Drive.Create.parse(["n", "--type", "sheets"]).type, .sheets)
        XCTAssertEqual(try Drive.Create.parse(["n", "--type", "slides"]).type, .slides)
        XCTAssertEqual(try Drive.Create.parse(["n", "--type", "folder"]).type, .folder)
    }

    func testDriveCreateAcceptsAnExplicitFormat() throws {
        let command = try Drive.Create.parse(["n", "--type", "sheets", "--format", "json"])
        XCTAssertEqual(command.format, .json)
    }

    func testDriveCreateRequiresANameAndAType() {
        // No name.
        XCTAssertThrowsError(try Drive.Create.parse(["--type", "docs"]))
        // No type.
        XCTAssertThrowsError(try Drive.Create.parse(["My File"]))
    }

    func testDriveCreateRejectsNonCreatableTypes() {
        // "all" and plural "folders" are listing filters, not creatable types.
        XCTAssertThrowsError(try Drive.Create.parse(["n", "--type", "all"]))
        XCTAssertThrowsError(try Drive.Create.parse(["n", "--type", "folders"]))
        XCTAssertThrowsError(try Drive.Create.parse(["n", "--type", "images"]))
    }

    func testDriveRegistersTheCreateSubcommand() {
        // The subcommands set no explicit commandName, so match by type name;
        // ArgumentParser lowercases it to "create" for the actual CLI.
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Create"), "drive should list a Create subcommand: \(names)")
    }
}
