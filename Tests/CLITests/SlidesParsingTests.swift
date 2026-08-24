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
        // The read commands are preserved alongside the write commands.
        XCTAssertTrue(names.contains("cat"))
        XCTAssertTrue(names.contains("list"))
        XCTAssertTrue(names.contains("images"))
        XCTAssertTrue(names.contains("add"))
        XCTAssertTrue(names.contains("move"))
        XCTAssertTrue(names.contains("delete"))
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

    // MARK: - add

    func testSlidesAddDefaultsToAppendingABlankSlide() throws {
        let command = try Slides.Add.parse(["deck-id"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertNil(command.at)
        XCTAssertEqual(command.layout, "BLANK")
    }

    func testSlidesAddParsesPositionAndLayout() throws {
        let command = try Slides.Add.parse(
            ["deck-id", "--at", "3", "--layout", "TITLE_AND_BODY"])
        XCTAssertEqual(command.at, 3)
        XCTAssertEqual(command.layout, "TITLE_AND_BODY")
    }

    func testSlidesAddRequiresAPresentationID() {
        XCTAssertThrowsError(try Slides.Add.parse([]))
    }

    func testSlidesAddRejectsANonPositivePosition() {
        // Positions are one-based; 0 and negatives fail validation.
        XCTAssertThrowsError(try Slides.Add.parse(["deck-id", "--at", "0"]))
        XCTAssertThrowsError(try Slides.Add.parse(["deck-id", "--at", "-2"]))
    }

    func testSlidesAddRejectsANonNumericPosition() {
        XCTAssertThrowsError(try Slides.Add.parse(["deck-id", "--at", "first"]))
    }

    // MARK: - move

    func testSlidesMoveParsesItsArguments() throws {
        let command = try Slides.Move.parse(["deck-id", "slide-9", "--to", "2"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.to, 2)
    }

    func testSlidesMoveRequiresBothIdsAndAPosition() {
        XCTAssertThrowsError(try Slides.Move.parse([]))
        XCTAssertThrowsError(try Slides.Move.parse(["deck-id"]))
        XCTAssertThrowsError(try Slides.Move.parse(["deck-id", "slide-9"]))
    }

    func testSlidesMoveRejectsANonPositivePosition() {
        XCTAssertThrowsError(try Slides.Move.parse(["deck-id", "slide-9", "--to", "0"]))
        XCTAssertThrowsError(try Slides.Move.parse(["deck-id", "slide-9", "--to", "-1"]))
    }

    // MARK: - delete

    func testSlidesDeleteParsesItsArguments() throws {
        let command = try Slides.Delete.parse(["deck-id", "slide-9"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
    }

    func testSlidesDeleteRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Delete.parse([]))
        XCTAssertThrowsError(try Slides.Delete.parse(["deck-id"]))
    }
}
