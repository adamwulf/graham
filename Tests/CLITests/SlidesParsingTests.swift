import XCTest
import GrahamKit
@testable import graham

/// Argument-parsing tests for the new `graham slides` subcommands. These check
/// only how arguments bind; they never build an API client or hit the network.
final class SlidesParsingTests: XCTestCase {
    func testSlidesListsItsSubcommands() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        // Cat is preserved alongside the two new commands.
        XCTAssertTrue(names.contains("cat"))
        XCTAssertTrue(names.contains("list"))
        XCTAssertTrue(names.contains("images"))
    }

    // MARK: - list

    func testSlidesListDefaults() throws {
        let command = try Slides.List.parse(["deck-id"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.format, .table)
    }

    func testSlidesListParsesFormat() throws {
        let command = try Slides.List.parse(["deck-id", "--format", "jsonl"])
        XCTAssertEqual(command.format, .jsonl)
    }

    func testSlidesListRequiresAPresentationID() {
        XCTAssertThrowsError(try Slides.List.parse([]))
    }

    func testSlidesListRejectsAnUnknownFormat() {
        XCTAssertThrowsError(try Slides.List.parse(["deck-id", "--format", "xml"]))
    }

    // MARK: - images

    func testSlidesImagesDefaultsToListing() throws {
        let command = try Slides.Images.parse(["deck-id"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertNil(command.download)
        XCTAssertEqual(command.format, .table)
    }

    func testSlidesImagesParsesDownloadDirectoryLongAndShort() throws {
        let long = try Slides.Images.parse(["deck-id", "--download", "/tmp/out"])
        XCTAssertEqual(long.download, "/tmp/out")

        let short = try Slides.Images.parse(["deck-id", "-d", "/tmp/out"])
        XCTAssertEqual(short.download, "/tmp/out")
    }

    func testSlidesImagesParsesFormat() throws {
        let command = try Slides.Images.parse(["deck-id", "--format", "id"])
        XCTAssertEqual(command.format, .id)
    }

    func testSlidesImagesRequiresAPresentationID() {
        XCTAssertThrowsError(try Slides.Images.parse([]))
    }
}
