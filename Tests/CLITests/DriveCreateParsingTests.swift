import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham drive create <type>`.
final class DriveCreateParsingTests: XCTestCase {
    func testDriveCreateDocParsesTheName() throws {
        let command = try Drive.Create.Doc.parse(["Quarterly Report"])
        XCTAssertEqual(command.options.name, "Quarterly Report")
        // Without a parent the file lands in My Drive.
        XCTAssertNil(command.options.parent)
        // The default output is just the id, so scripts can capture it directly.
        XCTAssertEqual(command.options.format, .id)
    }

    func testDriveCreateEachTypeParsesItsName() throws {
        XCTAssertEqual(try Drive.Create.Doc.parse(["n"]).options.name, "n")
        XCTAssertEqual(try Drive.Create.Sheet.parse(["n"]).options.name, "n")
        XCTAssertEqual(try Drive.Create.Slides.parse(["n"]).options.name, "n")
        XCTAssertEqual(try Drive.Create.Folder.parse(["n"]).options.name, "n")
    }

    func testDriveCreateParsesAParent() throws {
        let command = try Drive.Create.Doc.parse(["n", "--parent", "folder-1"])
        XCTAssertEqual(command.options.parent, "folder-1")
    }

    func testDriveCreateAcceptsAnExplicitFormat() throws {
        let command = try Drive.Create.Sheet.parse(["n", "--format", "json"])
        XCTAssertEqual(command.options.format, .json)
    }

    func testDriveCreateEachTypeRequiresAName() {
        XCTAssertThrowsError(try Drive.Create.Doc.parse([]))
        XCTAssertThrowsError(try Drive.Create.Sheet.parse([]))
        XCTAssertThrowsError(try Drive.Create.Slides.parse([]))
        XCTAssertThrowsError(try Drive.Create.Folder.parse([]))
    }

    func testDriveRegistersTheCreateSubcommand() {
        // The subcommands set no explicit commandName, so match by type name;
        // ArgumentParser lowercases it to "create" for the actual CLI.
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Create"), "drive should list a Create subcommand: \(names)")
    }

    func testDriveCreateRegistersEveryTypeSubcommand() {
        let names = Drive.Create.configuration.subcommands.compactMap {
            $0.configuration.commandName
        }
        XCTAssertEqual(names, ["doc", "sheet", "slides", "folder"])
    }
}
