import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 `documents.batchUpdate` write path:
/// `insertText`, `deleteContentRange`, and `replaceAllText`. Every fixture is
/// static JSON; no test touches the network, and the request bodies are
/// asserted exactly (the shared encoder sorts keys, so the strings are
/// deterministic).
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
