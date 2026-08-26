import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the `docs style`, `docs paragraph`, and
/// `docs heading` commands. These check how flags bind and how the CLI enums map
/// to the Docs wire spellings; they never build an API client or touch the
/// network.
final class DocsStyleParsingTests: XCTestCase {
    // MARK: - registration

    func testDocsRegistersTheStylingSubcommands() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Style"), "docs should list a Style subcommand: \(names)")
        XCTAssertTrue(names.contains("Paragraph"), "docs should list a Paragraph subcommand: \(names)")
        XCTAssertTrue(names.contains("Heading"), "docs should list a Heading subcommand: \(names)")
    }

    // MARK: - docs style

    func testDocsStyleParsesRangeAndFlags() throws {
        let command = try Docs.Style.parse([
            "doc-1", "--from", "1", "--to", "9",
            "--bold", "--italic", "--underline", "--strike",
            "--color", "#FF0000", "--background", "#0000FF",
            "--size", "12", "--font", "Arial", "--font-weight", "700",
            "--baseline", "super", "--link", "https://example.com",
            "--segment", "hdr-1", "--require-revision", "rev-2",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 1)
        XCTAssertEqual(command.to, 9)
        XCTAssertEqual(command.bold, true)
        XCTAssertEqual(command.italic, true)
        XCTAssertEqual(command.underline, true)
        XCTAssertEqual(command.strike, true)
        XCTAssertEqual(command.color, "#FF0000")
        XCTAssertEqual(command.background, "#0000FF")
        XCTAssertEqual(command.size, 12)
        XCTAssertEqual(command.font, "Arial")
        XCTAssertEqual(command.fontWeight, 700)
        XCTAssertEqual(command.baseline, .superscript)
        XCTAssertEqual(command.link, "https://example.com")
        XCTAssertEqual(command.segment, "hdr-1")
        XCTAssertEqual(command.requireRevision, "rev-2")
    }

    func testDocsStyleNoBoldSetsFalse() throws {
        let command = try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5", "--no-bold"])
        XCTAssertEqual(command.bold, false)
    }

    func testDocsStyleLeavesToggleFlagsNilWhenAbsent() throws {
        let command = try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5", "--italic"])
        XCTAssertNil(command.bold)
        XCTAssertNil(command.underline)
        XCTAssertNil(command.strike)
    }

    func testDocsStyleRequiresDocumentAndBothBounds() {
        XCTAssertThrowsError(try Docs.Style.parse([]))
        XCTAssertThrowsError(try Docs.Style.parse(["doc-1", "--bold"]))
        XCTAssertThrowsError(try Docs.Style.parse(["doc-1", "--from", "1", "--bold"]))
        XCTAssertThrowsError(try Docs.Style.parse(["doc-1", "--to", "5", "--bold"]))
    }

    func testDocsStyleRequiresAtLeastOneStyleFlag() {
        XCTAssertThrowsError(try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5"])) { error in
            let message = Docs.Style.message(for: error)
            XCTAssertTrue(
                message.contains("at least one"), "Expected a no-style message: \(message)")
        }
    }

    func testDocsStyleFontWeightRequiresFont() {
        XCTAssertThrowsError(
            try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5", "--font-weight", "700"])
        ) { error in
            let message = Docs.Style.message(for: error)
            XCTAssertTrue(
                message.contains("--font-weight requires --font"),
                "Expected a weight-needs-font message: \(message)")
        }
    }

    func testDocsStyleRejectsAWeightOutsideTheAllowedSteps() {
        XCTAssertThrowsError(
            try Docs.Style.parse([
                "doc-1", "--from", "1", "--to", "5", "--font", "Arial", "--font-weight", "250",
            ])
        )
    }

    func testDocsStyleRejectsANonPositiveSize() {
        XCTAssertThrowsError(
            try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5", "--size", "0"])
        )
    }

    func testDocsStyleBaselineArgumentMapsToTheWireOffset() {
        XCTAssertEqual(DocsBaselineArgument.superscript.baselineOffset.rawValue, "SUPERSCRIPT")
        XCTAssertEqual(DocsBaselineArgument.`subscript`.baselineOffset.rawValue, "SUBSCRIPT")
        XCTAssertEqual(DocsBaselineArgument.normal.baselineOffset.rawValue, "NONE")
    }

    func testDocsStyleParsesSubAndNoneBaselines() throws {
        let sub = try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5", "--baseline", "sub"])
        XCTAssertEqual(sub.baseline, .`subscript`)
        let none = try Docs.Style.parse(["doc-1", "--from", "1", "--to", "5", "--baseline", "none"])
        XCTAssertEqual(none.baseline, .normal)
    }

    // MARK: - docs paragraph

    func testDocsParagraphParsesRangeAndFlags() throws {
        let command = try Docs.Paragraph.parse([
            "doc-1", "--from", "3", "--to", "20",
            "--style", "heading-2", "--align", "center", "--direction", "rtl",
            "--line-spacing", "150", "--space-above", "6", "--space-below", "6",
            "--indent-start", "18", "--indent-end", "9", "--indent-first-line", "36",
            "--segment", "ftr-2", "--require-revision", "rev-3",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 3)
        XCTAssertEqual(command.to, 20)
        XCTAssertEqual(command.style, .heading2)
        XCTAssertEqual(command.align, .center)
        XCTAssertEqual(command.direction, .rtl)
        XCTAssertEqual(command.lineSpacing, 150)
        XCTAssertEqual(command.spaceAbove, 6)
        XCTAssertEqual(command.spaceBelow, 6)
        XCTAssertEqual(command.indentStart, 18)
        XCTAssertEqual(command.indentEnd, 9)
        XCTAssertEqual(command.indentFirstLine, 36)
        XCTAssertEqual(command.segment, "ftr-2")
        XCTAssertEqual(command.requireRevision, "rev-3")
    }

    func testDocsParagraphRequiresDocumentAndBothBounds() {
        XCTAssertThrowsError(try Docs.Paragraph.parse([]))
        XCTAssertThrowsError(try Docs.Paragraph.parse(["doc-1", "--align", "center"]))
        XCTAssertThrowsError(try Docs.Paragraph.parse(["doc-1", "--from", "1", "--align", "center"]))
    }

    func testDocsParagraphRequiresAtLeastOneStyleFlag() {
        XCTAssertThrowsError(
            try Docs.Paragraph.parse(["doc-1", "--from", "1", "--to", "9"])
        ) { error in
            let message = Docs.Paragraph.message(for: error)
            XCTAssertTrue(
                message.contains("at least one"), "Expected a no-style message: \(message)")
        }
    }

    func testDocsParagraphRejectsANonPositiveLineSpacing() {
        XCTAssertThrowsError(
            try Docs.Paragraph.parse(["doc-1", "--from", "1", "--to", "9", "--line-spacing", "0"])
        )
    }

    func testDocsNamedStyleArgumentMapsToTheWireValue() {
        XCTAssertEqual(DocsNamedStyleArgument.normalText.namedStyleType, "NORMAL_TEXT")
        XCTAssertEqual(DocsNamedStyleArgument.title.namedStyleType, "TITLE")
        XCTAssertEqual(DocsNamedStyleArgument.subtitle.namedStyleType, "SUBTITLE")
        XCTAssertEqual(DocsNamedStyleArgument.heading1.namedStyleType, "HEADING_1")
        XCTAssertEqual(DocsNamedStyleArgument.heading6.namedStyleType, "HEADING_6")
    }

    func testDocsParagraphAlignmentAndDirectionMapToTheWire() {
        XCTAssertEqual(DocsAlignmentArgument.start.alignment.rawValue, "START")
        XCTAssertEqual(DocsAlignmentArgument.center.alignment.rawValue, "CENTER")
        XCTAssertEqual(DocsAlignmentArgument.end.alignment.rawValue, "END")
        XCTAssertEqual(DocsAlignmentArgument.justified.alignment.rawValue, "JUSTIFIED")
        XCTAssertEqual(DocsDirectionArgument.ltr.direction.rawValue, "LEFT_TO_RIGHT")
        XCTAssertEqual(DocsDirectionArgument.rtl.direction.rawValue, "RIGHT_TO_LEFT")
    }

    // MARK: - docs heading

    func testDocsHeadingParsesLevelAndRange() throws {
        let command = try Docs.Heading.parse(["doc-1", "3", "--from", "1", "--to", "10"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.level, .three)
        XCTAssertEqual(command.from, 1)
        XCTAssertEqual(command.to, 10)
    }

    func testDocsHeadingLevelMapsToTheWireValue() {
        XCTAssertEqual(DocsHeadingLevelArgument.one.namedStyleType, "HEADING_1")
        XCTAssertEqual(DocsHeadingLevelArgument.six.namedStyleType, "HEADING_6")
        XCTAssertEqual(DocsHeadingLevelArgument.title.namedStyleType, "TITLE")
        XCTAssertEqual(DocsHeadingLevelArgument.subtitle.namedStyleType, "SUBTITLE")
        XCTAssertEqual(DocsHeadingLevelArgument.normal.namedStyleType, "NORMAL_TEXT")
    }

    func testDocsHeadingRequiresALevelAndBothBounds() {
        XCTAssertThrowsError(try Docs.Heading.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Heading.parse(["doc-1", "2"]))
        XCTAssertThrowsError(try Docs.Heading.parse(["doc-1", "2", "--from", "1"]))
    }

    func testDocsHeadingRejectsAnUnknownLevel() {
        XCTAssertThrowsError(try Docs.Heading.parse(["doc-1", "7", "--from", "1", "--to", "10"]))
    }
}
