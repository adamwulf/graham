import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the Phase 8 `docs range` (create / delete / fill)
/// and `docs page-setup` commands. These tests parse arguments and never touch
/// the network; the client behavior is covered by `DocsWriteTests`. Mirrors
/// `DocsHeaderFooterParsingTests` and `DocsWriteParsingTests`.
final class DocsNamedRangeParsingTests: XCTestCase {
    func testDocsRegistersTheRangeAndPageSetupSubcommands() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        for expected in ["NamedRange", "PageSetup"] {
            XCTAssertTrue(names.contains(expected), "docs should list \(expected): \(names)")
        }
    }

    // MARK: - range

    func testDocsRangeListsCreateListDeleteAndFill() {
        let names = Docs.NamedRange.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["create", "list", "delete", "fill"])
    }

    func testRangeIsNamedRangeOnTheWire() {
        XCTAssertEqual(Docs.NamedRange.configuration.commandName, "range")
    }

    // MARK: - range list

    func testRangeListParsesTheDocumentID() throws {
        let command = try Docs.NamedRange.List.parse(["doc-1"])
        XCTAssertEqual(command.documentID, "doc-1")
    }

    func testRangeListDefaultsFormatToTable() throws {
        let command = try Docs.NamedRange.List.parse(["doc-1"])
        XCTAssertEqual(command.format, .table)
    }

    func testRangeListParsesTheFormat() throws {
        let command = try Docs.NamedRange.List.parse(["doc-1", "--format", "json"])
        XCTAssertEqual(command.format, .json)
    }

    func testRangeListRequiresADocumentID() {
        XCTAssertThrowsError(try Docs.NamedRange.List.parse([]))
    }

    // MARK: - range create

    func testRangeCreateParsesArguments() throws {
        let command = try Docs.NamedRange.Create.parse([
            "doc-1", "--name", "greeting", "--from", "2", "--to", "8",
            "--segment", "kix.ftn1", "--require-revision", "rev-1",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.name, "greeting")
        XCTAssertEqual(command.from, 2)
        XCTAssertEqual(command.to, 8)
        XCTAssertEqual(command.segment, "kix.ftn1")
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testRangeCreateDefaultsSegmentAndRevisionToNil() throws {
        let command = try Docs.NamedRange.Create.parse([
            "doc-1", "--name", "greeting", "--from", "2", "--to", "8",
        ])
        XCTAssertNil(command.segment)
        XCTAssertNil(command.requireRevision)
    }

    func testRangeCreateAcceptsA256UTF16Name() throws {
        // 256 UTF-16 code units is exactly the maximum.
        let name = String(repeating: "a", count: 256)
        let command = try Docs.NamedRange.Create.parse([
            "doc-1", "--name", name, "--from", "1", "--to", "5",
        ])
        XCTAssertEqual(command.name.utf16.count, 256)
    }

    func testRangeCreateRejectsNameTooLong() {
        let name = String(repeating: "a", count: 257)
        XCTAssertThrowsError(try Docs.NamedRange.Create.parse([
            "doc-1", "--name", name, "--from", "1", "--to", "5",
        ]))
    }

    func testRangeCreateRejectsEmptyName() {
        XCTAssertThrowsError(try Docs.NamedRange.Create.parse([
            "doc-1", "--name", "", "--from", "1", "--to", "5",
        ]))
    }

    func testRangeCreateRequiresNameFromAndTo() {
        XCTAssertThrowsError(try Docs.NamedRange.Create.parse([]))
        XCTAssertThrowsError(try Docs.NamedRange.Create.parse(["doc-1"]))
        // Missing --to.
        XCTAssertThrowsError(try Docs.NamedRange.Create.parse([
            "doc-1", "--name", "greeting", "--from", "2",
        ]))
    }

    // MARK: - range delete

    func testRangeDeleteParsesId() throws {
        let command = try Docs.NamedRange.Delete.parse([
            "doc-1", "--id", "nr-1", "--require-revision", "rev-2",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.id, "nr-1")
        XCTAssertNil(command.name)
        XCTAssertEqual(command.requireRevision, "rev-2")
    }

    func testRangeDeleteParsesName() throws {
        let command = try Docs.NamedRange.Delete.parse(["doc-1", "--name", "greeting"])
        XCTAssertNil(command.id)
        XCTAssertEqual(command.name, "greeting")
    }

    func testRangeDeleteRejectsBothAndNeitherSelector() {
        // Both --id and --name.
        XCTAssertThrowsError(try Docs.NamedRange.Delete.parse([
            "doc-1", "--id", "nr-1", "--name", "greeting",
        ]))
        // Neither selector.
        XCTAssertThrowsError(try Docs.NamedRange.Delete.parse(["doc-1"]))
    }

    func testRangeDeleteRejectsEmptySelectors() {
        XCTAssertThrowsError(try Docs.NamedRange.Delete.parse(["doc-1", "--id", ""]))
        XCTAssertThrowsError(try Docs.NamedRange.Delete.parse(["doc-1", "--name", ""]))
    }

    // MARK: - range fill

    func testRangeFillParsesIdAndText() throws {
        let command = try Docs.NamedRange.Fill.parse([
            "doc-1", "--id", "nr-1", "--text", "World",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.id, "nr-1")
        XCTAssertNil(command.name)
        XCTAssertEqual(command.text, "World")
    }

    func testRangeFillParsesNameAndText() throws {
        let command = try Docs.NamedRange.Fill.parse([
            "doc-1", "--name", "greeting", "--text", "Hi",
        ])
        XCTAssertNil(command.id)
        XCTAssertEqual(command.name, "greeting")
        XCTAssertEqual(command.text, "Hi")
    }

    func testRangeFillAllowsEmptyText() throws {
        // An empty replacement clears the range and is allowed.
        let command = try Docs.NamedRange.Fill.parse([
            "doc-1", "--id", "nr-1", "--text", "",
        ])
        XCTAssertEqual(command.text, "")
    }

    func testRangeFillRejectsBothAndNeitherSelector() {
        XCTAssertThrowsError(try Docs.NamedRange.Fill.parse([
            "doc-1", "--id", "nr-1", "--name", "greeting", "--text", "x",
        ]))
        XCTAssertThrowsError(try Docs.NamedRange.Fill.parse(["doc-1", "--text", "x"]))
    }

    func testRangeFillRejectsEmptySelectors() {
        XCTAssertThrowsError(try Docs.NamedRange.Fill.parse([
            "doc-1", "--id", "", "--text", "x",
        ]))
        XCTAssertThrowsError(try Docs.NamedRange.Fill.parse([
            "doc-1", "--name", "", "--text", "x",
        ]))
    }

    func testRangeFillRequiresText() {
        XCTAssertThrowsError(try Docs.NamedRange.Fill.parse(["doc-1", "--id", "nr-1"]))
    }

    // MARK: - page-setup

    func testPageSetupParsesAllOptions() throws {
        let command = try Docs.PageSetup.parse([
            "doc-1",
            "--page-width", "612", "--page-height", "792",
            "--margin-top", "72", "--margin-bottom", "72",
            "--margin-left", "90", "--margin-right", "90",
            "--first-page-header-footer", "--no-even-page-header-footer",
            "--background", "#FFFFFF", "--require-revision", "rev-1",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.pageWidth, 612)
        XCTAssertEqual(command.pageHeight, 792)
        XCTAssertEqual(command.marginTop, 72)
        XCTAssertEqual(command.marginBottom, 72)
        XCTAssertEqual(command.marginLeft, 90)
        XCTAssertEqual(command.marginRight, 90)
        XCTAssertEqual(command.firstPageHeaderFooter, true)
        XCTAssertEqual(command.evenPageHeaderFooter, false)
        XCTAssertEqual(command.background, "#FFFFFF")
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testPageSetupDefaultsFlagsToNil() throws {
        let command = try Docs.PageSetup.parse(["doc-1", "--margin-top", "72"])
        XCTAssertNil(command.firstPageHeaderFooter)
        XCTAssertNil(command.evenPageHeaderFooter)
        XCTAssertNil(command.pageWidth)
        XCTAssertNil(command.background)
    }

    func testPageSetupRejectsNoOptions() {
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1"]))
    }

    func testPageSetupRejectsLoneWidthOrHeight() {
        // A page width without a page height.
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--page-width", "612"]))
        // A page height without a page width.
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--page-height", "792"]))
    }

    func testPageSetupRejectsNonPositiveDimensions() {
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-top", "0"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-left", "-5"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse([
            "doc-1", "--page-width", "0", "--page-height", "792",
        ]))
    }

    func testPageSetupParsesMode() throws {
        // --mode alone is enough to satisfy the "at least one option" check.
        let pageless = try Docs.PageSetup.parse(["doc-1", "--mode", "pageless"])
        XCTAssertEqual(pageless.mode, .pageless)
        let pages = try Docs.PageSetup.parse(["doc-1", "--mode", "pages"])
        XCTAssertEqual(pages.mode, .pages)
    }

    func testPageSetupRejectsInvalidMode() {
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--mode", "landscape"]))
    }

    func testPageSetupRejectsNonFiniteDimensions() {
        // Double parses "inf" and "nan"; validation must reject them.
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-top", "inf"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-top", "nan"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse([
            "doc-1", "--page-width", "inf", "--page-height", "792",
        ]))
    }

    func testPageSetupParsesPageNumberMarginsAndFlip() throws {
        let command = try Docs.PageSetup.parse([
            "doc-1",
            "--page-number-start", "3",
            "--margin-header", "24", "--margin-footer", "18",
            "--flip-orientation",
        ])
        XCTAssertEqual(command.pageNumberStart, 3)
        XCTAssertEqual(command.marginHeader, 24)
        XCTAssertEqual(command.marginFooter, 18)
        XCTAssertEqual(command.flipOrientation, true)
    }

    func testPageSetupParsesNoFlipOrientation() throws {
        let command = try Docs.PageSetup.parse(["doc-1", "--no-flip-orientation"])
        XCTAssertEqual(command.flipOrientation, false)
    }

    func testPageSetupNewOptionsSatisfyTheAtLeastOneCheck() throws {
        // Each new option alone is enough to pass the "at least one option" check.
        XCTAssertEqual(
            try Docs.PageSetup.parse(["doc-1", "--page-number-start", "1"]).pageNumberStart, 1)
        XCTAssertEqual(
            try Docs.PageSetup.parse(["doc-1", "--margin-header", "24"]).marginHeader, 24)
        XCTAssertEqual(
            try Docs.PageSetup.parse(["doc-1", "--margin-footer", "24"]).marginFooter, 24)
        XCTAssertEqual(
            try Docs.PageSetup.parse(["doc-1", "--flip-orientation"]).flipOrientation, true)
    }

    func testPageSetupDefaultsNewOptionsToNil() throws {
        let command = try Docs.PageSetup.parse(["doc-1", "--margin-top", "72"])
        XCTAssertNil(command.pageNumberStart)
        XCTAssertNil(command.marginHeader)
        XCTAssertNil(command.marginFooter)
        XCTAssertNil(command.flipOrientation)
    }

    func testPageSetupRejectsPageNumberStartBelowOne() {
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--page-number-start", "0"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--page-number-start", "-1"]))
    }

    func testPageSetupRejectsNonPositiveHeaderFooterMargins() {
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-header", "0"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-footer", "-5"]))
    }

    func testPageSetupRejectsNonFiniteHeaderFooterMargins() {
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-header", "inf"]))
        XCTAssertThrowsError(try Docs.PageSetup.parse(["doc-1", "--margin-footer", "nan"]))
    }

    // MARK: - docs section-style

    func testSectionStyleParsesAllOptions() throws {
        let command = try Docs.SectionStyle.parse([
            "doc-1", "--from", "1", "--to", "20",
            "--margin-top", "72", "--margin-bottom", "72",
            "--margin-left", "90", "--margin-right", "90",
            "--margin-header", "24", "--margin-footer", "24",
            "--direction", "rtl", "--column-separator", "between",
            "--page-number-start", "1",
            "--first-page-header-footer", "--flip-orientation",
            "--require-revision", "rev-1",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 1)
        XCTAssertEqual(command.to, 20)
        XCTAssertEqual(command.marginTop, 72)
        XCTAssertEqual(command.marginFooter, 24)
        XCTAssertEqual(command.direction, .rtl)
        XCTAssertEqual(command.columnSeparator, .between)
        XCTAssertEqual(command.pageNumberStart, 1)
        XCTAssertEqual(command.firstPageHeaderFooter, true)
        XCTAssertEqual(command.flipOrientation, true)
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testSectionStyleParsesColumnSeparatorNoneAndDefaultsFlagsToNil() throws {
        let command = try Docs.SectionStyle.parse([
            "doc-1", "--from", "0", "--to", "5", "--column-separator", "none",
        ])
        XCTAssertEqual(command.columnSeparator, DocsColumnSeparatorArgument.none)
        XCTAssertNil(command.direction)
        XCTAssertNil(command.firstPageHeaderFooter)
        XCTAssertNil(command.flipOrientation)
        XCTAssertNil(command.marginTop)
    }

    func testSectionStyleRejectsNoStyleOptions() {
        XCTAssertThrowsError(try Docs.SectionStyle.parse(["doc-1", "--from", "1", "--to", "5"]))
    }

    func testSectionStyleRejectsBadRange() {
        // --to must be greater than --from.
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "5", "--to", "5", "--margin-top", "36",
        ]))
        // --from must be zero or greater.
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "-1", "--to", "5", "--margin-top", "36",
        ]))
    }

    func testSectionStyleRejectsNonPositiveAndNonFiniteMargins() {
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "1", "--to", "5", "--margin-top", "0",
        ]))
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "1", "--to", "5", "--margin-left", "inf",
        ]))
    }

    func testSectionStyleRejectsInvalidEnumsAndPageNumber() {
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "1", "--to", "5", "--direction", "sideways",
        ]))
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "1", "--to", "5", "--column-separator", "dotted",
        ]))
        XCTAssertThrowsError(try Docs.SectionStyle.parse([
            "doc-1", "--from", "1", "--to", "5", "--page-number-start", "0",
        ]))
    }

    // MARK: - docs named-style

    func testNamedStyleParsesSelectorTextAndParagraphOptions() throws {
        let command = try Docs.NamedStyle.parse([
            "doc-1", "--style", "heading-2",
            "--bold", "--small-caps", "--color", "#1155CC",
            "--size", "18", "--font", "Arial",
            "--align", "center", "--line-spacing", "150", "--space-above", "6",
            "--tab-id", "t.0", "--require-revision", "rev-1",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.style, .heading2)
        XCTAssertEqual(command.bold, true)
        XCTAssertEqual(command.smallCaps, true)
        XCTAssertEqual(command.color, "#1155CC")
        XCTAssertEqual(command.size, 18)
        XCTAssertEqual(command.font, "Arial")
        XCTAssertEqual(command.align, .center)
        XCTAssertEqual(command.lineSpacing, 150)
        XCTAssertEqual(command.spaceAbove, 6)
        XCTAssertEqual(command.tabId, "t.0")
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testNamedStyleRequiresStyleSelector() {
        XCTAssertThrowsError(try Docs.NamedStyle.parse(["doc-1", "--bold"]))
    }

    func testNamedStyleRejectsNoStyleFlags() {
        // --style alone is not a change.
        XCTAssertThrowsError(try Docs.NamedStyle.parse(["doc-1", "--style", "title"]))
    }

    func testNamedStyleRejectsBadFontWeightAndSize() {
        // --font-weight without --font.
        XCTAssertThrowsError(try Docs.NamedStyle.parse([
            "doc-1", "--style", "title", "--font-weight", "700",
        ]))
        // --font-weight not a multiple of 100.
        XCTAssertThrowsError(try Docs.NamedStyle.parse([
            "doc-1", "--style", "title", "--font", "Arial", "--font-weight", "750",
        ]))
        // A non-positive --size.
        XCTAssertThrowsError(try Docs.NamedStyle.parse([
            "doc-1", "--style", "title", "--size", "0",
        ]))
        // A non-positive --line-spacing.
        XCTAssertThrowsError(try Docs.NamedStyle.parse([
            "doc-1", "--style", "title", "--line-spacing", "0",
        ]))
    }

    func testNamedStyleRejectsInvalidSelector() {
        XCTAssertThrowsError(try Docs.NamedStyle.parse([
            "doc-1", "--style", "heading-9", "--bold",
        ]))
    }
}
