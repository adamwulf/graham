import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for the `files.update`-backed Drive commands
/// (move, rename, star, untrash), download, and `drive create shortcut`.
final class DriveUpdateParsingTests: XCTestCase {
    // MARK: - Move

    func testMoveParsesFileAndDestination() throws {
        let command = try Drive.Move.parse(["file-1", "--to", "folder-9"])
        XCTAssertEqual(command.fileID, "file-1")
        XCTAssertEqual(command.to, "folder-9")
    }

    func testMoveRequiresBothFileAndDestination() {
        XCTAssertThrowsError(try Drive.Move.parse([]))
        XCTAssertThrowsError(try Drive.Move.parse(["file-1"]))
        XCTAssertThrowsError(try Drive.Move.parse(["--to", "folder-9"]))
    }

    // MARK: - Rename

    func testRenameParsesFileAndNewName() throws {
        let command = try Drive.Rename.parse(["file-1", "Quarterly Report"])
        XCTAssertEqual(command.fileID, "file-1")
        XCTAssertEqual(command.name, "Quarterly Report")
    }

    func testRenameRequiresBothFileAndName() {
        XCTAssertThrowsError(try Drive.Rename.parse([]))
        XCTAssertThrowsError(try Drive.Rename.parse(["file-1"]))
    }

    // MARK: - Star

    func testStarParsesFileAndDefaultsOnLeavingTheStar() throws {
        let command = try Drive.Star.parse(["file-1"])
        XCTAssertEqual(command.fileID, "file-1")
        XCTAssertFalse(command.off)
    }

    func testStarParsesTheOffFlag() throws {
        let command = try Drive.Star.parse(["file-1", "--off"])
        XCTAssertTrue(command.off)
    }

    func testStarRequiresAFile() {
        XCTAssertThrowsError(try Drive.Star.parse([]))
    }

    // MARK: - Untrash

    func testUntrashParsesTheFile() throws {
        XCTAssertEqual(try Drive.Untrash.parse(["file-1"]).fileID, "file-1")
    }

    func testUntrashRequiresAFile() {
        XCTAssertThrowsError(try Drive.Untrash.parse([]))
    }

    // MARK: - Download

    func testDownloadParsesFileAndOutput() throws {
        let command = try Drive.Download.parse(["file-1", "--output", "out.bin"])
        XCTAssertEqual(command.fileID, "file-1")
        XCTAssertEqual(command.output, "out.bin")
    }

    func testDownloadDefaultsOutputToNilForStdout() throws {
        XCTAssertNil(try Drive.Download.parse(["file-1"]).output)
    }

    func testDownloadRequiresAFile() {
        XCTAssertThrowsError(try Drive.Download.parse([]))
    }

    // MARK: - Create shortcut

    func testCreateShortcutParsesTargetNameAndParent() throws {
        let command = try Drive.Create.Shortcut.parse([
            "target-1", "--name", "Link", "--parent", "folder-3",
        ])
        XCTAssertEqual(command.targetID, "target-1")
        XCTAssertEqual(command.name, "Link")
        XCTAssertEqual(command.parent, "folder-3")
        XCTAssertEqual(command.format, .id)
    }

    func testCreateShortcutRequiresTargetAndName() {
        XCTAssertThrowsError(try Drive.Create.Shortcut.parse([]))
        // A target with no --name.
        XCTAssertThrowsError(try Drive.Create.Shortcut.parse(["target-1"]))
    }

    // MARK: - Registration

    func testDriveRegistersTheNewSubcommands() {
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        for expected in ["Move", "Rename", "Star", "Untrash", "Download"] {
            XCTAssertTrue(names.contains(expected), "drive should list \(expected): \(names)")
        }
    }
    // `drive create shortcut` registration is asserted in DriveCreateParsingTests
    // alongside the other create subcommands.
}
