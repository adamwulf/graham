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
        // --layout is now optional; nil means unspecified, and the client
        // applies the BLANK default when neither --layout nor --layout-id given.
        let command = try Slides.Add.parse(["deck-id"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertNil(command.at)
        XCTAssertNil(command.layout)
        XCTAssertNil(command.layoutId)
    }

    func testSlidesAddParsesPositionAndLayout() throws {
        let command = try Slides.Add.parse(
            ["deck-id", "--at", "3", "--layout", "TITLE_AND_BODY"])
        XCTAssertEqual(command.at, 3)
        XCTAssertEqual(command.layout, "TITLE_AND_BODY")
        XCTAssertNil(command.layoutId)
    }

    func testSlidesAddParsesLayoutId() throws {
        let command = try Slides.Add.parse(["deck-id", "--layout-id", "layout-7"])
        XCTAssertEqual(command.layoutId, "layout-7")
        XCTAssertNil(command.layout)
    }

    func testSlidesAddRejectsLayoutWithLayoutId() {
        // The two layout selectors are mutually exclusive.
        XCTAssertThrowsError(try Slides.Add.parse([
            "deck-id", "--layout", "BLANK", "--layout-id", "layout-7",
        ]))
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

    // MARK: - layouts

    func testSlidesListsLayouts() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("layouts"))
    }

    func testSlidesLayoutsDefaults() throws {
        let command = try Slides.Layouts.parse(["deck-id"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.format, .table)
    }

    func testSlidesLayoutsParsesFormat() throws {
        let command = try Slides.Layouts.parse(["deck-id", "--format", "id"])
        XCTAssertEqual(command.format, .id)
    }

    func testSlidesLayoutsRequiresAPresentationID() {
        XCTAssertThrowsError(try Slides.Layouts.parse([]))
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

    // MARK: - alt-text

    func testSlidesListsAltText() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("alt-text"))
    }

    func testSlidesAltTextParsesTitleAndDescription() throws {
        let command = try Slides.AltText.parse([
            "deck-id", "el-1", "--title", "A cat", "--description", "On a mat",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "el-1")
        XCTAssertEqual(command.title, "A cat")
        XCTAssertEqual(command.description, "On a mat")
        XCTAssertFalse(command.clearTitle)
        XCTAssertFalse(command.clearDescription)
    }

    func testSlidesAltTextParsesClearFlags() throws {
        let command = try Slides.AltText.parse([
            "deck-id", "el-1", "--clear-title", "--clear-description",
        ])
        XCTAssertTrue(command.clearTitle)
        XCTAssertTrue(command.clearDescription)
        XCTAssertNil(command.title)
        XCTAssertNil(command.description)
    }

    func testSlidesAltTextRejectsTitleWithClearTitle() {
        XCTAssertThrowsError(try Slides.AltText.parse([
            "deck-id", "el-1", "--title", "A cat", "--clear-title",
        ]))
    }

    func testSlidesAltTextRejectsDescriptionWithClearDescription() {
        XCTAssertThrowsError(try Slides.AltText.parse([
            "deck-id", "el-1", "--description", "d", "--clear-description",
        ]))
    }

    func testSlidesAltTextRequiresAtLeastOneField() {
        // With neither a value nor a clear flag there is nothing to do.
        XCTAssertThrowsError(try Slides.AltText.parse(["deck-id", "el-1"]))
    }

    func testSlidesAltTextRequiresBothIds() {
        XCTAssertThrowsError(try Slides.AltText.parse([]))
        XCTAssertThrowsError(try Slides.AltText.parse(["deck-id"]))
    }

    // MARK: - notes

    func testSlidesListsNotes() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("notes"))
    }

    func testSlidesNotesListsEverySubcommand() {
        let names = Slides.Notes.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["show", "set", "clear"])
    }

    func testSlidesNotesShowParsesDefaults() throws {
        let command = try Slides.Notes.Show.parse(["deck-id"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.format, .table)
    }

    func testSlidesNotesShowParsesFormat() throws {
        let command = try Slides.Notes.Show.parse(["deck-id", "--format", "json"])
        XCTAssertEqual(command.format, .json)
    }

    func testSlidesNotesShowRequiresAPresentationID() {
        XCTAssertThrowsError(try Slides.Notes.Show.parse([]))
    }

    func testSlidesNotesSetParsesArguments() throws {
        let command = try Slides.Notes.Set.parse([
            "deck-id", "slide-1", "--text", "Remember to smile",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-1")
        XCTAssertEqual(command.text, "Remember to smile")
    }

    func testSlidesNotesSetRequiresText() {
        XCTAssertThrowsError(try Slides.Notes.Set.parse(["deck-id", "slide-1"]))
    }

    func testSlidesNotesSetRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Notes.Set.parse([]))
        XCTAssertThrowsError(try Slides.Notes.Set.parse(["deck-id", "--text", "x"]))
    }

    func testSlidesNotesClearParsesArguments() throws {
        let command = try Slides.Notes.Clear.parse(["deck-id", "slide-1"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.slideID, "slide-1")
    }

    func testSlidesNotesClearRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Notes.Clear.parse([]))
        XCTAssertThrowsError(try Slides.Notes.Clear.parse(["deck-id"]))
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

    // MARK: - element registry

    func testSlidesListsElementAfterCreate() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("element"))
        // Element is registered immediately after create.
        guard let create = names.firstIndex(of: "create"),
            let element = names.firstIndex(of: "element")
        else {
            return XCTFail("expected both create and element subcommands")
        }
        XCTAssertEqual(element, create + 1)
    }

    func testSlidesElementListsEverySubcommand() {
        let names = Slides.Element.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["move", "scale", "rotate", "transform", "reorder", "delete"])
    }

    // MARK: - element delete

    func testSlidesElementDeleteParsesItsArguments() throws {
        let command = try Slides.Element.Delete.parse(["deck-id", "obj-1"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
    }

    func testSlidesElementDeleteRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Element.Delete.parse([]))
        XCTAssertThrowsError(try Slides.Element.Delete.parse(["deck-id"]))
    }

    // MARK: - element move

    func testSlidesElementMoveParsesToStyle() throws {
        let command = try Slides.Element.Move.parse([
            "deck-id", "obj-1", "--to-x", "100", "--to-y", "200",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.toX, 100)
        XCTAssertEqual(command.toY, 200)
        XCTAssertNil(command.byX)
        XCTAssertNil(command.byY)
    }

    func testSlidesElementMoveParsesNegativeToStyle() throws {
        // Unconditional parsing lets a leading - be a value, not a flag.
        let command = try Slides.Element.Move.parse([
            "deck-id", "obj-1", "--to-x", "-25.5", "--to-y", "-10.25",
        ])
        XCTAssertEqual(command.toX, -25.5)
        XCTAssertEqual(command.toY, -10.25)
    }

    func testSlidesElementMoveParsesByStyleWithMissingAxis() throws {
        // A missing axis stays nil so the command can treat it as 0.
        let onlyX = try Slides.Element.Move.parse(["deck-id", "obj-1", "--by-x", "-5"])
        XCTAssertEqual(onlyX.byX, -5)
        XCTAssertNil(onlyX.byY)

        let both = try Slides.Element.Move.parse([
            "deck-id", "obj-1", "--by-x", "5", "--by-y", "-7.5",
        ])
        XCTAssertEqual(both.byX, 5)
        XCTAssertEqual(both.byY, -7.5)
    }

    func testSlidesElementMoveRejectsBothStyles() {
        XCTAssertThrowsError(try Slides.Element.Move.parse([
            "deck-id", "obj-1", "--to-x", "1", "--to-y", "2", "--by-x", "3",
        ]))
    }

    func testSlidesElementMoveRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Element.Move.parse(["deck-id", "obj-1"]))
    }

    func testSlidesElementMoveRejectsASingleToAxis() {
        // --to-x and --to-y must appear together.
        XCTAssertThrowsError(try Slides.Element.Move.parse([
            "deck-id", "obj-1", "--to-x", "100",
        ]))
        XCTAssertThrowsError(try Slides.Element.Move.parse([
            "deck-id", "obj-1", "--to-y", "200",
        ]))
    }

    func testSlidesElementMoveRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Element.Move.parse([]))
        XCTAssertThrowsError(try Slides.Element.Move.parse(["deck-id"]))
    }

    // MARK: - element scale

    func testSlidesElementScaleParsesUniformFactor() throws {
        let command = try Slides.Element.Scale.parse(["deck-id", "obj-1", "--by", "2"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.by, 2)
        XCTAssertNil(command.byX)
        XCTAssertNil(command.byY)
    }

    func testSlidesElementScaleParsesAxisFactors() throws {
        let command = try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by-x", "1.5", "--by-y", "0.5",
        ])
        XCTAssertEqual(command.byX, 1.5)
        XCTAssertEqual(command.byY, 0.5)
        XCTAssertNil(command.by)
    }

    func testSlidesElementScaleRejectsMixingStyles() {
        XCTAssertThrowsError(try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by", "2", "--by-x", "3",
        ]))
    }

    func testSlidesElementScaleRejectsASingleAxis() {
        XCTAssertThrowsError(try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by-x", "2",
        ]))
        XCTAssertThrowsError(try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by-y", "2",
        ]))
    }

    func testSlidesElementScaleRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Element.Scale.parse(["deck-id", "obj-1"]))
    }

    func testSlidesElementScaleRejectsNonPositiveFactors() {
        // Factors must be greater than zero; the negative still parses first.
        XCTAssertThrowsError(try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by", "0",
        ]))
        XCTAssertThrowsError(try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by", "-2",
        ]))
        XCTAssertThrowsError(try Slides.Element.Scale.parse([
            "deck-id", "obj-1", "--by-x", "-1", "--by-y", "2",
        ]))
    }

    // MARK: - element rotate

    func testSlidesElementRotateParsesBy() throws {
        let command = try Slides.Element.Rotate.parse(["deck-id", "obj-1", "--by", "90"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.by, 90)
        XCTAssertNil(command.to)
    }

    func testSlidesElementRotateParsesNegativeBy() throws {
        let command = try Slides.Element.Rotate.parse(["deck-id", "obj-1", "--by", "-45.5"])
        XCTAssertEqual(command.by, -45.5)
    }

    func testSlidesElementRotateParsesTo() throws {
        let command = try Slides.Element.Rotate.parse(["deck-id", "obj-1", "--to", "-30"])
        XCTAssertEqual(command.to, -30)
        XCTAssertNil(command.by)
    }

    func testSlidesElementRotateRejectsBothOrNeither() {
        XCTAssertThrowsError(try Slides.Element.Rotate.parse(["deck-id", "obj-1"]))
        XCTAssertThrowsError(try Slides.Element.Rotate.parse([
            "deck-id", "obj-1", "--by", "10", "--to", "20",
        ]))
    }

    // MARK: - element transform

    func testSlidesElementTransformDefaults() throws {
        // Identity/zero, in points, absolute (not relative).
        let command = try Slides.Element.Transform.parse(["deck-id", "obj-1"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.scaleX, 1)
        XCTAssertEqual(command.scaleY, 1)
        XCTAssertEqual(command.shearX, 0)
        XCTAssertEqual(command.shearY, 0)
        XCTAssertEqual(command.translateX, 0)
        XCTAssertEqual(command.translateY, 0)
        XCTAssertEqual(command.unit, .pt)
        XCTAssertFalse(command.relative)
    }

    func testSlidesElementTransformParsesEveryFlag() throws {
        let command = try Slides.Element.Transform.parse([
            "deck-id", "obj-1",
            "--scale-x", "2",
            "--scale-y", "-3",
            "--shear-x", "0.5",
            "--shear-y", "-0.25",
            "--translate-x", "-100",
            "--translate-y", "200",
            "--unit", "emu",
            "--relative",
        ])
        XCTAssertEqual(command.scaleX, 2)
        XCTAssertEqual(command.scaleY, -3)
        XCTAssertEqual(command.shearX, 0.5)
        XCTAssertEqual(command.shearY, -0.25)
        XCTAssertEqual(command.translateX, -100)
        XCTAssertEqual(command.translateY, 200)
        XCTAssertEqual(command.unit, .emu)
        XCTAssertTrue(command.relative)
    }

    func testSlidesElementTransformParsesUnitCaseInsensitively() throws {
        XCTAssertEqual(
            try Slides.Element.Transform.parse(["deck-id", "obj-1", "--unit", "pt"]).unit,
            .pt
        )
        XCTAssertEqual(
            try Slides.Element.Transform.parse(["deck-id", "obj-1", "--unit", "EMU"]).unit,
            .emu
        )
    }

    func testSlidesElementTransformRejectsAnUnknownUnit() {
        XCTAssertThrowsError(try Slides.Element.Transform.parse([
            "deck-id", "obj-1", "--unit", "inches",
        ]))
    }

    // MARK: - element reorder

    func testSlidesElementReorderParsesOneId() throws {
        let command = try Slides.Element.Reorder.parse([
            "deck-id", "obj-1", "--to", "front",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectIDs, ["obj-1"])
        XCTAssertEqual(command.to, .front)
    }

    func testSlidesElementReorderParsesManyIds() throws {
        let command = try Slides.Element.Reorder.parse([
            "deck-id", "a", "b", "c", "--to", "back",
        ])
        XCTAssertEqual(command.objectIDs, ["a", "b", "c"])
        XCTAssertEqual(command.to, .back)
    }

    func testSlidesElementReorderMapsEachPositionToItsOperation() throws {
        let cases: [(String, ReorderPosition, ZOrderOperation)] = [
            ("front", .front, .bringToFront),
            ("forward", .forward, .bringForward),
            ("backward", .backward, .sendBackward),
            ("back", .back, .sendToBack),
        ]
        for (name, position, operation) in cases {
            let command = try Slides.Element.Reorder.parse(["deck-id", "obj", "--to", name])
            XCTAssertEqual(command.to, position)
            XCTAssertEqual(command.to.operation, operation)
        }
    }

    func testSlidesElementReorderRequiresAnId() {
        // --to is present but no object ids follow it.
        XCTAssertThrowsError(try Slides.Element.Reorder.parse(["deck-id", "--to", "front"]))
    }

    func testSlidesElementReorderRequiresAPosition() {
        XCTAssertThrowsError(try Slides.Element.Reorder.parse(["deck-id", "obj-1"]))
    }

    func testSlidesElementReorderRejectsABadPosition() {
        XCTAssertThrowsError(try Slides.Element.Reorder.parse([
            "deck-id", "obj-1", "--to", "middle",
        ]))
    }

    // MARK: - style / chart registry

    func testSlidesListsStyleAndChart() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertTrue(names.contains("style"))
        XCTAssertTrue(names.contains("chart"))
    }

    func testSlidesStyleListsEverySubcommand() {
        let names = Slides.Style.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["shape", "image", "line", "video"])
    }

    func testSlidesChartListsRefresh() {
        let names = Slides.Chart.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["refresh"])
    }

    // MARK: - style shape

    func testSlidesStyleShapeParsesFillOutlineShadowAndAlign() throws {
        let command = try Slides.Style.Shape.parse([
            "deck-id", "obj-1",
            "--fill", "#FF0000",
            "--fill-alpha", "0.5",
            "--outline", "accent1",
            "--outline-alpha", "0.8",
            "--outline-weight", "2",
            "--outline-dash", "dash-dot",
            "--shadow-color", "#000000",
            "--shadow-alpha", "0.4",
            "--shadow-blur", "3",
            "--shadow-offset-x", "-5",
            "--shadow-offset-y", "10",
            "--align", "middle",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.fill, "#FF0000")
        XCTAssertEqual(command.fillAlpha, 0.5)
        XCTAssertFalse(command.noFill)
        XCTAssertEqual(command.outlineOptions.outline, "accent1")
        XCTAssertEqual(command.outlineOptions.outlineAlpha, 0.8)
        XCTAssertEqual(command.outlineOptions.outlineWeight, 2)
        XCTAssertEqual(command.outlineOptions.outlineDash, .dashDot)
        XCTAssertEqual(command.outlineOptions.outlineDash?.dashStyle, .dashDot)
        XCTAssertFalse(command.outlineOptions.noOutline)
        XCTAssertEqual(command.shadowColor, "#000000")
        XCTAssertEqual(command.shadowAlpha, 0.4)
        XCTAssertEqual(command.shadowBlur, 3)
        XCTAssertEqual(command.shadowOffsetX, -5)
        XCTAssertEqual(command.shadowOffsetY, 10)
        XCTAssertFalse(command.noShadow)
        XCTAssertEqual(command.align, .middle)
        XCTAssertEqual(command.align?.contentAlignment, .middle)
    }

    func testSlidesStyleShapeParsesTheNoFlags() throws {
        // The three removal flags belong to different groups, so they combine.
        let command = try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--no-fill", "--no-outline", "--no-shadow",
        ])
        XCTAssertTrue(command.noFill)
        XCTAssertTrue(command.outlineOptions.noOutline)
        XCTAssertTrue(command.noShadow)
    }

    func testSlidesStyleShapeParsesNegativeShadowOffsets() throws {
        // Unconditional parsing lets a leading - be a value; offsets may be negative.
        let command = try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--shadow-offset-x", "-5.5", "--shadow-offset-y", "-10.25",
        ])
        XCTAssertEqual(command.shadowOffsetX, -5.5)
        XCTAssertEqual(command.shadowOffsetY, -10.25)
    }

    func testSlidesStyleShapeRejectsNoStyleFlags() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse(["deck-id", "obj-1"]))
    }

    func testSlidesStyleShapeRejectsNoFillWithFillFlags() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--no-fill", "--fill", "#FF0000",
        ]))
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--no-fill", "--fill-alpha", "0.5",
        ]))
    }

    func testSlidesStyleShapeRejectsNoOutlineWithOutlineFlags() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--no-outline", "--outline", "accent1",
        ]))
    }

    func testSlidesStyleShapeRejectsNoShadowWithShadowFlags() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--no-shadow", "--shadow-color", "#000000",
        ]))
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--no-shadow", "--shadow-offset-x", "5",
        ]))
    }

    func testSlidesStyleShapeRejectsAlphaOutOfRange() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--fill-alpha", "1.5",
        ]))
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--fill-alpha", "-0.5",
        ]))
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--shadow-alpha", "2",
        ]))
    }

    func testSlidesStyleShapeRejectsNonPositiveWeightOrBlur() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--outline-weight", "0",
        ]))
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--shadow-blur", "-1",
        ]))
    }

    func testSlidesStyleShapeRejectsAnUnknownDash() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--outline-dash", "zigzag",
        ]))
    }

    func testSlidesStyleShapeRejectsAnUnknownAlign() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--align", "center",
        ]))
    }

    func testSlidesStyleShapeRejectsScreamingDashSpelling() {
        // The CLI surface is lower-kebab only; the wire spelling must not parse.
        XCTAssertThrowsError(try Slides.Style.Shape.parse([
            "deck-id", "obj-1", "--outline-dash", "DASH_DOT",
        ]))
    }

    func testSlidesStyleShapeRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Style.Shape.parse([]))
        XCTAssertThrowsError(try Slides.Style.Shape.parse(["deck-id"]))
    }

    // MARK: - style image

    func testSlidesStyleImageParsesEveryOutlineFlag() throws {
        let command = try Slides.Style.Image.parse([
            "deck-id", "obj-1",
            "--outline", "#00FF00",
            "--outline-alpha", "0.5",
            "--outline-weight", "1.5",
            "--outline-dash", "long-dash",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.outlineOptions.outline, "#00FF00")
        XCTAssertEqual(command.outlineOptions.outlineAlpha, 0.5)
        XCTAssertEqual(command.outlineOptions.outlineWeight, 1.5)
        XCTAssertEqual(command.outlineOptions.outlineDash, .longDash)
        XCTAssertFalse(command.outlineOptions.noOutline)
    }

    func testSlidesStyleImageParsesNoOutline() throws {
        let command = try Slides.Style.Image.parse(["deck-id", "obj-1", "--no-outline"])
        XCTAssertTrue(command.outlineOptions.noOutline)
    }

    func testSlidesStyleImageRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Style.Image.parse(["deck-id", "obj-1"]))
    }

    func testSlidesStyleImageRejectsNoOutlineWithOutlineFlags() {
        XCTAssertThrowsError(try Slides.Style.Image.parse([
            "deck-id", "obj-1", "--no-outline", "--outline", "#00FF00",
        ]))
    }

    func testSlidesStyleImageRejectsAlphaOutOfRange() {
        XCTAssertThrowsError(try Slides.Style.Image.parse([
            "deck-id", "obj-1", "--outline-alpha", "2",
        ]))
    }

    func testSlidesStyleImageRejectsNonPositiveWeight() {
        XCTAssertThrowsError(try Slides.Style.Image.parse([
            "deck-id", "obj-1", "--outline-weight", "0",
        ]))
    }

    // MARK: - style line

    func testSlidesStyleLineParsesEveryFlag() throws {
        let command = try Slides.Style.Line.parse([
            "deck-id", "obj-1",
            "--color", "#0000FF",
            "--alpha", "0.5",
            "--weight", "1.5",
            "--dash", "dot",
            "--start-arrow", "open-arrow",
            "--end-arrow", "fill-circle",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.color, "#0000FF")
        XCTAssertEqual(command.alpha, 0.5)
        XCTAssertEqual(command.weight, 1.5)
        XCTAssertEqual(command.dash, .dot)
        XCTAssertEqual(command.dash?.dashStyle, .dot)
        XCTAssertEqual(command.startArrow, .openArrow)
        XCTAssertEqual(command.startArrow?.arrowStyle, .openArrow)
        XCTAssertEqual(command.endArrow, .fillCircle)
        XCTAssertEqual(command.endArrow?.arrowStyle, .fillCircle)
    }

    func testSlidesStyleLineRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Style.Line.parse(["deck-id", "obj-1"]))
    }

    func testSlidesStyleLineRejectsAlphaOutOfRange() {
        XCTAssertThrowsError(try Slides.Style.Line.parse([
            "deck-id", "obj-1", "--alpha", "2",
        ]))
    }

    func testSlidesStyleLineRejectsNonPositiveWeight() {
        XCTAssertThrowsError(try Slides.Style.Line.parse([
            "deck-id", "obj-1", "--weight", "0",
        ]))
    }

    func testSlidesStyleLineRejectsAnUnknownDash() {
        XCTAssertThrowsError(try Slides.Style.Line.parse([
            "deck-id", "obj-1", "--dash", "zigzag",
        ]))
    }

    func testSlidesStyleLineRejectsAnUnknownArrow() {
        XCTAssertThrowsError(try Slides.Style.Line.parse([
            "deck-id", "obj-1", "--start-arrow", "triangle",
        ]))
    }

    // MARK: - style video

    func testSlidesStyleVideoParsesEveryFlag() throws {
        let command = try Slides.Style.Video.parse([
            "deck-id", "obj-1",
            "--autoplay",
            "--mute",
            "--start", "5",
            "--end", "30",
            "--outline", "accent2",
            "--outline-alpha", "0.5",
            "--outline-weight", "2",
            "--outline-dash", "solid",
        ])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.autoplay, true)
        XCTAssertEqual(command.mute, true)
        XCTAssertEqual(command.start, 5)
        XCTAssertEqual(command.end, 30)
        XCTAssertEqual(command.outlineOptions.outline, "accent2")
        XCTAssertEqual(command.outlineOptions.outlineAlpha, 0.5)
        XCTAssertEqual(command.outlineOptions.outlineWeight, 2)
        XCTAssertEqual(command.outlineOptions.outlineDash, .solid)
    }

    func testSlidesStyleVideoParsesAutoplayAndMuteInversion() throws {
        let on = try Slides.Style.Video.parse(["deck-id", "obj-1", "--autoplay", "--mute"])
        XCTAssertEqual(on.autoplay, true)
        XCTAssertEqual(on.mute, true)

        let off = try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--no-autoplay", "--no-mute",
        ])
        XCTAssertEqual(off.autoplay, false)
        XCTAssertEqual(off.mute, false)

        // Omitting them leaves each unchanged (nil), so another flag still parses.
        let unset = try Slides.Style.Video.parse(["deck-id", "obj-1", "--start", "1"])
        XCTAssertNil(unset.autoplay)
        XCTAssertNil(unset.mute)
    }

    func testSlidesStyleVideoRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Style.Video.parse(["deck-id", "obj-1"]))
    }

    func testSlidesStyleVideoRejectsNoOutlineWithOutlineFlags() {
        XCTAssertThrowsError(try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--no-outline", "--outline", "accent2",
        ]))
    }

    func testSlidesStyleVideoRejectsOutlineAlphaOutOfRange() {
        XCTAssertThrowsError(try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--outline-alpha", "2",
        ]))
    }

    func testSlidesStyleVideoRejectsNegativeStartOrEnd() {
        XCTAssertThrowsError(try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--start", "-1",
        ]))
        XCTAssertThrowsError(try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--end", "-1",
        ]))
    }

    func testSlidesStyleVideoRejectsEndNotAfterStart() {
        XCTAssertThrowsError(try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--start", "30", "--end", "10",
        ]))
        XCTAssertThrowsError(try Slides.Style.Video.parse([
            "deck-id", "obj-1", "--start", "10", "--end", "10",
        ]))
    }

    // MARK: - chart refresh

    func testSlidesChartRefreshParsesArguments() throws {
        let command = try Slides.Chart.Refresh.parse(["deck-id", "chart-1"])
        XCTAssertEqual(command.presentationID, "deck-id")
        XCTAssertEqual(command.objectID, "chart-1")
    }

    func testSlidesChartRefreshRequiresBothIds() {
        XCTAssertThrowsError(try Slides.Chart.Refresh.parse([]))
        XCTAssertThrowsError(try Slides.Chart.Refresh.parse(["deck-id"]))
    }

    // MARK: - CLI enum mapping

    func testDashStyleArgumentMapsEveryCase() throws {
        let cases: [(String, DashStyleArgument, DashStyle)] = [
            ("solid", .solid, .solid),
            ("dot", .dot, .dot),
            ("dash", .dash, .dash),
            ("dash-dot", .dashDot, .dashDot),
            ("long-dash", .longDash, .longDash),
            ("long-dash-dot", .longDashDot, .longDashDot),
        ]
        for (name, argument, dashStyle) in cases {
            let command = try Slides.Style.Line.parse(["deck-id", "obj-1", "--dash", name])
            XCTAssertEqual(command.dash, argument)
            XCTAssertEqual(command.dash?.dashStyle, dashStyle)
        }
    }

    func testArrowStyleArgumentMapsEveryCase() throws {
        let cases: [(String, ArrowStyleArgument, ArrowStyle)] = [
            ("none", .none, .none),
            ("stealth-arrow", .stealthArrow, .stealthArrow),
            ("fill-arrow", .fillArrow, .fillArrow),
            ("fill-circle", .fillCircle, .fillCircle),
            ("fill-square", .fillSquare, .fillSquare),
            ("fill-diamond", .fillDiamond, .fillDiamond),
            ("open-arrow", .openArrow, .openArrow),
            ("open-circle", .openCircle, .openCircle),
            ("open-square", .openSquare, .openSquare),
            ("open-diamond", .openDiamond, .openDiamond),
        ]
        for (name, argument, arrowStyle) in cases {
            let command = try Slides.Style.Line.parse([
                "deck-id", "obj-1", "--start-arrow", name,
            ])
            XCTAssertEqual(command.startArrow, argument)
            XCTAssertEqual(command.startArrow?.arrowStyle, arrowStyle)
        }
    }

    func testContentAlignmentArgumentMapsEveryCase() throws {
        let cases: [(String, ContentAlignmentArgument, ContentAlignment)] = [
            ("top", .top, .top),
            ("middle", .middle, .middle),
            ("bottom", .bottom, .bottom),
        ]
        for (name, argument, alignment) in cases {
            let command = try Slides.Style.Shape.parse(["deck-id", "obj-1", "--align", name])
            XCTAssertEqual(command.align, argument)
            XCTAssertEqual(command.align?.contentAlignment, alignment)
        }
    }
}
