import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 `updateTextStyle` and `updateParagraphStyle`
/// write path. Every fixture is static JSON; no test touches the network, and
/// each request body is asserted exactly, including its deterministic `fields`
/// mask string (the shared encoder sorts keys, so the strings are stable).
final class DocsStyleWriteTests: GrahamTestCase {

    // MARK: - updateTextStyle

    func testStyleTextPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 5, bold: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold","range":{"endIndex":5,"startIndex":1},"textStyle":{"bold":true}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    /// Locks the full mask order and every field encoding in one body: the mask
    /// is `bold,italic,underline,strikethrough,foregroundColor,backgroundColor,`
    /// `fontSize,weightedFontFamily,baselineOffset,link`.
    func testStyleTextEmitsEveryFieldInTheFixedMaskOrder() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1",
            startIndex: 2,
            endIndex: 8,
            bold: true,
            italic: true,
            underline: true,
            strikethrough: true,
            foregroundColor: try DocsOptionalColor.parse("#FF0000"),
            backgroundColor: try DocsOptionalColor.parse("#0000FF"),
            fontSize: 12,
            fontFamily: "Arial",
            fontWeight: 700,
            baselineOffset: .superscript,
            linkURL: "https://example.com"
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold,italic,underline,strikethrough,foregroundColor,backgroundColor,fontSize,weightedFontFamily,baselineOffset,link","range":{"endIndex":8,"startIndex":2},"textStyle":{"backgroundColor":{"color":{"rgbColor":{"blue":1,"green":0,"red":0}}},"baselineOffset":"SUPERSCRIPT","bold":true,"fontSize":{"magnitude":12,"unit":"PT"},"foregroundColor":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}},"italic":true,"link":{"url":"https:\/\/example.com"},"strikethrough":true,"underline":true,"weightedFontFamily":{"fontFamily":"Arial","weight":700}}}}]}"#
        )
    }

    func testStyleTextFontFamilyWithoutWeightOmitsWeight() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 4, fontFamily: "Georgia")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"weightedFontFamily","range":{"endIndex":4,"startIndex":1},"textStyle":{"weightedFontFamily":{"fontFamily":"Georgia"}}}}]}"#
        )
    }

    func testStyleTextCarriesSegmentIdAndAllowsIndexZeroInSegment() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "hdr-1", italic: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"italic","range":{"endIndex":4,"segmentId":"hdr-1","startIndex":0},"textStyle":{"italic":true}}}]}"#
        )
    }

    func testStyleTextEmptySegmentIdEncodesNoSegmentId() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        // An empty segment id means the body: no segmentId leaks into the range.
        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 4, segmentId: "", bold: false)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold","range":{"endIndex":4,"startIndex":1},"textStyle":{"bold":false}}}]}"#
        )
    }

    func testStyleTextCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 5, bold: true,
            requiredRevisionId: "rev-7")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold","range":{"endIndex":5,"startIndex":1},"textStyle":{"bold":true}}}],"writeControl":{"requiredRevisionId":"rev-7"}}"#
        )
    }

    func testStyleTextDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 5, bold: true)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testStyleTextRejectsBadArgumentsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // No style option at all.
        await assertInvalidArgument {
            _ = try await client.styleText(documentId: "doc-1", startIndex: 1, endIndex: 5)
        }
        // endIndex must be greater than startIndex.
        await assertInvalidArgument {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 5, endIndex: 5, bold: true)
        }
        await assertInvalidArgument {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 8, endIndex: 4, bold: true)
        }
        // A font weight without a family.
        await assertInvalidArgument {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 1, endIndex: 5, fontWeight: 700)
        }
        // A weight that is not a multiple of 100 in 100...900.
        await assertInvalidArgument {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 1, endIndex: 5,
                fontFamily: "Arial", fontWeight: 250)
        }
        // A non-positive font size.
        await assertInvalidArgument {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 1, endIndex: 5, fontSize: 0)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleTextRejectsBodyStartIndexZeroWithoutSendingARequest() async {
        // Index 0 lands inside the initial section break the body cannot edit;
        // the body guard rejects it before any request goes out. A named
        // segment starts at 0 and is still allowed (covered above).
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        await assertInvalidArgument {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 0, endIndex: 4, bold: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleTextRejectsBlankFontFamilyWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        for blank in ["", "   ", "\t\n"] {
            await assertInvalidArgument {
                _ = try await client.styleText(
                    documentId: "doc-1", startIndex: 1, endIndex: 5, fontFamily: blank)
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleTextPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad range","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad range") {
            _ = try await client.styleText(
                documentId: "doc-1", startIndex: 1, endIndex: 5, bold: true)
        }
    }

    // MARK: - updateTextStyle: smallCaps

    func testStyleTextSmallCapsAlonePostsExactBodyAndMask() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 5, smallCaps: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"smallCaps","range":{"endIndex":5,"startIndex":1},"textStyle":{"smallCaps":true}}}]}"#
        )
    }

    /// smallCaps is appended after the existing entries, so a bold + link +
    /// smallCaps call locks the mask order `bold,link,smallCaps`.
    func testStyleTextSmallCapsFollowsExistingFieldsInTheMask() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 2, endIndex: 8,
            bold: true, linkURL: "https://example.com", smallCaps: false)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold,link,smallCaps","range":{"endIndex":8,"startIndex":2},"textStyle":{"bold":true,"link":{"url":"https:\/\/example.com"},"smallCaps":false}}}]}"#
        )
    }

    // MARK: - updateParagraphStyle

    func testStyleParagraphsPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, namedStyleType: "HEADING_1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"namedStyleType","paragraphStyle":{"namedStyleType":"HEADING_1"},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    /// Locks the full paragraph mask order and every field encoding.
    func testStyleParagraphsEmitsEveryFieldInTheFixedMaskOrder() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1",
            startIndex: 3,
            endIndex: 20,
            namedStyleType: "normal_text",
            alignment: .center,
            direction: .rightToLeft,
            lineSpacing: 150,
            spaceAbove: 6,
            spaceBelow: 6,
            indentStart: 18,
            indentEnd: 9,
            indentFirstLine: 36
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"namedStyleType,alignment,direction,lineSpacing,spaceAbove,spaceBelow,indentStart,indentEnd,indentFirstLine","paragraphStyle":{"alignment":"CENTER","direction":"RIGHT_TO_LEFT","indentEnd":{"magnitude":9,"unit":"PT"},"indentFirstLine":{"magnitude":36,"unit":"PT"},"indentStart":{"magnitude":18,"unit":"PT"},"lineSpacing":150,"namedStyleType":"NORMAL_TEXT","spaceAbove":{"magnitude":6,"unit":"PT"},"spaceBelow":{"magnitude":6,"unit":"PT"}},"range":{"endIndex":20,"startIndex":3}}}]}"#
        )
    }

    func testStyleParagraphsCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "ftr-2", alignment: .end)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"alignment","paragraphStyle":{"alignment":"END"},"range":{"endIndex":4,"segmentId":"ftr-2","startIndex":0}}}]}"#
        )
    }

    func testStyleParagraphsNamedStyleIsCaseInsensitive() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, namedStyleType: "Heading_2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"namedStyleType","paragraphStyle":{"namedStyleType":"HEADING_2"},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
    }

    func testStyleParagraphsCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, alignment: .start,
            requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"alignment","paragraphStyle":{"alignment":"START"},"range":{"endIndex":10,"startIndex":1}}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    func testStyleParagraphsDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, alignment: .center)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testStyleParagraphsRejectsBadArgumentsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // No style option at all.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(documentId: "doc-1", startIndex: 1, endIndex: 10)
        }
        // endIndex must be greater than startIndex.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 10, endIndex: 10, alignment: .center)
        }
        // An unknown named style.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, namedStyleType: "HEADING_9")
        }
        // A non-positive line spacing.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, lineSpacing: 0)
        }
        // A negative indent.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, indentStart: -1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleParagraphsRejectsBodyStartIndexZeroWithoutSendingARequest() async {
        // The body guard rejects startIndex 0 before any request goes out; a
        // named segment starts at 0 and is still allowed (covered above).
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 0, endIndex: 10, alignment: .center)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleParagraphsPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":403,"message":"No access","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )

        await assertGoogleError(code: 403, status: "PERMISSION_DENIED", message: "No access") {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, alignment: .center)
        }
    }

    // MARK: - updateParagraphStyle: pagination, shading, and spacing

    func testStyleParagraphsKeepLinesTogetherAlonePostsExactBodyAndMask() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, keepLinesTogether: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"keepLinesTogether","paragraphStyle":{"keepLinesTogether":true},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
    }

    /// The new fields are appended after the existing entries, so an alignment
    /// (existing) plus every new field locks the mask order
    /// `alignment,keepLinesTogether,keepWithNext,avoidWidowAndOrphan,`
    /// `pageBreakBefore,shading,spacingMode`.
    func testStyleParagraphsEmitsEveryNewFieldAfterExistingInTheMask() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1",
            startIndex: 1,
            endIndex: 10,
            alignment: .center,
            keepLinesTogether: true,
            keepWithNext: true,
            avoidWidowAndOrphan: false,
            pageBreakBefore: true,
            shadingBackgroundColor: try DocsOptionalColor.parse("#FF0000"),
            spacingMode: .collapseLists
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"alignment,keepLinesTogether,keepWithNext,avoidWidowAndOrphan,pageBreakBefore,shading,spacingMode","paragraphStyle":{"alignment":"CENTER","avoidWidowAndOrphan":false,"keepLinesTogether":true,"keepWithNext":true,"pageBreakBefore":true,"shading":{"backgroundColor":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}}},"spacingMode":"COLLAPSE_LISTS"},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
    }

    func testStyleParagraphsShadingAloneWrapsTheColorInAShading() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10,
            shadingBackgroundColor: try DocsOptionalColor.parse("#00FF00"))

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"shading","paragraphStyle":{"shading":{"backgroundColor":{"color":{"rgbColor":{"blue":0,"green":1,"red":0}}}}},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
    }

    func testStyleParagraphsSpacingModeEmitsTheWireSpelling() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, spacingMode: .neverCollapse)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"spacingMode","paragraphStyle":{"spacingMode":"NEVER_COLLAPSE"},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
    }

    /// The spacing-mode raw values match the discovery document exactly, so the
    /// enum never drifts from the wire spelling.
    func testSpacingModeRawValuesMatchTheWireSpellings() {
        XCTAssertEqual(DocsSpacingMode.neverCollapse.rawValue, "NEVER_COLLAPSE")
        XCTAssertEqual(DocsSpacingMode.collapseLists.rawValue, "COLLAPSE_LISTS")
    }

    // MARK: - updateParagraphStyle: borders

    /// A single outer border color fans to all four outer sides, each carrying a
    /// full border (color + default width 1pt, padding 0pt, and solid dash). The
    /// mask lists the four outer paths in the fixed order.
    func testStyleParagraphsOuterBorderFansToTheFourOuterSides() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10,
            outerBorderColor: try DocsOptionalColor.parse("#FF0000"))

        // The identical border repeats across the four outer sides; build the
        // expected body from that one piece so the repetition is unmistakable.
        let border = #"{"color":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}},"dashStyle":"SOLID","padding":{"magnitude":0,"unit":"PT"},"width":{"magnitude":1,"unit":"PT"}}"#
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            "{\"requests\":[{\"updateParagraphStyle\":{"
            + "\"fields\":\"borderTop,borderBottom,borderLeft,borderRight\","
            + "\"paragraphStyle\":{\"borderBottom\":\(border),\"borderLeft\":\(border),"
            + "\"borderRight\":\(border),\"borderTop\":\(border)},"
            + "\"range\":{\"endIndex\":10,\"startIndex\":1}}}]}"
        )
    }

    /// The between-paragraph border is set on its own path, not fanned to the
    /// four outer sides.
    func testStyleParagraphsBetweenBorderAddsBorderBetweenAlone() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10,
            betweenBorderColor: try DocsOptionalColor.parse("#00FF00"))

        let border = #"{"color":{"color":{"rgbColor":{"blue":0,"green":1,"red":0}}},"dashStyle":"SOLID","padding":{"magnitude":0,"unit":"PT"},"width":{"magnitude":1,"unit":"PT"}}"#
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            "{\"requests\":[{\"updateParagraphStyle\":{"
            + "\"fields\":\"borderBetween\","
            + "\"paragraphStyle\":{\"borderBetween\":\(border)},"
            + "\"range\":{\"endIndex\":10,\"startIndex\":1}}}]}"
        )
    }

    /// Combining an existing paragraph field with both border kinds locks the
    /// order: the borders are appended after `alignment`, outer sides first and
    /// `borderBetween` last, and the shared width/dash/padding reach both borders.
    func testStyleParagraphsBorderFollowsExistingFieldsInTheMask() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10,
            alignment: .center,
            outerBorderColor: try DocsOptionalColor.parse("#FF0000"),
            betweenBorderColor: try DocsOptionalColor.parse("#0000FF"),
            borderWidth: 2,
            borderDash: .dash,
            borderPadding: 3)

        let outer = #"{"color":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}},"dashStyle":"DASH","padding":{"magnitude":3,"unit":"PT"},"width":{"magnitude":2,"unit":"PT"}}"#
        let between = #"{"color":{"color":{"rgbColor":{"blue":1,"green":0,"red":0}}},"dashStyle":"DASH","padding":{"magnitude":3,"unit":"PT"},"width":{"magnitude":2,"unit":"PT"}}"#
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            "{\"requests\":[{\"updateParagraphStyle\":{"
            + "\"fields\":\"alignment,borderTop,borderBottom,borderLeft,borderRight,borderBetween\","
            + "\"paragraphStyle\":{\"alignment\":\"CENTER\",\"borderBetween\":\(between),"
            + "\"borderBottom\":\(outer),\"borderLeft\":\(outer),\"borderRight\":\(outer),"
            + "\"borderTop\":\(outer)},"
            + "\"range\":{\"endIndex\":10,\"startIndex\":1}}}]}"
        )
    }

    /// A border width of 0 hides the border and is accepted; the encoded border
    /// carries a magnitude-0 width.
    func testStyleParagraphsBorderWidthZeroHidesAndIsAccepted() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10,
            outerBorderColor: try DocsOptionalColor.parse("#000000"),
            borderWidth: 0)

        let border = #"{"color":{"color":{"rgbColor":{"blue":0,"green":0,"red":0}}},"dashStyle":"SOLID","padding":{"magnitude":0,"unit":"PT"},"width":{"magnitude":0,"unit":"PT"}}"#
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            "{\"requests\":[{\"updateParagraphStyle\":{"
            + "\"fields\":\"borderTop,borderBottom,borderLeft,borderRight\","
            + "\"paragraphStyle\":{\"borderBottom\":\(border),\"borderLeft\":\(border),"
            + "\"borderRight\":\(border),\"borderTop\":\(border)},"
            + "\"range\":{\"endIndex\":10,\"startIndex\":1}}}]}"
        )
    }

    /// Bad border arguments are rejected before any request goes out: a width,
    /// dash, or padding with no color; a negative width; and a negative padding.
    func testStyleParagraphsRejectsBadBorderArgumentsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // A width with no border color.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, borderWidth: 2)
        }
        // A padding with no border color.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, borderPadding: 2)
        }
        // A dash with no border color.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10, borderDash: .dot)
        }
        // A negative width with a color.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10,
                outerBorderColor: try DocsOptionalColor.parse("#000000"), borderWidth: -1)
        }
        // A negative padding with a color.
        await assertInvalidArgument {
            _ = try await client.styleParagraphs(
                documentId: "doc-1", startIndex: 1, endIndex: 10,
                betweenBorderColor: try DocsOptionalColor.parse("#000000"), borderPadding: -1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    /// A border alone satisfies the at-least-one-style requirement, so a caller
    /// need not pass any other paragraph field.
    func testStyleParagraphsBorderAloneSatisfiesTheAtLeastOneCheck() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10,
            betweenBorderColor: try DocsOptionalColor.parse("#123456"))

        XCTAssertEqual(transport.requests(urlContains: ":batchUpdate").count, 1)
    }

    // MARK: - Color hex -> rgbColor conversion

    func testColorParseMapsHexChannelsToZeroToOne() throws {
        // Pure red: FF -> 1, 00 -> 0.
        let red = try DocsOptionalColor.parse("#FF0000")
        XCTAssertEqual(red.color?.rgbColor?.red, 1)
        XCTAssertEqual(red.color?.rgbColor?.green, 0)
        XCTAssertEqual(red.color?.rgbColor?.blue, 0)

        // A mid-gray exercises the exact component / 255 math.
        let gray = try DocsOptionalColor.parse("#808080")
        XCTAssertEqual(gray.color?.rgbColor?.red, Double(0x80) / 255)
        XCTAssertEqual(gray.color?.rgbColor?.green, Double(0x80) / 255)
        XCTAssertEqual(gray.color?.rgbColor?.blue, Double(0x80) / 255)

        // Distinct channels confirm the byte offsets are not transposed.
        let mixed = try DocsOptionalColor.parse("#123456")
        XCTAssertEqual(mixed.color?.rgbColor?.red, Double(0x12) / 255)
        XCTAssertEqual(mixed.color?.rgbColor?.green, Double(0x34) / 255)
        XCTAssertEqual(mixed.color?.rgbColor?.blue, Double(0x56) / 255)
    }

    func testColorParseAcceptsLowercaseAndAMissingHash() throws {
        let withHash = try DocsOptionalColor.parse("#00ff80")
        let without = try DocsOptionalColor.parse("00FF80")
        XCTAssertEqual(withHash, without)
        XCTAssertEqual(without.color?.rgbColor?.red, 0)
        XCTAssertEqual(without.color?.rgbColor?.green, 1)
        XCTAssertEqual(without.color?.rgbColor?.blue, Double(0x80) / 255)
    }

    func testColorParseRejectsBadHex() {
        // Wrong length (3-digit short form is not accepted), and a non-hex digit.
        for bad in ["#F00", "#12345", "#1234567", "#12345G", "nope", ""] {
            XCTAssertThrowsError(try DocsOptionalColor.parse(bad), "should reject \(bad)") { error in
                guard case GrahamError.invalidArgument = error else {
                    return XCTFail("Wrong error for \(bad): \(error)")
                }
            }
        }
    }

    func testRgbColorInitClampsChannelsIntoZeroToOne() {
        let color = DocsRgbColor(red: 2, green: -0.5, blue: 0.25)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0.25)

        // An in-range color is left untouched.
        let ok = DocsRgbColor(red: 0.1, green: 0.2, blue: 0.3)
        XCTAssertEqual(ok.red, 0.1)
        XCTAssertEqual(ok.green, 0.2)
        XCTAssertEqual(ok.blue, 0.3)
    }

    func testRgbColorDecodingIsUnchangedByTheClampingInit() throws {
        // Codable keeps the synthesized decoder, which does not run through the
        // clamping init, so a decoded color round-trips its raw channels.
        let decoded = try GoogleJSON.decoder.decode(
            DocsRgbColor.self, from: Data(#"{"red":0.5,"green":0.25,"blue":0.75}"#.utf8))
        XCTAssertEqual(decoded, DocsRgbColor(red: 0.5, green: 0.25, blue: 0.75))
    }

    // MARK: - Union encoding

    /// Each new case encodes under its own JSON key, so callers can mix these
    /// operations into one batch with the existing text edits.
    func testStyleRequestsEncodeUnderTheirOwnKeys() throws {
        let text = DocsBatchUpdateRequest.updateTextStyle(DocsUpdateTextStyleRequest(
            textStyle: DocsTextStyle(bold: true),
            fields: "bold",
            range: DocsRange(startIndex: 1, endIndex: 2)))
        XCTAssertEqual(
            String(data: try GoogleJSON.encoder.encode(text), encoding: .utf8),
            #"{"updateTextStyle":{"fields":"bold","range":{"endIndex":2,"startIndex":1},"textStyle":{"bold":true}}}"#
        )

        let paragraph = DocsBatchUpdateRequest.updateParagraphStyle(
            DocsUpdateParagraphStyleRequest(
                paragraphStyle: DocsParagraphStyle(alignment: .center),
                fields: "alignment",
                range: DocsRange(startIndex: 1, endIndex: 2)))
        XCTAssertEqual(
            String(data: try GoogleJSON.encoder.encode(paragraph), encoding: .utf8),
            #"{"updateParagraphStyle":{"fields":"alignment","paragraphStyle":{"alignment":"CENTER"},"range":{"endIndex":2,"startIndex":1}}}"#
        )
    }

    // MARK: - Helpers



}
