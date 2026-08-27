import XCTest
@testable import GrahamKit

/// Offline coverage for Slides text and paragraph writes: `deleteText`,
/// `updateTextStyle` (including links), `updateParagraphStyle`,
/// `createParagraphBullets`, `deleteParagraphBullets`, and the table-cell
/// extension of `insertText`. Every fixture is static JSON; no test touches the
/// network, and the JSON bodies are asserted exactly (the shared encoder sorts
/// keys, so the strings are deterministic).
final class SlidesTextWriteTests: XCTestCase {

    // MARK: - Exact request-union JSON

    func testEveryTextRequestTypeEncodesExactly() throws {
        let cases: [(SlidesBatchUpdateRequest, String)] = [
            // deleteText: each TextRange form, plus a table-cell target.
            (
                .deleteText(DeleteTextRequest(objectId: "obj", textRange: .all)),
                #"{"deleteText":{"objectId":"obj","textRange":{"type":"ALL"}}}"#
            ),
            (
                .deleteText(DeleteTextRequest(objectId: "obj", textRange: .fromIndex(5))),
                #"{"deleteText":{"objectId":"obj","textRange":{"startIndex":5,"type":"FROM_START_INDEX"}}}"#
            ),
            (
                .deleteText(DeleteTextRequest(
                    objectId: "obj",
                    cellLocation: TableCellLocation(rowIndex: 1, columnIndex: 2),
                    textRange: .fixed(start: 2, end: 7))),
                #"{"deleteText":{"cellLocation":{"columnIndex":2,"rowIndex":1},"objectId":"obj","textRange":{"endIndex":7,"startIndex":2,"type":"FIXED_RANGE"}}}"#
            ),
            // updateTextStyle: a bold run with a URL link.
            (
                .updateTextStyle(UpdateTextStyleRequest(
                    objectId: "obj",
                    style: TextStyleValue(bold: true, link: Link(url: "https://example.test")),
                    textRange: .all,
                    fields: "bold,link")),
                #"{"updateTextStyle":{"fields":"bold,link","objectId":"obj","style":{"bold":true,"link":{"url":"https:\/\/example.test"}},"textRange":{"type":"ALL"}}}"#
            ),
            // updateTextStyle: an explicit foreground with a transparent background.
            (
                .updateTextStyle(UpdateTextStyleRequest(
                    objectId: "obj",
                    style: TextStyleValue(
                        foregroundColor: OptionalColor(
                            opaqueColor: OpaqueColor(red: 1, green: 0, blue: 0)),
                        backgroundColor: OptionalColor()),
                    textRange: .all,
                    fields: "foregroundColor,backgroundColor")),
                #"{"updateTextStyle":{"fields":"foregroundColor,backgroundColor","objectId":"obj","style":{"backgroundColor":{},"foregroundColor":{"opaqueColor":{"rgbColor":{"blue":0,"green":0,"red":1}}}},"textRange":{"type":"ALL"}}}"#
            ),
            // updateTextStyle: font family + weight + size + baseline into a cell.
            (
                .updateTextStyle(UpdateTextStyleRequest(
                    objectId: "obj",
                    cellLocation: TableCellLocation(rowIndex: 0, columnIndex: 1),
                    style: TextStyleValue(
                        fontFamily: "Roboto",
                        weightedFontFamily: WeightedFontFamily(fontFamily: "Roboto", weight: 700),
                        fontSize: ElementDimension(magnitude: 24, unit: .pt),
                        baselineOffset: .subscript),
                    textRange: .fromIndex(3),
                    fields: "fontFamily,weightedFontFamily,fontSize,baselineOffset")),
                #"{"updateTextStyle":{"cellLocation":{"columnIndex":1,"rowIndex":0},"fields":"fontFamily,weightedFontFamily,fontSize,baselineOffset","objectId":"obj","style":{"baselineOffset":"SUBSCRIPT","fontFamily":"Roboto","fontSize":{"magnitude":24,"unit":"PT"},"weightedFontFamily":{"fontFamily":"Roboto","weight":700}},"textRange":{"startIndex":3,"type":"FROM_START_INDEX"}}}"#
            ),
            // updateParagraphStyle: every field, exercising the documented mask order.
            (
                .updateParagraphStyle(UpdateParagraphStyleRequest(
                    objectId: "obj",
                    style: ParagraphStyleValue(
                        alignment: .center,
                        lineSpacing: 150,
                        spaceAbove: ElementDimension(magnitude: 6, unit: .pt),
                        spaceBelow: ElementDimension(magnitude: 6, unit: .pt),
                        indentStart: ElementDimension(magnitude: 18, unit: .pt),
                        indentEnd: ElementDimension(magnitude: 0, unit: .pt),
                        indentFirstLine: ElementDimension(magnitude: 36, unit: .pt),
                        direction: .rightToLeft,
                        spacingMode: .collapseLists),
                    textRange: .all,
                    fields: "alignment,lineSpacing,spaceAbove,spaceBelow,indentStart,indentEnd,indentFirstLine,direction,spacingMode")),
                #"{"updateParagraphStyle":{"fields":"alignment,lineSpacing,spaceAbove,spaceBelow,indentStart,indentEnd,indentFirstLine,direction,spacingMode","objectId":"obj","style":{"alignment":"CENTER","direction":"RIGHT_TO_LEFT","indentEnd":{"magnitude":0,"unit":"PT"},"indentFirstLine":{"magnitude":36,"unit":"PT"},"indentStart":{"magnitude":18,"unit":"PT"},"lineSpacing":150,"spaceAbove":{"magnitude":6,"unit":"PT"},"spaceBelow":{"magnitude":6,"unit":"PT"},"spacingMode":"COLLAPSE_LISTS"},"textRange":{"type":"ALL"}}}"#
            ),
            // createParagraphBullets: without a preset (API default applies).
            (
                .createParagraphBullets(CreateParagraphBulletsRequest(
                    objectId: "obj", textRange: .all)),
                #"{"createParagraphBullets":{"objectId":"obj","textRange":{"type":"ALL"}}}"#
            ),
            // createParagraphBullets: with a preset and a fixed range.
            (
                .createParagraphBullets(CreateParagraphBulletsRequest(
                    objectId: "obj",
                    textRange: .fixed(start: 0, end: 10),
                    bulletPreset: .numberedDigitAlphaRoman)),
                #"{"createParagraphBullets":{"bulletPreset":"NUMBERED_DIGIT_ALPHA_ROMAN","objectId":"obj","textRange":{"endIndex":10,"startIndex":0,"type":"FIXED_RANGE"}}}"#
            ),
            // deleteParagraphBullets: into a table cell.
            (
                .deleteParagraphBullets(DeleteParagraphBulletsRequest(
                    objectId: "obj",
                    cellLocation: TableCellLocation(rowIndex: 2, columnIndex: 0),
                    textRange: .all)),
                #"{"deleteParagraphBullets":{"cellLocation":{"columnIndex":0,"rowIndex":2},"objectId":"obj","textRange":{"type":"ALL"}}}"#
            ),
            // insertText: extended with a table-cell target.
            (
                .insertText(InsertTextRequest(
                    objectId: "obj",
                    text: "Hi",
                    insertionIndex: 0,
                    cellLocation: TableCellLocation(rowIndex: 1, columnIndex: 1))),
                #"{"insertText":{"cellLocation":{"columnIndex":1,"rowIndex":1},"insertionIndex":0,"objectId":"obj","text":"Hi"}}"#
            ),
        ]

        for (request, expected) in cases {
            XCTAssertEqual(try encode(request), expected)
        }
    }

    /// The bare `insertText` (no cell) still encodes exactly as before, so the
    /// existing shape-insertion call sites and their fixtures are unchanged.
    func testInsertTextWithoutCellStillOmitsCellLocation() throws {
        XCTAssertEqual(
            try encode(.insertText(InsertTextRequest(
                objectId: "textbox-1", text: "Hello", insertionIndex: 3))),
            #"{"insertText":{"insertionIndex":3,"objectId":"textbox-1","text":"Hello"}}"#
        )
    }

    // MARK: - TextRange and Link one-of forms

    func testTextRangeFormsEncodeExactly() throws {
        // Encoded through deleteText, the smallest request that carries a range.
        XCTAssertEqual(
            try encode(.deleteText(DeleteTextRequest(objectId: "o", textRange: .all))),
            #"{"deleteText":{"objectId":"o","textRange":{"type":"ALL"}}}"#)
        XCTAssertEqual(
            try encode(.deleteText(DeleteTextRequest(objectId: "o", textRange: .fromIndex(0)))),
            #"{"deleteText":{"objectId":"o","textRange":{"startIndex":0,"type":"FROM_START_INDEX"}}}"#)
        XCTAssertEqual(
            try encode(.deleteText(DeleteTextRequest(
                objectId: "o", textRange: .fixed(start: 4, end: 9)))),
            #"{"deleteText":{"objectId":"o","textRange":{"endIndex":9,"startIndex":4,"type":"FIXED_RANGE"}}}"#)
    }

    func testLinkOneOfFormsEncodeExactly() throws {
        XCTAssertEqual(try encodeJSON(Link(url: "https://example.test")),
                       #"{"url":"https:\/\/example.test"}"#)
        XCTAssertEqual(try encodeJSON(Link(relativeLink: .nextSlide)),
                       #"{"relativeLink":"NEXT_SLIDE"}"#)
        XCTAssertEqual(try encodeJSON(Link(pageObjectId: "slide-9")),
                       #"{"pageObjectId":"slide-9"}"#)
        XCTAssertEqual(try encodeJSON(Link(slideIndex: 1)),
                       #"{"slideIndex":1}"#)
    }

    func testRelativeSlideLinkRawValuesMatchTheWire() {
        XCTAssertEqual(RelativeSlideLink.nextSlide.rawValue, "NEXT_SLIDE")
        XCTAssertEqual(RelativeSlideLink.previousSlide.rawValue, "PREVIOUS_SLIDE")
        XCTAssertEqual(RelativeSlideLink.firstSlide.rawValue, "FIRST_SLIDE")
        XCTAssertEqual(RelativeSlideLink.lastSlide.rawValue, "LAST_SLIDE")
    }

    func testBaselineOffsetRawValuesMatchTheWire() {
        XCTAssertEqual(BaselineOffset.none.rawValue, "NONE")
        XCTAssertEqual(BaselineOffset.superscript.rawValue, "SUPERSCRIPT")
        XCTAssertEqual(BaselineOffset.subscript.rawValue, "SUBSCRIPT")
    }

    func testParagraphEnumRawValuesMatchTheWire() {
        XCTAssertEqual(ParagraphAlignment.start.rawValue, "START")
        XCTAssertEqual(ParagraphAlignment.center.rawValue, "CENTER")
        XCTAssertEqual(ParagraphAlignment.end.rawValue, "END")
        XCTAssertEqual(ParagraphAlignment.justified.rawValue, "JUSTIFIED")
        XCTAssertEqual(TextDirection.leftToRight.rawValue, "LEFT_TO_RIGHT")
        XCTAssertEqual(TextDirection.rightToLeft.rawValue, "RIGHT_TO_LEFT")
        XCTAssertEqual(SpacingMode.neverCollapse.rawValue, "NEVER_COLLAPSE")
        XCTAssertEqual(SpacingMode.collapseLists.rawValue, "COLLAPSE_LISTS")
    }

    /// Guards the fifteen normative bullet presets and their exact wire values.
    func testBulletPresetRawValuesMatchTheVerifiedList() {
        let expected: [(BulletPreset, String)] = [
            (.bulletDiscCircleSquare, "BULLET_DISC_CIRCLE_SQUARE"),
            (.bulletDiamondxArrow3dSquare, "BULLET_DIAMONDX_ARROW3D_SQUARE"),
            (.bulletCheckbox, "BULLET_CHECKBOX"),
            (.bulletArrowDiamondDisc, "BULLET_ARROW_DIAMOND_DISC"),
            (.bulletStarCircleSquare, "BULLET_STAR_CIRCLE_SQUARE"),
            (.bulletArrow3dCircleSquare, "BULLET_ARROW3D_CIRCLE_SQUARE"),
            (.bulletLefttriangleDiamondDisc, "BULLET_LEFTTRIANGLE_DIAMOND_DISC"),
            (.bulletDiamondxHollowdiamondSquare, "BULLET_DIAMONDX_HOLLOWDIAMOND_SQUARE"),
            (.bulletDiamondCircleSquare, "BULLET_DIAMOND_CIRCLE_SQUARE"),
            (.numberedDigitAlphaRoman, "NUMBERED_DIGIT_ALPHA_ROMAN"),
            (.numberedDigitAlphaRomanParens, "NUMBERED_DIGIT_ALPHA_ROMAN_PARENS"),
            (.numberedDigitNested, "NUMBERED_DIGIT_NESTED"),
            (.numberedUpperalphaAlphaRoman, "NUMBERED_UPPERALPHA_ALPHA_ROMAN"),
            (.numberedUpperromanUpperalphaDigit, "NUMBERED_UPPERROMAN_UPPERALPHA_DIGIT"),
            (.numberedZerodigitAlphaRoman, "NUMBERED_ZERODIGIT_ALPHA_ROMAN"),
        ]
        XCTAssertEqual(expected.count, 15)
        for (preset, raw) in expected {
            XCTAssertEqual(preset.rawValue, raw)
        }
    }

    /// An `OptionalColor` with no `opaqueColor` is TRANSPARENT and encodes `{}`.
    func testOptionalColorTransparentEncodesAsEmptyObject() throws {
        XCTAssertEqual(try encodeJSON(OptionalColor()), "{}")
        XCTAssertEqual(
            try encodeJSON(OptionalColor(opaqueColor: OpaqueColor(theme: .accent1))),
            #"{"opaqueColor":{"themeColor":"ACCENT1"}}"#)
    }

    // MARK: - Client bodies

    func testEveryTextClientMethodPostsItsExactBody() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        for _ in 0..<9 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        // 0: delete the whole text of a shape.
        try await client.deleteText(presentationId: "deck", objectId: "obj")
        // 1: delete a fixed range in a one-based table cell.
        try await client.deleteText(
            presentationId: "deck", objectId: "obj", from: 2, to: 7, row: 2, column: 3)
        // 2: a comprehensive text style, with a one-based slide link.
        try await client.styleText(
            presentationId: "deck", objectId: "obj", from: 0, to: 4,
            bold: true, italic: false, color: OpaqueColor(theme: .accent1),
            fontFamily: "Arial", fontWeight: 700, fontSize: 18,
            baseline: .superscript, link: .slide(position: 2))
        // 3: a transparent background and a cleared link into a cell.
        try await client.styleText(
            presentationId: "deck", objectId: "obj", row: 1, column: 1,
            transparentBackground: true, clearLink: true)
        // 4: a full paragraph style.
        try await client.styleParagraphs(
            presentationId: "deck", objectId: "obj",
            alignment: .justified, lineSpacing: 115, spaceAbove: 6, spaceBelow: 0,
            indentStart: 18, indentEnd: 0, indentFirstLine: 36,
            direction: .leftToRight, spacingMode: .neverCollapse)
        // 5: bullets with a preset into a cell.
        try await client.createBullets(
            presentationId: "deck", objectId: "obj", from: 0, row: 2, column: 1,
            preset: .bulletCheckbox)
        // 6: bullets with the API default preset over the whole text.
        try await client.createBullets(presentationId: "deck", objectId: "obj")
        // 7: remove bullets from a fixed range.
        try await client.deleteBullets(presentationId: "deck", objectId: "obj", from: 3, to: 9)
        // 8: insert text into a one-based table cell.
        try await client.insertText(
            presentationId: "deck", objectId: "obj", text: "Hi", insertionIndex: 4,
            row: 2, column: 3)

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 9)
        XCTAssertTrue(requests.allSatisfy { $0.method == "POST" })
        XCTAssertTrue(requests.allSatisfy {
            URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.path
                == "/v1/presentations/deck:batchUpdate"
        })

        XCTAssertEqual(Self.body(requests[0]),
            #"{"requests":[{"deleteText":{"objectId":"obj","textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[1]),
            #"{"requests":[{"deleteText":{"cellLocation":{"columnIndex":2,"rowIndex":1},"objectId":"obj","textRange":{"endIndex":7,"startIndex":2,"type":"FIXED_RANGE"}}}]}"#)
        XCTAssertEqual(Self.body(requests[2]),
            #"{"requests":[{"updateTextStyle":{"fields":"bold,italic,foregroundColor,fontFamily,weightedFontFamily,fontSize,baselineOffset,link","objectId":"obj","style":{"baselineOffset":"SUPERSCRIPT","bold":true,"fontFamily":"Arial","fontSize":{"magnitude":18,"unit":"PT"},"foregroundColor":{"opaqueColor":{"themeColor":"ACCENT1"}},"italic":false,"link":{"slideIndex":1},"weightedFontFamily":{"fontFamily":"Arial","weight":700}},"textRange":{"endIndex":4,"startIndex":0,"type":"FIXED_RANGE"}}}]}"#)
        XCTAssertEqual(Self.body(requests[3]),
            #"{"requests":[{"updateTextStyle":{"cellLocation":{"columnIndex":0,"rowIndex":0},"fields":"backgroundColor,link","objectId":"obj","style":{"backgroundColor":{}},"textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[4]),
            #"{"requests":[{"updateParagraphStyle":{"fields":"alignment,lineSpacing,spaceAbove,spaceBelow,indentStart,indentEnd,indentFirstLine,direction,spacingMode","objectId":"obj","style":{"alignment":"JUSTIFIED","direction":"LEFT_TO_RIGHT","indentEnd":{"magnitude":0,"unit":"PT"},"indentFirstLine":{"magnitude":36,"unit":"PT"},"indentStart":{"magnitude":18,"unit":"PT"},"lineSpacing":115,"spaceAbove":{"magnitude":6,"unit":"PT"},"spaceBelow":{"magnitude":0,"unit":"PT"},"spacingMode":"NEVER_COLLAPSE"},"textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[5]),
            #"{"requests":[{"createParagraphBullets":{"bulletPreset":"BULLET_CHECKBOX","cellLocation":{"columnIndex":0,"rowIndex":1},"objectId":"obj","textRange":{"startIndex":0,"type":"FROM_START_INDEX"}}}]}"#)
        XCTAssertEqual(Self.body(requests[6]),
            #"{"requests":[{"createParagraphBullets":{"objectId":"obj","textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[7]),
            #"{"requests":[{"deleteParagraphBullets":{"objectId":"obj","textRange":{"endIndex":9,"startIndex":3,"type":"FIXED_RANGE"}}}]}"#)
        XCTAssertEqual(Self.body(requests[8]),
            #"{"requests":[{"insertText":{"cellLocation":{"columnIndex":2,"rowIndex":1},"insertionIndex":4,"objectId":"obj","text":"Hi"}}]}"#)
    }

    /// A `fontWeight` also writes the plain `fontFamily`, so both mask paths and
    /// both style fields are present and consistent.
    func testStyleTextFontWeightSetsBothFamilyPathsConsistently() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleText(
            presentationId: "deck", objectId: "obj",
            fontFamily: "Times New Roman", fontWeight: 300)

        let body = Self.body(transport.requests(urlContains: ":batchUpdate")[0])
        XCTAssertEqual(body,
            #"{"requests":[{"updateTextStyle":{"fields":"fontFamily,weightedFontFamily","objectId":"obj","style":{"fontFamily":"Times New Roman","weightedFontFamily":{"fontFamily":"Times New Roman","weight":300}},"textRange":{"type":"ALL"}}}]}"#)
    }

    /// A plain `fontFamily` with no weight masks only `fontFamily`.
    func testStyleTextFontFamilyWithoutWeightMasksOnlyFamily() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleText(
            presentationId: "deck", objectId: "obj", fontFamily: "Georgia")

        let body = Self.body(transport.requests(urlContains: ":batchUpdate")[0])
        XCTAssertEqual(body,
            #"{"requests":[{"updateTextStyle":{"fields":"fontFamily","objectId":"obj","style":{"fontFamily":"Georgia"},"textRange":{"type":"ALL"}}}]}"#)
    }

    /// A solid background (no transparency) wraps the color in an OptionalColor.
    func testStyleTextSolidBackgroundWrapsTheColor() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleText(
            presentationId: "deck", objectId: "obj",
            background: OpaqueColor(red: 0, green: 0, blue: 1))

        let body = Self.body(transport.requests(urlContains: ":batchUpdate")[0])
        XCTAssertEqual(body,
            #"{"requests":[{"updateTextStyle":{"fields":"backgroundColor","objectId":"obj","style":{"backgroundColor":{"opaqueColor":{"rgbColor":{"blue":1,"green":0,"red":0}}}},"textRange":{"type":"ALL"}}}]}"#)
    }

    /// Each `TextLinkTarget` maps to the wire link, translating one-based slide
    /// positions to the zero-based `slideIndex`.
    func testStyleTextLinkTargetsTranslateToTheWire() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        for _ in 0..<4 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        try await client.styleText(
            presentationId: "deck", objectId: "obj", link: .url("https://a.test"))
        try await client.styleText(
            presentationId: "deck", objectId: "obj", link: .slide(position: 3))
        try await client.styleText(
            presentationId: "deck", objectId: "obj", link: .page(objectId: "slide-x"))
        try await client.styleText(
            presentationId: "deck", objectId: "obj", link: .relative(.lastSlide))

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(Self.body(requests[0]),
            #"{"requests":[{"updateTextStyle":{"fields":"link","objectId":"obj","style":{"link":{"url":"https:\/\/a.test"}},"textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[1]),
            #"{"requests":[{"updateTextStyle":{"fields":"link","objectId":"obj","style":{"link":{"slideIndex":2}},"textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[2]),
            #"{"requests":[{"updateTextStyle":{"fields":"link","objectId":"obj","style":{"link":{"pageObjectId":"slide-x"}},"textRange":{"type":"ALL"}}}]}"#)
        XCTAssertEqual(Self.body(requests[3]),
            #"{"requests":[{"updateTextStyle":{"fields":"link","objectId":"obj","style":{"link":{"relativeLink":"LAST_SLIDE"}},"textRange":{"type":"ALL"}}}]}"#)
    }

    // MARK: - Range and cell validation

    func testRangeBuilderRejectionsSendNothing() async {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)

        // `to` without `from`.
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", to: 5) }
        // negative `from`.
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", from: -1) }
        // `to` equal to `from`.
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", from: 5, to: 5) }
        // `to` less than `from`.
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", from: 5, to: 3) }
        // negative `from` with a `to`.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj", from: -2, to: 4, bold: true) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCellTargetRejectionsSendNothing() async {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)

        // row without column.
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", row: 1) }
        // column without row.
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", column: 1) }
        // row zero (not one-based).
        await assertInvalid { try await client.deleteText(
            presentationId: "deck", objectId: "obj", row: 0, column: 1) }
        // column zero (not one-based).
        await assertInvalid { try await client.createBullets(
            presentationId: "deck", objectId: "obj", row: 1, column: 0) }
        // through insertText as well.
        await assertInvalid { try await client.insertText(
            presentationId: "deck", objectId: "obj", text: "x", row: 2) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Style validation and mutual exclusions

    func testStyleTextValidationAndExclusionsSendNothing() async {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)

        // no style options at all.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj") }
        // font weight not a multiple of 100.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj", fontFamily: "Arial", fontWeight: 750) }
        // font weight out of range.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj", fontFamily: "Arial", fontWeight: 1000) }
        // font weight without a family.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj", fontWeight: 400) }
        // font size not positive.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj", fontSize: 0) }
        // background color and transparent background together.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj",
            background: OpaqueColor(theme: .accent1), transparentBackground: true) }
        // link and clear-link together.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj",
            link: .url("https://a.test"), clearLink: true) }
        // one-based slide link position of zero.
        await assertInvalid { try await client.styleText(
            presentationId: "deck", objectId: "obj", link: .slide(position: 0)) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleParagraphsValidationSendsNothing() async {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)

        // no options.
        await assertInvalid { try await client.styleParagraphs(
            presentationId: "deck", objectId: "obj") }
        // non-positive line spacing.
        await assertInvalid { try await client.styleParagraphs(
            presentationId: "deck", objectId: "obj", lineSpacing: 0) }
        // negative spacing dimension.
        await assertInvalid { try await client.styleParagraphs(
            presentationId: "deck", objectId: "obj", spaceAbove: -1) }
        // negative indent.
        await assertInvalid { try await client.styleParagraphs(
            presentationId: "deck", objectId: "obj", indentStart: -0.5) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Error propagation

    func testTextMethodPropagatesGoogleErrorEnvelope() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"bad range","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        do {
            try await client.deleteText(presentationId: "deck", objectId: "obj")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "bad range")
        }
    }

    // MARK: - Helpers

    private func assertInvalid(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
        }
    }

    private func encode(_ request: SlidesBatchUpdateRequest) throws -> String {
        String(data: try GoogleJSON.encoder.encode(request), encoding: .utf8) ?? ""
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        String(data: try GoogleJSON.encoder.encode(value), encoding: .utf8) ?? ""
    }

    private static func body(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
