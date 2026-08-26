import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 `documents.batchUpdate` write path:
/// `insertText`, `deleteContentRange`, `replaceAllText`, the list (bullet) ops,
/// and the `createHeader` / `createFooter` / `deleteHeader` / `deleteFooter` /
/// `createFootnote` ops. Every fixture is static JSON; no test touches the
/// network, and the request bodies are asserted exactly (the shared encoder
/// sorts keys, so the strings are deterministic).
final class DocsWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - insertText

    func testInsertTextPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.insertText(
            documentId: "doc-1", text: "Hello", index: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"location":{"index":5},"text":"Hello"}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testInsertTextDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.insertText(
            documentId: "doc-1", text: "Hi", index: 1)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testInsertTextRejectsBadArgumentsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.insertText(documentId: "doc-1", text: "", index: 1)
        }
        // Index 0 lands inside the initial section break, which the body cannot
        // edit; the guard rejects it before any request goes out.
        await assertInvalidArgument {
            _ = try await client.insertText(documentId: "doc-1", text: "Hi", index: 0)
        }
        await assertInvalidArgument {
            _ = try await client.insertText(documentId: "doc-1", text: "Hi", index: -1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertTextPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad insert","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad insert") {
            _ = try await client.insertText(documentId: "doc-1", text: "Hi", index: 1)
        }
    }

    // MARK: - deleteContentRange

    func testDeleteContentRangePostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.deleteContentRange(
            documentId: "doc-1", startIndex: 5, endIndex: 12)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteContentRange":{"range":{"endIndex":12,"startIndex":5}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testDeleteContentRangeDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.deleteContentRange(
            documentId: "doc-1", startIndex: 1, endIndex: 4)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testDeleteContentRangeRejectsBadRangesWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // startIndex 0 lands inside the initial section break; the guard
        // rejects it before any request goes out.
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: 0, endIndex: 4)
        }
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: -1, endIndex: 4)
        }
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: 4, endIndex: 4)
        }
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: 8, endIndex: 4)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testDeleteContentRangePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":403,"message":"No access","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )

        await assertGoogleError(code: 403, status: "PERMISSION_DENIED", message: "No access") {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: 1, endIndex: 4)
        }
    }

    // MARK: - replaceAllText

    func testReplaceAllTextPostsExactBodyAndReturnsCount() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"replaceAllText":{"occurrencesChanged":3}}]}"#
        )

        let count = try await client.replaceAllText(
            documentId: "doc-1", find: "old", replace: "new", matchCase: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceAllText":{"containsText":{"matchCase":true,"text":"old"},"replaceText":"new"}}]}"#
        )
        XCTAssertEqual(count, 3)
    }

    func testReplaceAllTextDefaultsToCaseInsensitive() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"replaceAllText":{"occurrencesChanged":1}}]}"#
        )

        _ = try await client.replaceAllText(
            documentId: "doc-1", find: "cat", replace: "dog")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceAllText":{"containsText":{"matchCase":false,"text":"cat"},"replaceText":"dog"}}]}"#
        )
    }

    func testReplaceAllTextReturnsZeroForEmptyReply() async throws {
        // No match at all: an empty reply object, and a whole-empty response,
        // both decode to zero occurrences changed.
        for json in ["{}", #"{"documentId":"doc-1","replies":[{}]}"#] {
            let transport = StubTransport()
            let client = makeClient(transport: transport)
            transport.stub(urlContains: ":batchUpdate", json: json)

            let count = try await client.replaceAllText(
                documentId: "doc-1", find: "gone", replace: "x")

            XCTAssertEqual(count, 0, "unexpected count for reply: \(json)")
        }
    }

    func testReplaceAllTextRejectsEmptyFindWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.replaceAllText(documentId: "doc-1", find: "", replace: "new")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testReplaceAllTextPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":404,"message":"No document","status":"NOT_FOUND"}}"#,
            status: 404
        )

        await assertGoogleError(code: 404, status: "NOT_FOUND", message: "No document") {
            _ = try await client.replaceAllText(documentId: "doc-1", find: "a", replace: "b")
        }
    }

    // MARK: - Segment-aware text ops

    func testInsertTextIntoSegmentAllowsIndexZeroAndCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // A named segment starts its content at index 0, which the body guard
        // would reject; here it is allowed, and the location carries segmentId.
        _ = try await client.insertText(
            documentId: "doc-1", text: "Hi", index: 0, segmentId: "hdr-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"location":{"index":0,"segmentId":"hdr-1"},"text":"Hi"}}]}"#
        )
    }

    func testInsertTextBodyGuardStillRejectsIndexZeroWithoutSegment() async {
        // The body guard is unchanged: index 0 in the body (no segment) is
        // rejected before any request goes out.
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.insertText(documentId: "doc-1", text: "Hi", index: 0)
        }
        // In a segment, a negative index is still rejected.
        await assertInvalidArgument {
            _ = try await client.insertText(
                documentId: "doc-1", text: "Hi", index: -1, segmentId: "hdr-1")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertTextEndOfSegmentEncodesEndOfSegmentLocation() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertText(
            documentId: "doc-1", text: "Hi", index: 0, segmentId: "hdr-1", endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // Appending encodes endOfSegmentLocation instead of location; no index
        // is present at all.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"endOfSegmentLocation":{"segmentId":"hdr-1"},"text":"Hi"}}]}"#
        )
    }

    func testInsertTextEndOfBodyIgnoresIndexAndEncodesEmptyEndOfSegment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // No segment and end-of-segment: the destination is the end of the
        // body. The passed index is ignored, and no index guard applies.
        _ = try await client.insertText(
            documentId: "doc-1", text: "Hi", index: 999, endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"endOfSegmentLocation":{},"text":"Hi"}}]}"#
        )
    }

    func testDeleteContentRangeInSegmentAllowsIndexZeroAndCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.deleteContentRange(
            documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "ftr-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteContentRange":{"range":{"endIndex":4,"segmentId":"ftr-2","startIndex":0}}}]}"#
        )
    }

    func testDeleteContentRangeBodyGuardStillRejectsIndexZeroWithoutSegment() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Body: index 0 rejected, unchanged.
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: 0, endIndex: 4)
        }
        // Segment: a negative start is still rejected.
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: -1, endIndex: 4, segmentId: "ftr-2")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Empty segment id means the body

    func testInsertTextEmptySegmentIdUsesTheBodyGuardAndEncodesNoSegmentId() async {
        // The Docs API reads an empty segment id as the body, so the body guard
        // applies: index 0 is rejected before any request goes out.
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.insertText(
                documentId: "doc-1", text: "Hi", index: 0, segmentId: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertTextEmptySegmentIdEncodesLocationWithoutSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // An empty segment id at a body-legal index encodes a plain body
        // location — no empty segmentId leaks into the request.
        _ = try await client.insertText(
            documentId: "doc-1", text: "Hi", index: 1, segmentId: "")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"location":{"index":1},"text":"Hi"}}]}"#
        )
    }

    func testInsertTextEndOfSegmentEmptySegmentIdEncodesEmptyEndOfSegment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // An empty segment id on the append path means the end of the body,
        // encoding an empty endOfSegmentLocation with no segmentId.
        _ = try await client.insertText(
            documentId: "doc-1", text: "Hi", index: 0, segmentId: "", endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"endOfSegmentLocation":{},"text":"Hi"}}]}"#
        )
    }

    func testDeleteContentRangeEmptySegmentIdUsesTheBodyGuardAndEncodesNoSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // Empty segment id: the body guard rejects startIndex 0.
        await assertInvalidArgument {
            _ = try await client.deleteContentRange(
                documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)

        // A body-legal range with an empty segment id encodes a plain body
        // range — no empty segmentId leaks into the request.
        _ = try await client.deleteContentRange(
            documentId: "doc-1", startIndex: 1, endIndex: 4, segmentId: "")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteContentRange":{"range":{"endIndex":4,"startIndex":1}}}]}"#
        )
    }

    // MARK: - WriteControl

    func testInsertTextWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertText(
            documentId: "doc-1", text: "Hello", index: 5, requiredRevisionId: "rev-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // The write control rides alongside the requests, carrying only the
        // required revision (targetRevisionId stays nil and is omitted).
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"location":{"index":5},"text":"Hello"}}],"writeControl":{"requiredRevisionId":"rev-1"}}"#
        )
    }

    func testDeleteContentRangeWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.deleteContentRange(
            documentId: "doc-1", startIndex: 5, endIndex: 12, requiredRevisionId: "rev-9")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteContentRange":{"range":{"endIndex":12,"startIndex":5}}}],"writeControl":{"requiredRevisionId":"rev-9"}}"#
        )
    }

    func testReplaceAllTextWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"replaceAllText":{"occurrencesChanged":1}}]}"#
        )

        _ = try await client.replaceAllText(
            documentId: "doc-1", find: "old", replace: "new", matchCase: true,
            requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceAllText":{"containsText":{"matchCase":true,"text":"old"},"replaceText":"new"}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    func testWriteControlOmittedWhenRevisionIsNil() async throws {
        // The default (no required revision) sends an ordinary body with no
        // writeControl key at all, so existing callers are unchanged.
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertText(documentId: "doc-1", text: "Hello", index: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"location":{"index":5},"text":"Hello"}}]}"#
        )
        XCTAssertFalse(Self.bodyString(request).contains("writeControl"))
    }

    func testBatchUpdateDecodesWriteControlInTheResponse() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}],"writeControl":{"requiredRevisionId":"rev-2"}}"#
        )

        let response = try await client.insertText(documentId: "doc-1", text: "Hi", index: 1)

        XCTAssertEqual(response.writeControl?.requiredRevisionId, "rev-2")
        XCTAssertNil(response.writeControl?.targetRevisionId)
    }

    func testWriteControlEncodesOnlyTheFieldsThatAreSet() throws {
        XCTAssertEqual(
            String(data: try GoogleJSON.encoder.encode(
                DocsWriteControl(requiredRevisionId: "r")), encoding: .utf8),
            #"{"requiredRevisionId":"r"}"#
        )
        XCTAssertEqual(
            String(data: try GoogleJSON.encoder.encode(
                DocsWriteControl(targetRevisionId: "t")), encoding: .utf8),
            #"{"targetRevisionId":"t"}"#
        )
    }

    func testWriteControlIsAOneOfConstructibleWithExactlyOneField() throws {
        // Each dedicated init sets exactly one field and leaves the other nil,
        // so a dual-field body is unrepresentable.
        XCTAssertNil(DocsWriteControl(requiredRevisionId: "r").targetRevisionId)
        XCTAssertNil(DocsWriteControl(targetRevisionId: "t").requiredRevisionId)
        // Both properties stay optional so the response — which may echo either,
        // or an empty object — still decodes.
        let decoded = try GoogleJSON.decoder.decode(
            DocsWriteControl.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.requiredRevisionId)
        XCTAssertNil(decoded.targetRevisionId)
    }

    // MARK: - createParagraphBullets

    func testCreateParagraphBulletsPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.createParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9,
            preset: "BULLET_DISC_CIRCLE_SQUARE")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createParagraphBullets":{"bulletPreset":"BULLET_DISC_CIRCLE_SQUARE","range":{"endIndex":9,"startIndex":1}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testCreateParagraphBulletsDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.createParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9,
            preset: "BULLET_CHECKBOX")

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testCreateParagraphBulletsInSegmentAllowsIndexZeroAndCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // A named segment starts its content at index 0, which the body guard
        // would reject; here it is allowed, and the range carries segmentId.
        _ = try await client.createParagraphBullets(
            documentId: "doc-1", startIndex: 0, endIndex: 4,
            preset: "BULLET_CHECKBOX", segmentId: "ftr-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createParagraphBullets":{"bulletPreset":"BULLET_CHECKBOX","range":{"endIndex":4,"segmentId":"ftr-2","startIndex":0}}}]}"#
        )
    }

    func testCreateParagraphBulletsAcceptsThePresetCaseInsensitively() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // A lowercased API spelling is uppercased before it is matched, so it
        // still encodes the canonical wire value.
        _ = try await client.createParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9,
            preset: "numbered_decimal_alpha_roman")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createParagraphBullets":{"bulletPreset":"NUMBERED_DECIMAL_ALPHA_ROMAN","range":{"endIndex":9,"startIndex":1}}}]}"#
        )
    }

    func testCreateParagraphBulletsWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.createParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9,
            preset: "BULLET_DISC_CIRCLE_SQUARE", requiredRevisionId: "rev-4")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createParagraphBullets":{"bulletPreset":"BULLET_DISC_CIRCLE_SQUARE","range":{"endIndex":9,"startIndex":1}}}],"writeControl":{"requiredRevisionId":"rev-4"}}"#
        )
    }

    func testCreateParagraphBulletsRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // startIndex 0 in the body lands inside the initial section break; the
        // range guard rejects it before any request goes out.
        await assertInvalidArgument {
            _ = try await client.createParagraphBullets(
                documentId: "doc-1", startIndex: 0, endIndex: 4,
                preset: "BULLET_DISC_CIRCLE_SQUARE")
        }
        // A negative start is rejected.
        await assertInvalidArgument {
            _ = try await client.createParagraphBullets(
                documentId: "doc-1", startIndex: -1, endIndex: 4,
                preset: "BULLET_DISC_CIRCLE_SQUARE")
        }
        // An empty range (end not greater than start) is rejected.
        await assertInvalidArgument {
            _ = try await client.createParagraphBullets(
                documentId: "doc-1", startIndex: 4, endIndex: 4,
                preset: "BULLET_DISC_CIRCLE_SQUARE")
        }
        // An unknown preset is rejected before any request goes out.
        await assertInvalidArgument {
            _ = try await client.createParagraphBullets(
                documentId: "doc-1", startIndex: 1, endIndex: 9,
                preset: "BULLET_NOT_A_REAL_PRESET")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateParagraphBulletsPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad bullets","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad bullets") {
            _ = try await client.createParagraphBullets(
                documentId: "doc-1", startIndex: 1, endIndex: 9,
                preset: "BULLET_DISC_CIRCLE_SQUARE")
        }
    }

    /// Every writable preset maps to its exact API wire value, so the enum's raw
    /// values never drift from the discovery document.
    func testDocsBulletPresetRawValuesMatchTheWireSpellings() {
        XCTAssertEqual(
            DocsBulletPreset.allCases.map(\.rawValue),
            [
                "BULLET_DISC_CIRCLE_SQUARE",
                "BULLET_DIAMONDX_ARROW3D_SQUARE",
                "BULLET_CHECKBOX",
                "BULLET_ARROW_DIAMOND_DISC",
                "BULLET_STAR_CIRCLE_SQUARE",
                "BULLET_ARROW3D_CIRCLE_SQUARE",
                "BULLET_LEFTTRIANGLE_DIAMOND_DISC",
                "BULLET_DIAMONDX_HOLLOWDIAMOND_SQUARE",
                "BULLET_DIAMOND_CIRCLE_SQUARE",
                "NUMBERED_DECIMAL_ALPHA_ROMAN",
                "NUMBERED_DECIMAL_ALPHA_ROMAN_PARENS",
                "NUMBERED_DECIMAL_NESTED",
                "NUMBERED_UPPERALPHA_ALPHA_ROMAN",
                "NUMBERED_UPPERROMAN_UPPERALPHA_DECIMAL",
                "NUMBERED_ZERODECIMAL_ALPHA_ROMAN",
            ]
        )
    }

    // MARK: - deleteParagraphBullets

    func testDeleteParagraphBulletsPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.deleteParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteParagraphBullets":{"range":{"endIndex":9,"startIndex":1}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testDeleteParagraphBulletsDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.deleteParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testDeleteParagraphBulletsInSegmentAllowsIndexZeroAndCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.deleteParagraphBullets(
            documentId: "doc-1", startIndex: 0, endIndex: 4, segmentId: "ftr-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteParagraphBullets":{"range":{"endIndex":4,"segmentId":"ftr-2","startIndex":0}}}]}"#
        )
    }

    func testDeleteParagraphBulletsWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.deleteParagraphBullets(
            documentId: "doc-1", startIndex: 1, endIndex: 9, requiredRevisionId: "rev-5")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteParagraphBullets":{"range":{"endIndex":9,"startIndex":1}}}],"writeControl":{"requiredRevisionId":"rev-5"}}"#
        )
    }

    func testDeleteParagraphBulletsRejectsBadRangesWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // startIndex 0 in the body lands inside the initial section break.
        await assertInvalidArgument {
            _ = try await client.deleteParagraphBullets(
                documentId: "doc-1", startIndex: 0, endIndex: 4)
        }
        await assertInvalidArgument {
            _ = try await client.deleteParagraphBullets(
                documentId: "doc-1", startIndex: -1, endIndex: 4)
        }
        await assertInvalidArgument {
            _ = try await client.deleteParagraphBullets(
                documentId: "doc-1", startIndex: 4, endIndex: 4)
        }
        // Segment: a negative start is still rejected.
        await assertInvalidArgument {
            _ = try await client.deleteParagraphBullets(
                documentId: "doc-1", startIndex: -1, endIndex: 4, segmentId: "ftr-2")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testDeleteParagraphBulletsPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":403,"message":"No access","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )

        await assertGoogleError(code: 403, status: "PERMISSION_DENIED", message: "No access") {
            _ = try await client.deleteParagraphBullets(
                documentId: "doc-1", startIndex: 1, endIndex: 9)
        }
    }

    // MARK: - Encoding a mixed batch

    /// The union encodes each case under its own JSON key, so a caller can mix
    /// operations in one batch. This locks the discriminators for all three.
    func testEveryRequestTypeEncodesUnderItsOwnKey() throws {
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .insertText(DocsInsertTextRequest(
                    text: "Hi", location: DocsLocation(index: 0))),
                #"{"insertText":{"location":{"index":0},"text":"Hi"}}"#
            ),
            (
                .deleteContentRange(DocsDeleteContentRangeRequest(
                    range: DocsRange(startIndex: 1, endIndex: 2))),
                #"{"deleteContentRange":{"range":{"endIndex":2,"startIndex":1}}}"#
            ),
            (
                .replaceAllText(DocsReplaceAllTextRequest(
                    replaceText: "b",
                    containsText: DocsSubstringMatchCriteria(text: "a", matchCase: false))),
                #"{"replaceAllText":{"containsText":{"matchCase":false,"text":"a"},"replaceText":"b"}}"#
            ),
            (
                .createParagraphBullets(DocsCreateParagraphBulletsRequest(
                    range: DocsRange(startIndex: 1, endIndex: 9),
                    bulletPreset: .bulletDiscCircleSquare)),
                #"{"createParagraphBullets":{"bulletPreset":"BULLET_DISC_CIRCLE_SQUARE","range":{"endIndex":9,"startIndex":1}}}"#
            ),
            (
                .deleteParagraphBullets(DocsDeleteParagraphBulletsRequest(
                    range: DocsRange(startIndex: 1, endIndex: 9))),
                #"{"deleteParagraphBullets":{"range":{"endIndex":9,"startIndex":1}}}"#
            ),
        ]
        for (request, expected) in cases {
            let data = try GoogleJSON.encoder.encode(request)
            XCTAssertEqual(String(data: data, encoding: .utf8), expected)
        }
    }

    // MARK: - createHeader

    func testCreateHeaderPostsExactBodyAndReturnsHeaderId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"createHeader":{"headerId":"kix.hdr1"}}]}"#
        )

        let result = try await client.createHeader(documentId: "doc-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // The only valid type is DEFAULT, and it is always sent.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createHeader":{"type":"DEFAULT"}}]}"#
        )
        // The reply segment id is returned so a follow-up write can target it.
        XCTAssertEqual(result.headerId, "kix.hdr1")
        XCTAssertEqual(result.response.documentId, "doc-1")
    }

    func testCreateHeaderWithSectionBreakIndexEncodesLocation() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createHeader":{"headerId":"kix.hdr2"}}]}"#
        )

        _ = try await client.createHeader(documentId: "doc-1", sectionBreakIndex: 12)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // The section-break body location scopes the header to a section; sorted
        // keys put sectionBreakLocation before type.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createHeader":{"sectionBreakLocation":{"index":12},"type":"DEFAULT"}}]}"#
        )
    }

    func testCreateHeaderWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createHeader":{"headerId":"kix.hdr3"}}]}"#
        )

        _ = try await client.createHeader(documentId: "doc-1", requiredRevisionId: "rev-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createHeader":{"type":"DEFAULT"}}],"writeControl":{"requiredRevisionId":"rev-1"}}"#
        )
    }

    func testCreateHeaderReturnsNilHeaderIdForEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let result = try await client.createHeader(documentId: "doc-1")

        XCTAssertNil(result.headerId)
        XCTAssertNil(result.response.documentId)
    }

    func testCreateHeaderRejectsBadSectionBreakIndexWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // A provided section-break index follows the body guard: index 0 lands
        // inside the initial section break, so it is rejected before any request.
        await assertInvalidArgument {
            _ = try await client.createHeader(documentId: "doc-1", sectionBreakIndex: 0)
        }
        await assertInvalidArgument {
            _ = try await client.createHeader(documentId: "doc-1", sectionBreakIndex: -1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateHeaderPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad header","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad header") {
            _ = try await client.createHeader(documentId: "doc-1")
        }
    }

    // MARK: - createFooter

    func testCreateFooterPostsExactBodyAndReturnsFooterId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"createFooter":{"footerId":"kix.ftr1"}}]}"#
        )

        let result = try await client.createFooter(documentId: "doc-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createFooter":{"type":"DEFAULT"}}]}"#
        )
        XCTAssertEqual(result.footerId, "kix.ftr1")
        XCTAssertEqual(result.response.documentId, "doc-1")
    }

    func testCreateFooterWithSectionBreakIndexEncodesLocation() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createFooter":{"footerId":"kix.ftr2"}}]}"#
        )

        _ = try await client.createFooter(documentId: "doc-1", sectionBreakIndex: 7)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createFooter":{"sectionBreakLocation":{"index":7},"type":"DEFAULT"}}]}"#
        )
    }

    func testCreateFooterWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createFooter":{"footerId":"kix.ftr3"}}]}"#
        )

        _ = try await client.createFooter(documentId: "doc-1", requiredRevisionId: "rev-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createFooter":{"type":"DEFAULT"}}],"writeControl":{"requiredRevisionId":"rev-2"}}"#
        )
    }

    func testCreateFooterReturnsNilFooterIdForEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let result = try await client.createFooter(documentId: "doc-1")

        XCTAssertNil(result.footerId)
        XCTAssertNil(result.response.documentId)
    }

    func testCreateFooterRejectsBadSectionBreakIndexWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.createFooter(documentId: "doc-1", sectionBreakIndex: 0)
        }
        await assertInvalidArgument {
            _ = try await client.createFooter(documentId: "doc-1", sectionBreakIndex: -1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateFooterPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":403,"message":"No access","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )

        await assertGoogleError(code: 403, status: "PERMISSION_DENIED", message: "No access") {
            _ = try await client.createFooter(documentId: "doc-1")
        }
    }

    // MARK: - deleteHeader

    func testDeleteHeaderPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.deleteHeader(documentId: "doc-1", headerId: "kix.hdr1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteHeader":{"headerId":"kix.hdr1"}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testDeleteHeaderDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.deleteHeader(documentId: "doc-1", headerId: "kix.hdr1")

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testDeleteHeaderWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.deleteHeader(
            documentId: "doc-1", headerId: "kix.hdr1", requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteHeader":{"headerId":"kix.hdr1"}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    func testDeleteHeaderRejectsEmptyIdWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.deleteHeader(documentId: "doc-1", headerId: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testDeleteHeaderPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":404,"message":"No header","status":"NOT_FOUND"}}"#,
            status: 404
        )

        await assertGoogleError(code: 404, status: "NOT_FOUND", message: "No header") {
            _ = try await client.deleteHeader(documentId: "doc-1", headerId: "kix.hdr1")
        }
    }

    // MARK: - deleteFooter

    func testDeleteFooterPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.deleteFooter(documentId: "doc-1", footerId: "kix.ftr1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteFooter":{"footerId":"kix.ftr1"}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testDeleteFooterDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.deleteFooter(documentId: "doc-1", footerId: "kix.ftr1")

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testDeleteFooterWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.deleteFooter(
            documentId: "doc-1", footerId: "kix.ftr1", requiredRevisionId: "rev-4")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteFooter":{"footerId":"kix.ftr1"}}],"writeControl":{"requiredRevisionId":"rev-4"}}"#
        )
    }

    func testDeleteFooterRejectsEmptyIdWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.deleteFooter(documentId: "doc-1", footerId: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testDeleteFooterPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":404,"message":"No footer","status":"NOT_FOUND"}}"#,
            status: 404
        )

        await assertGoogleError(code: 404, status: "NOT_FOUND", message: "No footer") {
            _ = try await client.deleteFooter(documentId: "doc-1", footerId: "kix.ftr1")
        }
    }

    // MARK: - createFootnote

    func testCreateFootnotePostsExactBodyAndReturnsFootnoteId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"createFootnote":{"footnoteId":"kix.fn1"}}]}"#
        )

        let result = try await client.createFootnote(documentId: "doc-1", index: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createFootnote":{"location":{"index":5}}}]}"#
        )
        XCTAssertEqual(result.footnoteId, "kix.fn1")
        XCTAssertEqual(result.response.documentId, "doc-1")
    }

    func testCreateFootnoteEndOfBodyEncodesEmptyEndOfSegment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createFootnote":{"footnoteId":"kix.fn2"}}]}"#
        )

        // End-of-body alone (no index): the reference goes at the end of the body
        // with no segment id.
        _ = try await client.createFootnote(documentId: "doc-1", endOfBody: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createFootnote":{"endOfSegmentLocation":{}}}]}"#
        )
    }

    func testCreateFootnoteReturnsNilFootnoteIdForEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let result = try await client.createFootnote(documentId: "doc-1", index: 5)

        XCTAssertNil(result.footnoteId)
        XCTAssertNil(result.response.documentId)
    }

    func testCreateFootnoteWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createFootnote":{"footnoteId":"kix.fn3"}}]}"#
        )

        _ = try await client.createFootnote(
            documentId: "doc-1", index: 5, requiredRevisionId: "rev-6")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createFootnote":{"location":{"index":5}}}],"writeControl":{"requiredRevisionId":"rev-6"}}"#
        )
    }

    func testCreateFootnoteWithTextMakesTwoBatchUpdatesInOrder() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        // Two responses in order: the first createFootnote reply carries the
        // footnoteId, and the second is the insertText reply.
        transport.stub(urlContains: ":batchUpdate", responses: [
            StubTransport.json(
                #"{"documentId":"doc-1","replies":[{"createFootnote":{"footnoteId":"kix.fn9"}}]}"#),
            StubTransport.json(#"{"documentId":"doc-1","replies":[{}]}"#),
        ])

        let result = try await client.createFootnote(
            documentId: "doc-1", index: 5, text: "See note")

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 2)
        // First: the createFootnote reference at the body index.
        XCTAssertEqual(
            Self.bodyString(requests[0]),
            #"{"requests":[{"createFootnote":{"location":{"index":5}}}]}"#
        )
        // Second: insertText into the returned footnote segment. The segment's
        // content starts with an auto-inserted space and newline, so the text
        // goes at index 1, carrying the returned footnoteId as its segment id.
        XCTAssertEqual(
            Self.bodyString(requests[1]),
            #"{"requests":[{"insertText":{"location":{"index":1,"segmentId":"kix.fn9"},"text":"See note"}}]}"#
        )
        XCTAssertEqual(result.footnoteId, "kix.fn9")
    }

    func testCreateFootnoteWithTextButNoReturnedIdThrowsAfterTheFirstCall() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        // The createFootnote reply carries no footnoteId, so the text cannot be
        // inserted into the (unknown) segment.
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        await assertInvalidArgument {
            _ = try await client.createFootnote(documentId: "doc-1", index: 5, text: "See note")
        }
        // Only the first batchUpdate went out; there is no second call.
        XCTAssertEqual(transport.requests(urlContains: ":batchUpdate").count, 1)
    }

    func testCreateFootnoteRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Index 0 lands inside the initial section break; the body guard rejects
        // it before any request goes out.
        await assertInvalidArgument {
            _ = try await client.createFootnote(documentId: "doc-1", index: 0)
        }
        await assertInvalidArgument {
            _ = try await client.createFootnote(documentId: "doc-1", index: -1)
        }
        // Neither an index nor end-of-body is provided.
        await assertInvalidArgument {
            _ = try await client.createFootnote(documentId: "doc-1")
        }
        // Both an index and end-of-body is ambiguous.
        await assertInvalidArgument {
            _ = try await client.createFootnote(documentId: "doc-1", index: 5, endOfBody: true)
        }
        // An empty --text is rejected up front, so no orphan footnote is created.
        await assertInvalidArgument {
            _ = try await client.createFootnote(documentId: "doc-1", index: 5, text: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateFootnotePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad footnote","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad footnote") {
            _ = try await client.createFootnote(documentId: "doc-1", index: 5)
        }
    }

    // MARK: - Header/footer/footnote enum and union discriminators

    /// The header-footer type raw value matches the discovery document exactly,
    /// so the enum never drifts from the wire spelling.
    func testHeaderFooterTypeRawValueMatchesTheWireSpelling() {
        XCTAssertEqual(DocsHeaderFooterType.default.rawValue, "DEFAULT")
    }

    /// The footnote request is body-only by construction: its entry points build
    /// a location / end-of-segment with no segment id, so no illegal non-body
    /// request is representable.
    func testCreateFootnoteRequestIsBodyOnlyByConstruction() {
        let atIndex = DocsCreateFootnoteRequest(bodyIndex: 5)
        XCTAssertEqual(atIndex.location?.index, 5)
        XCTAssertNil(atIndex.location?.segmentId)
        XCTAssertNil(atIndex.endOfSegmentLocation)

        let end = DocsCreateFootnoteRequest.endOfBody
        XCTAssertNil(end.location)
        XCTAssertNil(end.endOfSegmentLocation?.segmentId)
    }

    /// The union encodes each new case under its own JSON key, so a caller can
    /// mix these operations in one batch. This locks the five discriminators.
    func testEveryHeaderFooterFootnoteRequestTypeEncodesUnderItsOwnKey() throws {
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .createHeader(DocsCreateHeaderRequest()),
                #"{"createHeader":{"type":"DEFAULT"}}"#
            ),
            (
                .createFooter(DocsCreateFooterRequest()),
                #"{"createFooter":{"type":"DEFAULT"}}"#
            ),
            (
                .deleteHeader(DocsDeleteHeaderRequest(headerId: "h-1")),
                #"{"deleteHeader":{"headerId":"h-1"}}"#
            ),
            (
                .deleteFooter(DocsDeleteFooterRequest(footerId: "f-1")),
                #"{"deleteFooter":{"footerId":"f-1"}}"#
            ),
            (
                .createFootnote(DocsCreateFootnoteRequest(bodyIndex: 5)),
                #"{"createFootnote":{"location":{"index":5}}}"#
            ),
        ]
        for (request, expected) in cases {
            let data = try GoogleJSON.encoder.encode(request)
            XCTAssertEqual(String(data: data, encoding: .utf8), expected)
        }
    }

    // MARK: - createNamedRange

    func testCreateNamedRangePostsExactBodyAndReturnsNamedRangeId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"createNamedRange":{"namedRangeId":"nr-1"}}]}"#
        )

        let result = try await client.createNamedRange(
            documentId: "doc-1", name: "greeting", startIndex: 2, endIndex: 8)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createNamedRange":{"name":"greeting","range":{"endIndex":8,"startIndex":2}}}]}"#
        )
        // The reply id is returned so the delete and fill ops can address it.
        XCTAssertEqual(result.namedRangeId, "nr-1")
        XCTAssertEqual(result.response.documentId, "doc-1")
    }

    func testCreateNamedRangeInSegmentCarriesSegmentIdAndAllowsIndexZero() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createNamedRange":{"namedRangeId":"nr-2"}}]}"#
        )

        _ = try await client.createNamedRange(
            documentId: "doc-1", name: "note", startIndex: 0, endIndex: 3,
            segmentId: "kix.ftn1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // A named segment starts its content at index 0, and the segment id rides
        // in the range (sorted keys put endIndex, segmentId, then startIndex).
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createNamedRange":{"name":"note","range":{"endIndex":3,"segmentId":"kix.ftn1","startIndex":0}}}]}"#
        )
    }

    func testCreateNamedRangeWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createNamedRange":{"namedRangeId":"nr-3"}}]}"#
        )

        _ = try await client.createNamedRange(
            documentId: "doc-1", name: "greeting", startIndex: 2, endIndex: 8,
            requiredRevisionId: "rev-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createNamedRange":{"name":"greeting","range":{"endIndex":8,"startIndex":2}}}],"writeControl":{"requiredRevisionId":"rev-1"}}"#
        )
    }

    func testCreateNamedRangeReturnsNilIdForEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let result = try await client.createNamedRange(
            documentId: "doc-1", name: "greeting", startIndex: 2, endIndex: 8)

        XCTAssertNil(result.namedRangeId)
        XCTAssertNil(result.response.documentId)
    }

    func testCreateNamedRangeRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Empty name.
        await assertInvalidArgument {
            _ = try await client.createNamedRange(
                documentId: "doc-1", name: "", startIndex: 1, endIndex: 5)
        }
        // Name longer than 256 UTF-16 code units.
        await assertInvalidArgument {
            _ = try await client.createNamedRange(
                documentId: "doc-1", name: String(repeating: "a", count: 257),
                startIndex: 1, endIndex: 5)
        }
        // endIndex must be greater than startIndex.
        await assertInvalidArgument {
            _ = try await client.createNamedRange(
                documentId: "doc-1", name: "x", startIndex: 5, endIndex: 5)
        }
        // Body index 0 lands inside the initial section break.
        await assertInvalidArgument {
            _ = try await client.createNamedRange(
                documentId: "doc-1", name: "x", startIndex: 0, endIndex: 3)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateNamedRangeMeasuresNameInUTF16CodeUnits() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createNamedRange":{"namedRangeId":"nr-4"}}]}"#
        )

        // 128 emoji is 256 UTF-16 code units — exactly the maximum, so accepted.
        let maxName = String(repeating: "😀", count: 128)
        XCTAssertEqual(maxName.utf16.count, 256)
        _ = try await client.createNamedRange(
            documentId: "doc-1", name: maxName, startIndex: 1, endIndex: 5)
        XCTAssertEqual(transport.requests(urlContains: ":batchUpdate").count, 1)

        // 129 emoji is 258 UTF-16 code units — over the limit, so rejected even
        // though it is only 129 Characters (this proves the count is UTF-16, not
        // Characters).
        let tooLong = String(repeating: "😀", count: 129)
        XCTAssertEqual(tooLong.utf16.count, 258)
        await assertInvalidArgument {
            _ = try await client.createNamedRange(
                documentId: "doc-1", name: tooLong, startIndex: 1, endIndex: 5)
        }
        // Still only the one accepted request went out.
        XCTAssertEqual(transport.requests(urlContains: ":batchUpdate").count, 1)
    }

    func testCreateNamedRangePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad range","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad range") {
            _ = try await client.createNamedRange(
                documentId: "doc-1", name: "greeting", startIndex: 2, endIndex: 8)
        }
    }

    // MARK: - deleteNamedRange

    func testDeleteNamedRangeByIdPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.deleteNamedRange(
            documentId: "doc-1", namedRangeId: "nr-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteNamedRange":{"namedRangeId":"nr-1"}}]}"#
        )
        // A delete replies with an empty object.
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testDeleteNamedRangeByNamePostsExactBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.deleteNamedRange(documentId: "doc-1", name: "greeting")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // The name selector deletes every range sharing the name.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteNamedRange":{"name":"greeting"}}]}"#
        )
    }

    func testDeleteNamedRangeWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.deleteNamedRange(
            documentId: "doc-1", namedRangeId: "nr-1", requiredRevisionId: "rev-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteNamedRange":{"namedRangeId":"nr-1"}}],"writeControl":{"requiredRevisionId":"rev-2"}}"#
        )
    }

    func testDeleteNamedRangeRejectsBadSelectorsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Neither selector.
        await assertInvalidArgument {
            _ = try await client.deleteNamedRange(documentId: "doc-1")
        }
        // Both selectors.
        await assertInvalidArgument {
            _ = try await client.deleteNamedRange(
                documentId: "doc-1", namedRangeId: "nr-1", name: "greeting")
        }
        // Empty id.
        await assertInvalidArgument {
            _ = try await client.deleteNamedRange(documentId: "doc-1", namedRangeId: "")
        }
        // Empty name.
        await assertInvalidArgument {
            _ = try await client.deleteNamedRange(documentId: "doc-1", name: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testDeleteNamedRangePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":404,"message":"No range","status":"NOT_FOUND"}}"#,
            status: 404
        )

        await assertGoogleError(code: 404, status: "NOT_FOUND", message: "No range") {
            _ = try await client.deleteNamedRange(documentId: "doc-1", namedRangeId: "nr-1")
        }
    }

    // MARK: - replaceNamedRangeContent

    func testReplaceNamedRangeContentByIdPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.replaceNamedRangeContent(
            documentId: "doc-1", text: "World", namedRangeId: "nr-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceNamedRangeContent":{"namedRangeId":"nr-1","text":"World"}}]}"#
        )
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testReplaceNamedRangeContentByNameUsesNamedRangeNameField() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.replaceNamedRangeContent(
            documentId: "doc-1", text: "Hi", name: "greeting")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // The name selector uses the `namedRangeName` field (not `name`), matching
        // the API's ReplaceNamedRangeContentRequest.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceNamedRangeContent":{"namedRangeName":"greeting","text":"Hi"}}]}"#
        )
    }

    func testReplaceNamedRangeContentAllowsEmptyTextToClearTheRange() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.replaceNamedRangeContent(
            documentId: "doc-1", text: "", namedRangeId: "nr-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // An empty replacement clears the range and is allowed.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceNamedRangeContent":{"namedRangeId":"nr-1","text":""}}]}"#
        )
    }

    func testReplaceNamedRangeContentWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.replaceNamedRangeContent(
            documentId: "doc-1", text: "World", namedRangeId: "nr-1",
            requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceNamedRangeContent":{"namedRangeId":"nr-1","text":"World"}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    func testReplaceNamedRangeContentRejectsBadSelectorsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Neither selector.
        await assertInvalidArgument {
            _ = try await client.replaceNamedRangeContent(documentId: "doc-1", text: "x")
        }
        // Both selectors.
        await assertInvalidArgument {
            _ = try await client.replaceNamedRangeContent(
                documentId: "doc-1", text: "x", namedRangeId: "nr-1", name: "greeting")
        }
        // Empty id.
        await assertInvalidArgument {
            _ = try await client.replaceNamedRangeContent(
                documentId: "doc-1", text: "x", namedRangeId: "")
        }
        // Empty name.
        await assertInvalidArgument {
            _ = try await client.replaceNamedRangeContent(
                documentId: "doc-1", text: "x", name: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testReplaceNamedRangeContentPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad id","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad id") {
            _ = try await client.replaceNamedRangeContent(
                documentId: "doc-1", text: "World", namedRangeId: "nr-1")
        }
    }

    // MARK: - updateDocumentStyle

    func testUpdateDocumentStyleWithAllOptionsPostsExactBodyAndMask() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let background = try DocsOptionalColor.parse("#FFFFFF")
        _ = try await client.updateDocumentStyle(
            documentId: "doc-1",
            pageWidth: 612, pageHeight: 792,
            marginTop: 72, marginBottom: 72, marginLeft: 90, marginRight: 90,
            useFirstPageHeaderFooter: true, useEvenPageHeaderFooter: false,
            background: background)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        // The fields mask is the fixed documented order; the documentStyle keys
        // are sorted by the shared encoder. pageSize is one Size (width+height).
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDocumentStyle":{"documentStyle":{"background":{"color":{"color":{"rgbColor":{"blue":1,"green":1,"red":1}}}},"marginBottom":{"magnitude":72,"unit":"PT"},"marginLeft":{"magnitude":90,"unit":"PT"},"marginRight":{"magnitude":90,"unit":"PT"},"marginTop":{"magnitude":72,"unit":"PT"},"pageSize":{"height":{"magnitude":792,"unit":"PT"},"width":{"magnitude":612,"unit":"PT"}},"useEvenPageHeaderFooter":false,"useFirstPageHeaderFooter":true},"fields":"pageSize,marginTop,marginBottom,marginLeft,marginRight,useFirstPageHeaderFooter,useEvenPageHeaderFooter,background"}}]}"#
        )
    }

    func testUpdateDocumentStyleMarginsOnlyEmitsMinimalMaskAndBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.updateDocumentStyle(
            documentId: "doc-1", marginTop: 36, marginLeft: 54)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // Only the provided margins appear in the mask, in the fixed order
        // (marginTop before marginLeft); absent fields are omitted entirely.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDocumentStyle":{"documentStyle":{"marginLeft":{"magnitude":54,"unit":"PT"},"marginTop":{"magnitude":36,"unit":"PT"}},"fields":"marginTop,marginLeft"}}]}"#
        )
    }

    func testUpdateDocumentStyleHeaderFooterFlagsAndBackground() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        let background = try DocsOptionalColor.parse("#000000")
        _ = try await client.updateDocumentStyle(
            documentId: "doc-1",
            useFirstPageHeaderFooter: true, useEvenPageHeaderFooter: true,
            background: background)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDocumentStyle":{"documentStyle":{"background":{"color":{"color":{"rgbColor":{"blue":0,"green":0,"red":0}}}},"useEvenPageHeaderFooter":true,"useFirstPageHeaderFooter":true},"fields":"useFirstPageHeaderFooter,useEvenPageHeaderFooter,background"}}]}"#
        )
    }

    func testUpdateDocumentStyleWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.updateDocumentStyle(
            documentId: "doc-1", marginTop: 10, requiredRevisionId: "rev-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDocumentStyle":{"documentStyle":{"marginTop":{"magnitude":10,"unit":"PT"}},"fields":"marginTop"}}],"writeControl":{"requiredRevisionId":"rev-1"}}"#
        )
    }

    func testUpdateDocumentStyleDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.updateDocumentStyle(
            documentId: "doc-1", marginTop: 36)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testUpdateDocumentStyleRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // No option at all.
        await assertInvalidArgument {
            _ = try await client.updateDocumentStyle(documentId: "doc-1")
        }
        // A page width without a page height (the pair must be given together).
        await assertInvalidArgument {
            _ = try await client.updateDocumentStyle(documentId: "doc-1", pageWidth: 612)
        }
        // A page height without a page width.
        await assertInvalidArgument {
            _ = try await client.updateDocumentStyle(documentId: "doc-1", pageHeight: 792)
        }
        // A zero dimension.
        await assertInvalidArgument {
            _ = try await client.updateDocumentStyle(documentId: "doc-1", marginTop: 0)
        }
        // A negative dimension.
        await assertInvalidArgument {
            _ = try await client.updateDocumentStyle(documentId: "doc-1", marginLeft: -5)
        }
        // A non-positive page size dimension (both given, but one is zero).
        await assertInvalidArgument {
            _ = try await client.updateDocumentStyle(
                documentId: "doc-1", pageWidth: 0, pageHeight: 792)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testUpdateDocumentStylePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad style","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad style") {
            _ = try await client.updateDocumentStyle(documentId: "doc-1", marginTop: 36)
        }
    }

    // MARK: - Named-range and document-style union discriminators

    /// The two delete/replace selectors are a one-of: each dedicated init sets
    /// exactly one field, so a dual-selector body is unrepresentable.
    func testNamedRangeSelectorsAreMutuallyExclusiveByConstruction() {
        let deleteById = DocsDeleteNamedRangeRequest(namedRangeId: "nr-1")
        XCTAssertEqual(deleteById.namedRangeId, "nr-1")
        XCTAssertNil(deleteById.name)

        let deleteByName = DocsDeleteNamedRangeRequest(name: "greeting")
        XCTAssertNil(deleteByName.namedRangeId)
        XCTAssertEqual(deleteByName.name, "greeting")

        let replaceById = DocsReplaceNamedRangeContentRequest(namedRangeId: "nr-1", text: "x")
        XCTAssertEqual(replaceById.namedRangeId, "nr-1")
        XCTAssertNil(replaceById.namedRangeName)

        let replaceByName = DocsReplaceNamedRangeContentRequest(namedRangeName: "greeting", text: "x")
        XCTAssertNil(replaceByName.namedRangeId)
        XCTAssertEqual(replaceByName.namedRangeName, "greeting")
    }

    /// The union encodes each new case under its own JSON key, so a caller can mix
    /// these operations in one batch. This locks the four discriminators.
    func testEveryNamedRangeAndDocumentStyleRequestTypeEncodesUnderItsOwnKey() throws {
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .createNamedRange(DocsCreateNamedRangeRequest(
                    name: "greeting", range: DocsRange(startIndex: 2, endIndex: 8))),
                #"{"createNamedRange":{"name":"greeting","range":{"endIndex":8,"startIndex":2}}}"#
            ),
            (
                .deleteNamedRange(DocsDeleteNamedRangeRequest(namedRangeId: "nr-1")),
                #"{"deleteNamedRange":{"namedRangeId":"nr-1"}}"#
            ),
            (
                .replaceNamedRangeContent(DocsReplaceNamedRangeContentRequest(
                    namedRangeName: "greeting", text: "Hi")),
                #"{"replaceNamedRangeContent":{"namedRangeName":"greeting","text":"Hi"}}"#
            ),
            (
                .updateDocumentStyle(DocsUpdateDocumentStyleRequest(
                    documentStyle: DocsDocumentStyle(
                        marginTop: DocsDimension(magnitude: 10, unit: .pt)),
                    fields: "marginTop")),
                #"{"updateDocumentStyle":{"documentStyle":{"marginTop":{"magnitude":10,"unit":"PT"}},"fields":"marginTop"}}"#
            ),
        ]
        for (request, expected) in cases {
            let data = try GoogleJSON.encoder.encode(request)
            XCTAssertEqual(String(data: data, encoding: .utf8), expected)
        }
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
