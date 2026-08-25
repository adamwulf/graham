import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the `slides text` command group. These check how
/// arguments bind and how the CLI enums map to the wire; they never build an API
/// client or touch the network.
///
/// The enum-mapping tests assert the API enum's `rawValue` (the SCREAMING wire
/// spelling verified in the spec) rather than a Swift case, so they pin the
/// normative wire contract without coupling to `GrahamKit`'s case names.
final class SlidesTextParsingTests: XCTestCase {
    // MARK: - registration

    func testSlidesRegistersTextAfterTable() {
        let names = Slides.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        let table = names.firstIndex(of: "table")
        let text = names.firstIndex(of: "text")
        XCTAssertNotNil(table)
        XCTAssertEqual(text, table.map { $0 + 1 })
    }

    func testSlidesTextListsEverySubcommand() {
        let names = Slides.Text.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, [
            "insert", "delete", "style", "paragraph", "bullets", "unbullet",
        ])
    }

    // MARK: - insert

    func testInsertParsesDefaults() throws {
        let command = try Slides.Text.Insert.parse([
            "deck", "obj", "--text", "Hello",
        ])
        XCTAssertEqual(command.presentationID, "deck")
        XCTAssertEqual(command.objectID, "obj")
        XCTAssertEqual(command.text, "Hello")
        XCTAssertEqual(command.at, 0)
        XCTAssertNil(command.cell.row)
        XCTAssertNil(command.cell.column)
    }

    func testInsertParsesEveryFlag() throws {
        let command = try Slides.Text.Insert.parse([
            "deck", "obj", "--text", "Hi there",
            "--at", "4", "--row", "2", "--column", "3",
        ])
        XCTAssertEqual(command.text, "Hi there")
        XCTAssertEqual(command.at, 4)
        XCTAssertEqual(command.cell.row, 2)
        XCTAssertEqual(command.cell.column, 3)
    }

    func testInsertRequiresText() {
        XCTAssertThrowsError(try Slides.Text.Insert.parse(["deck", "obj"]))
    }

    func testInsertRejectsRowWithoutColumn() {
        XCTAssertThrowsError(try Slides.Text.Insert.parse([
            "deck", "obj", "--text", "x", "--row", "1",
        ]))
    }

    // MARK: - delete

    func testDeleteParsesDefaults() throws {
        let command = try Slides.Text.Delete.parse(["deck", "obj"])
        XCTAssertEqual(command.presentationID, "deck")
        XCTAssertEqual(command.objectID, "obj")
        XCTAssertNil(command.range.from)
        XCTAssertNil(command.range.to)
        XCTAssertNil(command.cell.row)
        XCTAssertNil(command.cell.column)
    }

    func testDeleteParsesEveryFlag() throws {
        let command = try Slides.Text.Delete.parse([
            "deck", "obj", "--from", "2", "--to", "6", "--row", "1", "--column", "4",
        ])
        XCTAssertEqual(command.range.from, 2)
        XCTAssertEqual(command.range.to, 6)
        XCTAssertEqual(command.cell.row, 1)
        XCTAssertEqual(command.cell.column, 4)
    }

    func testDeleteRejectsColumnWithoutRow() {
        XCTAssertThrowsError(try Slides.Text.Delete.parse([
            "deck", "obj", "--column", "2",
        ]))
    }

    // MARK: - style

    func testStyleRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Text.Style.parse(["deck", "obj"]))
    }

    func testStyleParsesEveryFlag() throws {
        let command = try Slides.Text.Style.parse([
            "deck", "obj",
            "--from", "1", "--to", "5",
            "--row", "2", "--column", "3",
            "--bold", "--italic", "--underline", "--strikethrough", "--small-caps",
            "--color", "#FF0000", "--background", "accent1",
            "--font", "Arial", "--font-weight", "700", "--size", "18",
            "--baseline", "superscript",
            "--link", "https://example.com",
        ])
        XCTAssertEqual(command.range.from, 1)
        XCTAssertEqual(command.range.to, 5)
        XCTAssertEqual(command.cell.row, 2)
        XCTAssertEqual(command.cell.column, 3)
        XCTAssertEqual(command.bold, true)
        XCTAssertEqual(command.italic, true)
        XCTAssertEqual(command.underline, true)
        XCTAssertEqual(command.strikethrough, true)
        XCTAssertEqual(command.smallCaps, true)
        XCTAssertEqual(command.color, "#FF0000")
        XCTAssertEqual(command.background, "accent1")
        XCTAssertFalse(command.transparentBackground)
        XCTAssertEqual(command.font, "Arial")
        XCTAssertEqual(command.fontWeight, 700)
        XCTAssertEqual(command.size, 18)
        XCTAssertEqual(command.baseline, .superscript)
        XCTAssertEqual(command.link, "https://example.com")
        XCTAssertFalse(command.noLink)
    }

    func testStyleParsesFlagInversions() throws {
        let on = try Slides.Text.Style.parse([
            "deck", "obj", "--bold", "--italic", "--underline",
            "--strikethrough", "--small-caps",
        ])
        XCTAssertEqual(on.bold, true)
        XCTAssertEqual(on.italic, true)
        XCTAssertEqual(on.underline, true)
        XCTAssertEqual(on.strikethrough, true)
        XCTAssertEqual(on.smallCaps, true)

        let off = try Slides.Text.Style.parse([
            "deck", "obj", "--no-bold", "--no-italic", "--no-underline",
            "--no-strikethrough", "--no-small-caps",
        ])
        XCTAssertEqual(off.bold, false)
        XCTAssertEqual(off.italic, false)
        XCTAssertEqual(off.underline, false)
        XCTAssertEqual(off.strikethrough, false)
        XCTAssertEqual(off.smallCaps, false)

        // Omitting a pair leaves it unchanged (nil); another flag keeps it valid.
        let unset = try Slides.Text.Style.parse(["deck", "obj", "--italic"])
        XCTAssertNil(unset.bold)
        XCTAssertNil(unset.underline)
        XCTAssertNil(unset.strikethrough)
        XCTAssertNil(unset.smallCaps)
    }

    func testStyleParsesEachLinkForm() throws {
        let url = try Slides.Text.Style.parse([
            "deck", "obj", "--link", "https://example.com",
        ])
        XCTAssertEqual(url.link, "https://example.com")

        let slide = try Slides.Text.Style.parse(["deck", "obj", "--link-slide", "2"])
        XCTAssertEqual(slide.linkSlide, 2)

        let page = try Slides.Text.Style.parse(["deck", "obj", "--link-page", "slide-9"])
        XCTAssertEqual(page.linkPage, "slide-9")

        let relative = try Slides.Text.Style.parse([
            "deck", "obj", "--link-relative", "next",
        ])
        XCTAssertEqual(relative.linkRelative, .next)
    }

    func testStyleParsesNoLink() throws {
        let command = try Slides.Text.Style.parse(["deck", "obj", "--no-link"])
        XCTAssertTrue(command.noLink)
    }

    func testStyleRejectsExclusiveLinkFlags() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--link", "https://example.com", "--no-link",
        ]))
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--link", "https://example.com", "--link-slide", "2",
        ]))
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--link-page", "p", "--link-relative", "first",
        ]))
    }

    func testStyleParsesTransparentBackground() throws {
        let command = try Slides.Text.Style.parse([
            "deck", "obj", "--transparent-background",
        ])
        XCTAssertTrue(command.transparentBackground)
    }

    func testStyleRejectsBackgroundAndTransparent() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--background", "#F00", "--transparent-background",
        ]))
    }

    func testStyleParsesBaselineKebab() throws {
        let normal = try Slides.Text.Style.parse(["deck", "obj", "--baseline", "normal"])
        XCTAssertEqual(normal.baseline, .normal)
        let superscript = try Slides.Text.Style.parse([
            "deck", "obj", "--baseline", "superscript",
        ])
        XCTAssertEqual(superscript.baseline, .superscript)
        let sub = try Slides.Text.Style.parse(["deck", "obj", "--baseline", "subscript"])
        XCTAssertEqual(sub.baseline, .`subscript`)
    }

    func testStyleRejectsUnknownBaseline() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--baseline", "SUPERSCRIPT",
        ]))
    }

    func testStyleRejectsFontWeightWithoutFont() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--font-weight", "700",
        ]))
    }

    func testStyleRejectsFontWeightNotMultipleOf100() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--font", "Arial", "--font-weight", "750",
        ]))
    }

    func testStyleRejectsFontWeightOutOfRange() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--font", "Arial", "--font-weight", "1000",
        ]))
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--font", "Arial", "--font-weight", "0",
        ]))
    }

    func testStyleRejectsNonPositiveSize() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--size", "0",
        ]))
    }

    func testStyleRejectsNonOneBasedLinkSlide() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--link-slide", "0",
        ]))
    }

    func testStyleRejectsRowWithoutColumn() {
        XCTAssertThrowsError(try Slides.Text.Style.parse([
            "deck", "obj", "--bold", "--row", "1",
        ]))
    }

    // MARK: - paragraph

    func testParagraphRejectsNoFlags() {
        XCTAssertThrowsError(try Slides.Text.Paragraph.parse(["deck", "obj"]))
    }

    func testParagraphParsesEveryFlag() throws {
        let command = try Slides.Text.Paragraph.parse([
            "deck", "obj",
            "--from", "0", "--to", "10", "--row", "1", "--column", "2",
            "--align", "center", "--line-spacing", "150",
            "--space-above", "6", "--space-below", "8",
            "--indent-start", "12", "--indent-end", "4", "--indent-first-line", "18",
            "--direction", "rtl", "--spacing-mode", "collapse-lists",
        ])
        XCTAssertEqual(command.range.from, 0)
        XCTAssertEqual(command.range.to, 10)
        XCTAssertEqual(command.cell.row, 1)
        XCTAssertEqual(command.cell.column, 2)
        XCTAssertEqual(command.align, .center)
        XCTAssertEqual(command.lineSpacing, 150)
        XCTAssertEqual(command.spaceAbove, 6)
        XCTAssertEqual(command.spaceBelow, 8)
        XCTAssertEqual(command.indentStart, 12)
        XCTAssertEqual(command.indentEnd, 4)
        XCTAssertEqual(command.indentFirstLine, 18)
        XCTAssertEqual(command.direction, .rtl)
        XCTAssertEqual(command.spacingMode, .collapseLists)
    }

    func testParagraphParsesEachAlignmentAndDirection() throws {
        for name in ["start", "center", "end", "justified"] {
            let command = try Slides.Text.Paragraph.parse(["deck", "obj", "--align", name])
            XCTAssertEqual(command.align?.rawValue, name)
        }
        let ltr = try Slides.Text.Paragraph.parse(["deck", "obj", "--direction", "ltr"])
        XCTAssertEqual(ltr.direction, .ltr)
        let neverCollapse = try Slides.Text.Paragraph.parse([
            "deck", "obj", "--spacing-mode", "never-collapse",
        ])
        XCTAssertEqual(neverCollapse.spacingMode, .neverCollapse)
    }

    func testParagraphRejectsNonPositiveLineSpacing() {
        XCTAssertThrowsError(try Slides.Text.Paragraph.parse([
            "deck", "obj", "--line-spacing", "0",
        ]))
    }

    func testParagraphRejectsRowWithoutColumn() {
        XCTAssertThrowsError(try Slides.Text.Paragraph.parse([
            "deck", "obj", "--align", "start", "--row", "1",
        ]))
    }

    func testParagraphRejectsUnknownEnums() {
        XCTAssertThrowsError(try Slides.Text.Paragraph.parse([
            "deck", "obj", "--align", "middle",
        ]))
        XCTAssertThrowsError(try Slides.Text.Paragraph.parse([
            "deck", "obj", "--direction", "left-to-right",
        ]))
        XCTAssertThrowsError(try Slides.Text.Paragraph.parse([
            "deck", "obj", "--spacing-mode", "COLLAPSE_LISTS",
        ]))
    }

    // MARK: - bullets

    func testBulletsParsesDefault() throws {
        let command = try Slides.Text.Bullets.parse(["deck", "obj"])
        XCTAssertEqual(command.presentationID, "deck")
        XCTAssertEqual(command.objectID, "obj")
        XCTAssertNil(command.preset)
        XCTAssertNil(command.range.from)
        XCTAssertNil(command.cell.row)
    }

    func testBulletsParsesPresetAndRangeAndCell() throws {
        let command = try Slides.Text.Bullets.parse([
            "deck", "obj", "--from", "1", "--to", "9", "--row", "2", "--column", "1",
            "--preset", "digit-alpha-roman",
        ])
        XCTAssertEqual(command.range.from, 1)
        XCTAssertEqual(command.range.to, 9)
        XCTAssertEqual(command.cell.row, 2)
        XCTAssertEqual(command.cell.column, 1)
        XCTAssertEqual(command.preset, .digitAlphaRoman)
    }

    func testBulletsRejectsUnknownPreset() {
        XCTAssertThrowsError(try Slides.Text.Bullets.parse([
            "deck", "obj", "--preset", "BULLET_CHECKBOX",
        ]))
        XCTAssertThrowsError(try Slides.Text.Bullets.parse([
            "deck", "obj", "--preset", "smiley",
        ]))
    }

    func testBulletsRejectsRowWithoutColumn() {
        XCTAssertThrowsError(try Slides.Text.Bullets.parse([
            "deck", "obj", "--row", "1",
        ]))
    }

    // MARK: - unbullet

    func testUnbulletParsesRangeAndCell() throws {
        let command = try Slides.Text.Unbullet.parse([
            "deck", "obj", "--from", "0", "--to", "4", "--row", "1", "--column", "1",
        ])
        XCTAssertEqual(command.range.from, 0)
        XCTAssertEqual(command.range.to, 4)
        XCTAssertEqual(command.cell.row, 1)
        XCTAssertEqual(command.cell.column, 1)
    }

    func testUnbulletRejectsColumnWithoutRow() {
        XCTAssertThrowsError(try Slides.Text.Unbullet.parse([
            "deck", "obj", "--column", "1",
        ]))
    }

    // MARK: - CLI enum mapping (normative wire values)

    func testTextBaselineArgumentMapsEveryCase() {
        XCTAssertEqual(TextBaselineArgument.normal.baselineOffset.rawValue, "NONE")
        XCTAssertEqual(TextBaselineArgument.superscript.baselineOffset.rawValue, "SUPERSCRIPT")
        XCTAssertEqual(TextBaselineArgument.`subscript`.baselineOffset.rawValue, "SUBSCRIPT")
    }

    func testRelativeLinkArgumentMapsEveryCase() {
        XCTAssertEqual(RelativeLinkArgument.next.relativeSlideLink.rawValue, "NEXT_SLIDE")
        XCTAssertEqual(
            RelativeLinkArgument.previous.relativeSlideLink.rawValue, "PREVIOUS_SLIDE")
        XCTAssertEqual(RelativeLinkArgument.first.relativeSlideLink.rawValue, "FIRST_SLIDE")
        XCTAssertEqual(RelativeLinkArgument.last.relativeSlideLink.rawValue, "LAST_SLIDE")
    }

    func testParagraphAlignmentArgumentMapsEveryCase() {
        XCTAssertEqual(ParagraphAlignmentArgument.start.alignment.rawValue, "START")
        XCTAssertEqual(ParagraphAlignmentArgument.center.alignment.rawValue, "CENTER")
        XCTAssertEqual(ParagraphAlignmentArgument.end.alignment.rawValue, "END")
        XCTAssertEqual(ParagraphAlignmentArgument.justified.alignment.rawValue, "JUSTIFIED")
    }

    func testTextDirectionArgumentMapsEveryCase() {
        XCTAssertEqual(TextDirectionArgument.ltr.direction.rawValue, "LEFT_TO_RIGHT")
        XCTAssertEqual(TextDirectionArgument.rtl.direction.rawValue, "RIGHT_TO_LEFT")
    }

    func testSpacingModeArgumentMapsEveryCase() {
        XCTAssertEqual(SpacingModeArgument.neverCollapse.spacingMode.rawValue, "NEVER_COLLAPSE")
        XCTAssertEqual(SpacingModeArgument.collapseLists.spacingMode.rawValue, "COLLAPSE_LISTS")
    }

    func testBulletPresetArgumentMapsAllKebabCases() throws {
        let cases: [(String, String)] = [
            ("disc-circle-square", "BULLET_DISC_CIRCLE_SQUARE"),
            ("diamondx-arrow3d-square", "BULLET_DIAMONDX_ARROW3D_SQUARE"),
            ("checkbox", "BULLET_CHECKBOX"),
            ("arrow-diamond-disc", "BULLET_ARROW_DIAMOND_DISC"),
            ("star-circle-square", "BULLET_STAR_CIRCLE_SQUARE"),
            ("arrow3d-circle-square", "BULLET_ARROW3D_CIRCLE_SQUARE"),
            ("lefttriangle-diamond-disc", "BULLET_LEFTTRIANGLE_DIAMOND_DISC"),
            ("diamondx-hollowdiamond-square", "BULLET_DIAMONDX_HOLLOWDIAMOND_SQUARE"),
            ("diamond-circle-square", "BULLET_DIAMOND_CIRCLE_SQUARE"),
            ("digit-alpha-roman", "NUMBERED_DIGIT_ALPHA_ROMAN"),
            ("digit-alpha-roman-parens", "NUMBERED_DIGIT_ALPHA_ROMAN_PARENS"),
            ("digit-nested", "NUMBERED_DIGIT_NESTED"),
            ("upperalpha-alpha-roman", "NUMBERED_UPPERALPHA_ALPHA_ROMAN"),
            ("upperroman-upperalpha-digit", "NUMBERED_UPPERROMAN_UPPERALPHA_DIGIT"),
            ("zerodigit-alpha-roman", "NUMBERED_ZERODIGIT_ALPHA_ROMAN"),
        ]
        XCTAssertEqual(cases.count, 15)
        for (kebab, wire) in cases {
            let command = try Slides.Text.Bullets.parse(["deck", "obj", "--preset", kebab])
            XCTAssertEqual(command.preset?.bulletPreset.rawValue, wire)
        }
    }
}
