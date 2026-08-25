import XCTest
import ArgumentParser
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham drive trash` and `graham drive delete`,
/// including the delete `--force` gate.
final class DriveTrashDeleteParsingTests: XCTestCase {
    // MARK: - Trash

    func testTrashParsesTheFileID() throws {
        let command = try Drive.Trash.parse(["file-123"])
        XCTAssertEqual(command.fileID, "file-123")
    }

    func testTrashRequiresAFileID() {
        XCTAssertThrowsError(try Drive.Trash.parse([]))
        XCTAssertNoThrow(try Drive.Trash.parse(["file-123"]))
    }

    // MARK: - Delete

    func testDeleteParsesTheFileIDWithForce() throws {
        let command = try Drive.Delete.parse(["file-123", "--force"])
        XCTAssertEqual(command.fileID, "file-123")
        XCTAssertTrue(command.force)
    }

    func testDeleteRequiresAFileID() {
        // A missing file id fails even with --force present.
        XCTAssertThrowsError(try Drive.Delete.parse(["--force"]))
        XCTAssertNoThrow(try Drive.Delete.parse(["file-123", "--force"]))
    }

    /// The force gate lives in `validate()`, so plain parsing fails without
    /// `--force`: deletion cannot happen by accident. The rejection carries the
    /// permanence warning and points the user at `drive trash`. This stays
    /// offline — no client is built.
    func testDeleteWithoutForceIsRejectedAtParse() {
        XCTAssertThrowsError(try Drive.Delete.parse(["file-123"])) { error in
            let message = Drive.Delete.message(for: error)
            XCTAssertTrue(message.contains("permanent"), "Expected a permanence warning: \(message)")
            XCTAssertTrue(message.contains("drive trash"), "Expected a trash suggestion: \(message)")
        }
    }

    // MARK: - Registration

    func testDriveRegistersTheTrashAndDeleteSubcommands() {
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Trash"), "drive should list a Trash subcommand: \(names)")
        XCTAssertTrue(names.contains("Delete"), "drive should list a Delete subcommand: \(names)")
    }
}
