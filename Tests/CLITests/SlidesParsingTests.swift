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
        XCTAssertTrue(names.contains("create"))
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

    // MARK: - create textbox

    func testSlidesCreateListsTextbox() {
        let names = Slides.Create.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("textbox"))
    }

    func testSlidesCreateTextboxParsesDefaults() throws {
        let command = try Slides.Create.Textbox.parse(["deck-id", "slide-9"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.text, "")
        XCTAssertEqual(command.x, 50)
        XCTAssertEqual(command.y, 50)
        XCTAssertEqual(command.width, 300)
        XCTAssertEqual(command.height, 50)
    }

    func testSlidesCreateTextboxParsesEveryFlag() throws {
        let command = try Slides.Create.Textbox.parse([
            "deck-id",
            "slide-9",
            "--text", "Hello world",
            "--x", "-25.5",
            "--y", "10.25",
            "--width", "400.5",
            "--height", "80.75",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.text, "Hello world")
        XCTAssertEqual(command.x, -25.5)
        XCTAssertEqual(command.y, 10.25)
        XCTAssertEqual(command.width, 400.5)
        XCTAssertEqual(command.height, 80.75)
    }

    func testSlidesCreateTextboxRejectsNonPositiveDimensions() {
        XCTAssertThrowsError(try Slides.Create.Textbox.parse([
            "deck-id", "slide-9", "--width", "0",
        ]))
        XCTAssertThrowsError(try Slides.Create.Textbox.parse([
            "deck-id", "slide-9", "--height", "-1",
        ]))
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

    // MARK: - create subcommand registry

    func testSlidesCreateListsEveryElementSubcommand() {
        let names = Slides.Create.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("textbox"))
        XCTAssertTrue(names.contains("image"))
        XCTAssertTrue(names.contains("video"))
        XCTAssertTrue(names.contains("line"))
        XCTAssertTrue(names.contains("table"))
        XCTAssertTrue(names.contains("chart"))
    }

    func testSlidesListsGroupAndUngroup() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("group"))
        XCTAssertTrue(names.contains("ungroup"))
    }

    // MARK: - create image

    func testSlidesCreateImageParsesDefaults() throws {
        let command = try Slides.Create.Image.parse([
            "deck-id", "slide-9", "--url", "https://example.com/pic.png",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.url, "https://example.com/pic.png")
        // Geometry is optional; with no flags every dimension is nil so Google
        // chooses the default placement.
        XCTAssertNil(command.geometry.x)
        XCTAssertNil(command.geometry.y)
        XCTAssertNil(command.geometry.width)
        XCTAssertNil(command.geometry.height)
    }

    func testSlidesCreateImageParsesEveryGeometryFlag() throws {
        let command = try Slides.Create.Image.parse([
            "deck-id", "slide-9",
            "--url", "u",
            "--x", "-25.5",
            "--y", "10.25",
            "--width", "400.5",
            "--height", "80.75",
        ])
        XCTAssertEqual(command.geometry.x, -25.5)
        XCTAssertEqual(command.geometry.y, 10.25)
        XCTAssertEqual(command.geometry.width, 400.5)
        XCTAssertEqual(command.geometry.height, 80.75)
    }

    func testSlidesCreateImageRequiresAUrl() {
        XCTAssertThrowsError(try Slides.Create.Image.parse(["deck-id", "slide-9"]))
    }

    func testSlidesCreateImageRejectsASingleGeometryDimension() {
        // width and height must be given together.
        XCTAssertThrowsError(try Slides.Create.Image.parse([
            "deck-id", "slide-9", "--url", "u", "--width", "100",
        ]))
        XCTAssertThrowsError(try Slides.Create.Image.parse([
            "deck-id", "slide-9", "--url", "u", "--height", "50",
        ]))
    }

    func testSlidesCreateImageRejectsNonPositiveDimensions() {
        XCTAssertThrowsError(try Slides.Create.Image.parse([
            "deck-id", "slide-9", "--url", "u", "--width", "0", "--height", "50",
        ]))
        XCTAssertThrowsError(try Slides.Create.Image.parse([
            "deck-id", "slide-9", "--url", "u", "--width", "50", "--height", "-1",
        ]))
    }

    // MARK: - create video

    func testSlidesCreateVideoParsesDefaults() throws {
        let command = try Slides.Create.Video.parse(["deck-id", "slide-9", "--id", "abc123"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.id, "abc123")
        XCTAssertEqual(command.source, .youtube)
    }

    func testSlidesCreateVideoParsesEachSourceLowerCase() throws {
        XCTAssertEqual(
            try Slides.Create.Video.parse(
                ["deck-id", "slide-9", "--id", "abc", "--source", "youtube"]).source,
            .youtube
        )
        XCTAssertEqual(
            try Slides.Create.Video.parse(
                ["deck-id", "slide-9", "--id", "file-1", "--source", "drive"]).source,
            .drive
        )
    }

    func testSlidesCreateVideoRequiresAnId() {
        XCTAssertThrowsError(try Slides.Create.Video.parse(["deck-id", "slide-9"]))
    }

    func testSlidesCreateVideoRejectsAnUnknownSource() {
        XCTAssertThrowsError(try Slides.Create.Video.parse([
            "deck-id", "slide-9", "--id", "abc", "--source", "vimeo",
        ]))
    }

    // MARK: - create line

    func testSlidesCreateLineParsesDefaults() throws {
        let command = try Slides.Create.Line.parse(["deck-id", "slide-9"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.category, .straight)
    }

    func testSlidesCreateLineParsesEachCategoryLowerCase() throws {
        XCTAssertEqual(
            try Slides.Create.Line.parse(
                ["deck-id", "slide-9", "--category", "straight"]).category,
            .straight
        )
        XCTAssertEqual(
            try Slides.Create.Line.parse(
                ["deck-id", "slide-9", "--category", "bent"]).category,
            .bent
        )
        XCTAssertEqual(
            try Slides.Create.Line.parse(
                ["deck-id", "slide-9", "--category", "curved"]).category,
            .curved
        )
    }

    func testSlidesCreateLineRejectsAnUnknownCategory() {
        XCTAssertThrowsError(try Slides.Create.Line.parse([
            "deck-id", "slide-9", "--category", "diagonal",
        ]))
    }

    // MARK: - create table

    func testSlidesCreateTableParsesRowsAndColumns() throws {
        let command = try Slides.Create.Table.parse([
            "deck-id", "slide-9", "--rows", "3", "--columns", "4",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.rows, 3)
        XCTAssertEqual(command.columns, 4)
    }

    func testSlidesCreateTableRequiresRowsAndColumns() {
        XCTAssertThrowsError(try Slides.Create.Table.parse(["deck-id", "slide-9"]))
        XCTAssertThrowsError(try Slides.Create.Table.parse(["deck-id", "slide-9", "--rows", "3"]))
        XCTAssertThrowsError(try Slides.Create.Table.parse(["deck-id", "slide-9", "--columns", "4"]))
    }

    func testSlidesCreateTableRejectsNonPositiveRowsOrColumns() {
        XCTAssertThrowsError(try Slides.Create.Table.parse([
            "deck-id", "slide-9", "--rows", "0", "--columns", "4",
        ]))
        XCTAssertThrowsError(try Slides.Create.Table.parse([
            "deck-id", "slide-9", "--rows", "3", "--columns", "0",
        ]))
    }

    // MARK: - create chart

    func testSlidesCreateChartParsesDefaults() throws {
        let command = try Slides.Create.Chart.parse([
            "deck-id", "slide-9", "--spreadsheet", "sheet-1", "--chart-id", "42",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-9")
        XCTAssertEqual(command.spreadsheet, "sheet-1")
        XCTAssertEqual(command.chartId, 42)
        XCTAssertFalse(command.linked)
    }

    func testSlidesCreateChartParsesTheLinkedFlag() throws {
        let command = try Slides.Create.Chart.parse([
            "deck-id", "slide-9", "--spreadsheet", "sheet-1", "--chart-id", "7", "--linked",
        ])
        XCTAssertTrue(command.linked)
    }

    func testSlidesCreateChartRequiresSpreadsheetAndChartId() {
        XCTAssertThrowsError(try Slides.Create.Chart.parse(["deck-id", "slide-9"]))
        XCTAssertThrowsError(try Slides.Create.Chart.parse([
            "deck-id", "slide-9", "--spreadsheet", "sheet-1",
        ]))
        XCTAssertThrowsError(try Slides.Create.Chart.parse([
            "deck-id", "slide-9", "--chart-id", "42",
        ]))
    }

    // MARK: - group

    func testSlidesGroupParsesChildIds() throws {
        let command = try Slides.Group.parse(["deck-id", "a", "b", "c"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.childIDs, ["a", "b", "c"])
    }

    func testSlidesGroupRequiresAtLeastTwoChildren() {
        XCTAssertThrowsError(try Slides.Group.parse(["deck-id"]))
        XCTAssertThrowsError(try Slides.Group.parse(["deck-id", "only-one"]))
    }

    // MARK: - ungroup

    func testSlidesUngroupParsesGroupIds() throws {
        let command = try Slides.Ungroup.parse(["deck-id", "g1", "g2"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectIDs, ["g1", "g2"])
    }

    func testSlidesUngroupRequiresAtLeastOneGroupId() {
        XCTAssertThrowsError(try Slides.Ungroup.parse(["deck-id"]))
    }
}
