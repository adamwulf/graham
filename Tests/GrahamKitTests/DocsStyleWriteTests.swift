import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 `updateTextStyle` and `updateParagraphStyle`
/// write path. Every fixture is static JSON; no test touches the network, and
/// each request body is asserted exactly, including its deterministic `fields`
/// mask string (the shared encoder sorts keys, so the strings are stable).
final class DocsStyleWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - updateTextStyle

    func testStyleTextPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
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
            Self.bodyString(request),
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
        let client = makeClient(transport: transport)
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
            Self.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold,italic,underline,strikethrough,foregroundColor,backgroundColor,fontSize,weightedFontFamily,baselineOffset,link","range":{"endIndex":8,"startIndex":2},"textStyle":{"backgroundColor":{"color":{"rgbColor":{"blue":1,"green":0,"red":0}}},"baselineOffset":"SUPERSCRIPT","bold":true,"fontSize":{"magnitude":12,"unit":"PT"},"foregroundColor":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}},"italic":true,"link":{"url":"https:\/\/example.com"},"strikethrough":true,"underline":true,"weightedFontFamily":{"fontFamily":"Arial","weight":700}}}}]}"#
        )
    }

    func testStyleTextFontFamilyWithoutWeightOmitsWeight() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 4, fontFamily: "Georgia")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"weightedFontFamily","range":{"endIndex":4,"startIndex":1},"textStyle":{"weightedFontFamily":{"fontFamily":"Georgia"}}}}]}"#
        )
    }

    func testStyleTextCarriesSegmentIdAndAllowsIndexZeroInSegment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "hdr-1", italic: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"italic","range":{"endIndex":4,"segmentId":"hdr-1","startIndex":0},"textStyle":{"italic":true}}}]}"#
        )
    }

    func testStyleTextEmptySegmentIdEncodesNoSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        // An empty segment id means the body: no segmentId leaks into the range.
        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 4, segmentId: "", bold: false)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold","range":{"endIndex":4,"startIndex":1},"textStyle":{"bold":false}}}]}"#
        )
    }

    func testStyleTextCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 5, bold: true,
            requiredRevisionId: "rev-7")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateTextStyle":{"fields":"bold","range":{"endIndex":5,"startIndex":1},"textStyle":{"bold":true}}}],"writeControl":{"requiredRevisionId":"rev-7"}}"#
        )
    }

    func testStyleTextDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.styleText(
            documentId: "doc-1", startIndex: 1, endIndex: 5, bold: true)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testStyleTextRejectsBadArgumentsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

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

    func testStyleTextPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
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

    // MARK: - updateParagraphStyle

    func testStyleParagraphsPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
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
            Self.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"namedStyleType","paragraphStyle":{"namedStyleType":"HEADING_1"},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    /// Locks the full paragraph mask order and every field encoding.
    func testStyleParagraphsEmitsEveryFieldInTheFixedMaskOrder() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
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
            Self.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"namedStyleType,alignment,direction,lineSpacing,spaceAbove,spaceBelow,indentStart,indentEnd,indentFirstLine","paragraphStyle":{"alignment":"CENTER","direction":"RIGHT_TO_LEFT","indentEnd":{"magnitude":9,"unit":"PT"},"indentFirstLine":{"magnitude":36,"unit":"PT"},"indentStart":{"magnitude":18,"unit":"PT"},"lineSpacing":150,"namedStyleType":"NORMAL_TEXT","spaceAbove":{"magnitude":6,"unit":"PT"},"spaceBelow":{"magnitude":6,"unit":"PT"}},"range":{"endIndex":20,"startIndex":3}}}]}"#
        )
    }

    func testStyleParagraphsCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "ftr-2", alignment: .end)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"alignment","paragraphStyle":{"alignment":"END"},"range":{"endIndex":4,"segmentId":"ftr-2","startIndex":0}}}]}"#
        )
    }

    func testStyleParagraphsNamedStyleIsCaseInsensitive() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, namedStyleType: "Heading_2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"namedStyleType","paragraphStyle":{"namedStyleType":"HEADING_2"},"range":{"endIndex":10,"startIndex":1}}}]}"#
        )
    }

    func testStyleParagraphsCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, alignment: .start,
            requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateParagraphStyle":{"fields":"alignment","paragraphStyle":{"alignment":"START"},"range":{"endIndex":10,"startIndex":1}}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    func testStyleParagraphsDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.styleParagraphs(
            documentId: "doc-1", startIndex: 1, endIndex: 10, alignment: .center)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testStyleParagraphsRejectsBadArgumentsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

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

    func testStyleParagraphsPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
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

    private func assertInvalidArgument(
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

    private func assertGoogleError(
        code expectedCode: Int,
        status expectedStatus: String,
        message expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(code, expectedCode, file: file, line: line)
            XCTAssertEqual(status, expectedStatus, file: file, line: line)
            XCTAssertEqual(message, expectedMessage, file: file, line: line)
        }
    }

    private static func bodyString(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
