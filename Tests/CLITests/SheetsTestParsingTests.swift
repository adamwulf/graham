import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham sheets test`, mirroring the `docs test`
/// and `slides test` parse tests. They check only how arguments bind; they never
/// build an API client or hit the network.
final class SheetsTestParsingTests: XCTestCase {
    func testSheetsRegistersTheTestSubcommand() {
        let names = Sheets.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Test"), "sheets should list a Test subcommand: \(names)")
    }

    func testSheetsTestDefaults() throws {
        let command = try Sheets.Test.parse([])
        XCTAssertFalse(command.keep)
        XCTAssertEqual(command.folder, "graham test")
    }

    func testSheetsTestParsesEveryOption() throws {
        let command = try Sheets.Test.parse([
            "--keep",
            "--folder", "smoke folder",
        ])
        XCTAssertTrue(command.keep)
        XCTAssertEqual(command.folder, "smoke folder")
    }
}
