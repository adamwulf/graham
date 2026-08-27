import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham drive test`. They check only how
/// arguments bind; they never build an API client or hit the network.
final class DriveTestParsingTests: XCTestCase {
    func testDriveRegistersTheTestSubcommand() {
        let names = Drive.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Test"), "drive should list a Test subcommand: \(names)")
    }

    func testDriveTestDefaults() throws {
        let command = try Drive.Test.parse([])
        XCTAssertFalse(command.keep)
        XCTAssertEqual(command.folder, "graham test")
    }

    func testDriveTestParsesEveryOption() throws {
        let command = try Drive.Test.parse([
            "--keep",
            "--folder", "smoke folder",
        ])
        XCTAssertTrue(command.keep)
        XCTAssertEqual(command.folder, "smoke folder")
    }
}
