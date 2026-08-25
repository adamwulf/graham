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

    func testDeleteParsesTheFileID() throws {
        let command = try Drive.Delete.parse(["file-123"])
        XCTAssertEqual(command.fileID, "file-123")
        // Without --force, the flag defaults to false.
        XCTAssertFalse(command.force)
    }

    func testDeleteParsesTheForceFlag() throws {
        let command = try Drive.Delete.parse(["file-123", "--force"])
        XCTAssertTrue(command.force)
    }

    func testDeleteRequiresAFileID() {
        XCTAssertThrowsError(try Drive.Delete.parse([]))
        XCTAssertNoThrow(try Drive.Delete.parse(["file-123"]))
    }

    /// The force gate lives in `run()`: without `--force` it must fail with a
    /// `ValidationError` before any network call, so deletion cannot happen by
    /// accident. The guard runs before the client is built, so this stays
    /// offline.
    func testDeleteWithoutForceIsRejectedBeforeAnyNetwork() async throws {
        var command = try Drive.Delete.parse(["file-123"])
        do {
            try await command.run()
            XCTFail("Expected a ValidationError")
        } catch {
            XCTAssertTrue(error is ValidationError, "Expected a ValidationError, got \(error)")
        }
    }

    // MARK: - Registration

    func testDriveRegistersTheTrashAndDeleteSubcommands() {
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Trash"), "drive should list a Trash subcommand: \(names)")
        XCTAssertTrue(names.contains("Delete"), "drive should list a Delete subcommand: \(names)")
    }
}
