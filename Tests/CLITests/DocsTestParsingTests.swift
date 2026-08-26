import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for `graham docs test`, mirroring the `slides test`
/// parse tests. They check only how arguments bind; they never build an API
/// client or hit the network.
final class DocsTestParsingTests: XCTestCase {
    func testDocsRegistersTheTestSubcommand() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Test"), "docs should list a Test subcommand: \(names)")
    }

    func testDocsTestDefaults() throws {
        let command = try Docs.Test.parse([])
        XCTAssertFalse(command.keep)
        XCTAssertEqual(command.folder, "graham test")
        XCTAssertEqual(command.imageURL, DocsLiveTest.defaultImageURL)
    }

    func testDocsTestParsesEveryOption() throws {
        let command = try Docs.Test.parse([
            "--keep",
            "--folder", "smoke folder",
            "--image-url", "https://example.com/image.png",
        ])
        XCTAssertTrue(command.keep)
        XCTAssertEqual(command.folder, "smoke folder")
        XCTAssertEqual(command.imageURL, "https://example.com/image.png")
    }
}
