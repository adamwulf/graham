import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the `docs bullets` and `docs unbullet` commands.
/// These check how flags bind and how the CLI preset enum maps to the Docs wire
/// spellings; they never build an API client or touch the network.
final class DocsBulletsParsingTests: XCTestCase {
    // MARK: - registration

    func testDocsRegistersTheListSubcommands() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Bullets"), "docs should list a Bullets subcommand: \(names)")
        XCTAssertTrue(names.contains("Unbullet"), "docs should list an Unbullet subcommand: \(names)")
    }

    // MARK: - docs bullets

    func testDocsBulletsParsesRangePresetAndFlags() throws {
        let command = try Docs.Bullets.parse([
            "doc-1", "--from", "1", "--to", "9",
            "--preset", "checkbox",
            "--segment", "ftr-2", "--require-revision", "rev-2",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 1)
        XCTAssertEqual(command.to, 9)
        XCTAssertEqual(command.preset, .checkbox)
        XCTAssertEqual(command.segment, "ftr-2")
        XCTAssertEqual(command.requireRevision, "rev-2")
    }

    func testDocsBulletsDefaultsSegmentAndRevisionToNil() throws {
        let command = try Docs.Bullets.parse([
            "doc-1", "--from", "1", "--to", "9", "--preset", "disc-circle-square",
        ])
        XCTAssertNil(command.segment)
        XCTAssertNil(command.requireRevision)
    }

    func testDocsBulletsRequiresDocumentBothBoundsAndPreset() {
        XCTAssertThrowsError(try Docs.Bullets.parse([]))
        XCTAssertThrowsError(try Docs.Bullets.parse(["doc-1", "--preset", "checkbox"]))
        XCTAssertThrowsError(
            try Docs.Bullets.parse(["doc-1", "--from", "1", "--preset", "checkbox"]))
        XCTAssertThrowsError(
            try Docs.Bullets.parse(["doc-1", "--to", "9", "--preset", "checkbox"]))
        // The preset is required.
        XCTAssertThrowsError(try Docs.Bullets.parse(["doc-1", "--from", "1", "--to", "9"]))
    }

    func testDocsBulletsRejectsAnUnknownPreset() {
        XCTAssertThrowsError(
            try Docs.Bullets.parse([
                "doc-1", "--from", "1", "--to", "9", "--preset", "not-a-real-preset",
            ]))
    }

    /// Every CLI preset short name parses and maps to its exact Docs wire value.
    func testEveryBulletPresetShortNameParsesAndMapsToTheApiValue() throws {
        let expected: [DocsBulletPresetArgument: String] = [
            .discCircleSquare: "BULLET_DISC_CIRCLE_SQUARE",
            .diamondxArrow3dSquare: "BULLET_DIAMONDX_ARROW3D_SQUARE",
            .checkbox: "BULLET_CHECKBOX",
            .arrowDiamondDisc: "BULLET_ARROW_DIAMOND_DISC",
            .starCircleSquare: "BULLET_STAR_CIRCLE_SQUARE",
            .arrow3dCircleSquare: "BULLET_ARROW3D_CIRCLE_SQUARE",
            .lefttriangleDiamondDisc: "BULLET_LEFTTRIANGLE_DIAMOND_DISC",
            .diamondxHollowdiamondSquare: "BULLET_DIAMONDX_HOLLOWDIAMOND_SQUARE",
            .diamondCircleSquare: "BULLET_DIAMOND_CIRCLE_SQUARE",
            .decimalAlphaRoman: "NUMBERED_DECIMAL_ALPHA_ROMAN",
            .decimalAlphaRomanParens: "NUMBERED_DECIMAL_ALPHA_ROMAN_PARENS",
            .decimalNested: "NUMBERED_DECIMAL_NESTED",
            .upperalphaAlphaRoman: "NUMBERED_UPPERALPHA_ALPHA_ROMAN",
            .upperromanUpperalphaDecimal: "NUMBERED_UPPERROMAN_UPPERALPHA_DECIMAL",
            .zerodecimalAlphaRoman: "NUMBERED_ZERODECIMAL_ALPHA_ROMAN",
        ]
        // Guard against a case being added to the argument enum without a
        // matching expectation here.
        XCTAssertEqual(DocsBulletPresetArgument.allCases.count, expected.count)

        for argument in DocsBulletPresetArgument.allCases {
            let command = try Docs.Bullets.parse([
                "doc-1", "--from", "1", "--to", "9", "--preset", argument.rawValue,
            ])
            XCTAssertEqual(
                command.preset, argument,
                "short name \(argument.rawValue) should parse to itself")
            XCTAssertEqual(
                command.preset.bulletPreset, expected[argument],
                "short name \(argument.rawValue) mapped to the wrong wire value")
        }
    }

    func testDocsBulletPresetArgumentMapsToTheTypedPreset() {
        XCTAssertEqual(DocsBulletPresetArgument.checkbox.preset, .bulletCheckbox)
        XCTAssertEqual(
            DocsBulletPresetArgument.decimalNested.preset, .numberedDecimalNested)
        XCTAssertEqual(
            DocsBulletPresetArgument.discCircleSquare.bulletPreset,
            "BULLET_DISC_CIRCLE_SQUARE")
    }

    // MARK: - docs unbullet

    func testDocsUnbulletParsesRangeAndFlags() throws {
        let command = try Docs.Unbullet.parse([
            "doc-1", "--from", "3", "--to", "20",
            "--segment", "hdr-1", "--require-revision", "rev-3",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 3)
        XCTAssertEqual(command.to, 20)
        XCTAssertEqual(command.segment, "hdr-1")
        XCTAssertEqual(command.requireRevision, "rev-3")
    }

    func testDocsUnbulletDefaultsSegmentAndRevisionToNil() throws {
        let command = try Docs.Unbullet.parse(["doc-1", "--from", "1", "--to", "9"])
        XCTAssertNil(command.segment)
        XCTAssertNil(command.requireRevision)
    }

    func testDocsUnbulletRequiresDocumentAndBothBounds() {
        XCTAssertThrowsError(try Docs.Unbullet.parse([]))
        XCTAssertThrowsError(try Docs.Unbullet.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Unbullet.parse(["doc-1", "--from", "1"]))
        XCTAssertThrowsError(try Docs.Unbullet.parse(["doc-1", "--to", "9"]))
    }
}
