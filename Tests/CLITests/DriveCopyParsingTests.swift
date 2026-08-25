import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham drive copy`.
final class DriveCopyParsingTests: XCTestCase {
    func testCopyParsesTheFileID() throws {
        let command = try Drive.Copy.parse(["file-123"])
        XCTAssertEqual(command.fileID, "file-123")
        XCTAssertNil(command.name)
        // The default output is just the id, so scripts can capture it directly.
        XCTAssertEqual(command.format, .id)
    }

    func testCopyParsesAnOptionalName() throws {
        let command = try Drive.Copy.parse(["file-123", "--name", "My Copy"])
        XCTAssertEqual(command.fileID, "file-123")
        XCTAssertEqual(command.name, "My Copy")
    }

    func testCopyAcceptsAnExplicitFormat() throws {
        let command = try Drive.Copy.parse(["file-123", "--format", "json"])
        XCTAssertEqual(command.format, .json)
    }

    func testCopyRequiresAFileID() {
        XCTAssertThrowsError(try Drive.Copy.parse([]))
        XCTAssertNoThrow(try Drive.Copy.parse(["file-123"]))
    }

    func testDriveRegistersTheCopySubcommand() {
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Copy"), "drive should list a Copy subcommand: \(names)")
    }
}
