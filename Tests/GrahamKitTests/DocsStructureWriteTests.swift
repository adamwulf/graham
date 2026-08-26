import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 `documents.batchUpdate` structure and image
/// operations: `insertPageBreak`, `insertInlineImage`, `replaceImage`, and
/// `insertSectionBreak`. Every fixture is static
/// JSON; no test touches the network, and the request bodies are asserted
/// exactly (the shared encoder sorts keys, so the strings are deterministic).
/// Mirrors `DocsWriteTests` and `DocsTableWriteTests`.
final class DocsStructureWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    /// A realistic public image URI; its slashes exercise the JSON escaping.
    private static let uri = "https://cdn.example.com/pic.png"
    /// The same URI as it appears once JSON-escaped in an encoded body.
    private static let escapedURI = #"https:\/\/cdn.example.com\/pic.png"#

    // MARK: - insertPageBreak

    func testInsertPageBreakPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.insertPageBreak(documentId: "doc-1", index: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertPageBreak":{"location":{"index":5}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testInsertPageBreakEndOfBodyEncodesEmptyEndOfSegment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // End-of-body alone (no index): the destination is the end of the body
        // with no segment id.
        _ = try await client.insertPageBreak(documentId: "doc-1", endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertPageBreak":{"endOfSegmentLocation":{}}}]}"#
        )
    }

    func testInsertPageBreakRejectsBothIndexAndEndOfBodyWithoutSendingARequest() async {
        // Passing both an index and end-of-body is ambiguous; the client rejects
        // it instead of silently picking one, and sends nothing.
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.insertPageBreak(
                documentId: "doc-1", index: 5, endOfSegment: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertPageBreakDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.insertPageBreak(documentId: "doc-1", index: 1)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testInsertPageBreakWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertPageBreak(
            documentId: "doc-1", index: 5, requiredRevisionId: "rev-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertPageBreak":{"location":{"index":5}}}],"writeControl":{"requiredRevisionId":"rev-1"}}"#
        )
    }

    func testInsertPageBreakRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Index 0 lands inside the initial section break, which the body cannot
        // edit; the guard rejects it before any request goes out.
        await assertInvalidArgument {
            _ = try await client.insertPageBreak(documentId: "doc-1", index: 0)
        }
        await assertInvalidArgument {
            _ = try await client.insertPageBreak(documentId: "doc-1", index: -1)
        }
        // Neither an index nor end-of-body is provided.
        await assertInvalidArgument {
            _ = try await client.insertPageBreak(documentId: "doc-1")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertPageBreakPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad break","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad break") {
            _ = try await client.insertPageBreak(documentId: "doc-1", index: 5)
        }
    }

    // MARK: - insertInlineImage

    func testInsertInlineImagePostsExactBodyAndReturnsObjectId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{"insertInlineImage":{"objectId":"kix.img1"}}]}"#
        )

        let result = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"location":{"index":5},"uri":"\#(Self.escapedURI)"}}]}"#
        )
        // The reply object id is returned so a follow-up edit can address it.
        XCTAssertEqual(result.objectId, "kix.img1")
        XCTAssertEqual(result.response.documentId, "doc-1")
    }

    func testInsertInlineImageWithSizeEncodesObjectSizeInPoints() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"insertInlineImage":{"objectId":"kix.img2"}}]}"#)

        _ = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 5, width: 120, height: 80)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // objectSize carries both dimensions as PT; sorted keys put height first.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"location":{"index":5},"objectSize":{"height":{"magnitude":80,"unit":"PT"},"width":{"magnitude":120,"unit":"PT"}},"uri":"\#(Self.escapedURI)"}}]}"#
        )
    }

    func testInsertInlineImageWithOnlyWidthEncodesOnlyWidth() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"insertInlineImage":{"objectId":"kix.img3"}}]}"#)

        // Giving one dimension lets the API compute the other; only width is
        // encoded, so height is absent from objectSize.
        _ = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 5, width: 200)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"location":{"index":5},"objectSize":{"width":{"magnitude":200,"unit":"PT"}},"uri":"\#(Self.escapedURI)"}}]}"#
        )
    }

    func testInsertInlineImageIntoSegmentAllowsIndexZeroAndCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"insertInlineImage":{"objectId":"kix.img4"}}]}"#)

        // A header segment starts its content at index 0, which the body guard
        // would reject; here it is allowed, and the location carries segmentId.
        _ = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 0, segmentId: "hdr-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"location":{"index":0,"segmentId":"hdr-1"},"uri":"\#(Self.escapedURI)"}}]}"#
        )
    }

    func testInsertInlineImageEndOfSegmentEncodesEndOfSegmentLocation() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"insertInlineImage":{"objectId":"kix.img5"}}]}"#)

        _ = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, endOfSegment: true, segmentId: "ftr-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"endOfSegmentLocation":{"segmentId":"ftr-2"},"uri":"\#(Self.escapedURI)"}}]}"#
        )
    }

    func testInsertInlineImageRejectsBothIndexAndEndOfSegmentWithoutSendingARequest() async {
        // Passing both an index and end-of-segment is ambiguous; the client
        // rejects it instead of silently picking one, and sends nothing.
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.insertInlineImage(
                documentId: "doc-1", uri: Self.uri, index: 5, endOfSegment: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertInlineImageEmptySegmentIdEncodesNoSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"insertInlineImage":{"objectId":"kix.img6"}}]}"#)

        // An empty segment id at a body-legal index encodes a plain body
        // location — no empty segmentId leaks into the request.
        _ = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 1, segmentId: "")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"location":{"index":1},"uri":"\#(Self.escapedURI)"}}]}"#
        )
    }

    func testInsertInlineImageReturnsNilObjectIdForEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        let result = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 1)

        XCTAssertNil(result.objectId)
    }

    func testInsertInlineImageWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"insertInlineImage":{"objectId":"kix.img7"}}]}"#)

        _ = try await client.insertInlineImage(
            documentId: "doc-1", uri: Self.uri, index: 5, requiredRevisionId: "rev-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertInlineImage":{"location":{"index":5},"uri":"\#(Self.escapedURI)"}}],"writeControl":{"requiredRevisionId":"rev-2"}}"#
        )
    }

    func testInsertInlineImageRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Empty URI.
        await assertInvalidArgument {
            _ = try await client.insertInlineImage(documentId: "doc-1", uri: "", index: 5)
        }
        // Body index 0 lands inside the initial section break.
        await assertInvalidArgument {
            _ = try await client.insertInlineImage(documentId: "doc-1", uri: Self.uri, index: 0)
        }
        // A negative index inside a segment is still rejected.
        await assertInvalidArgument {
            _ = try await client.insertInlineImage(
                documentId: "doc-1", uri: Self.uri, index: -1, segmentId: "hdr-1")
        }
        // Neither an index nor end-of-segment is provided.
        await assertInvalidArgument {
            _ = try await client.insertInlineImage(documentId: "doc-1", uri: Self.uri)
        }
        // Non-positive dimensions are rejected.
        await assertInvalidArgument {
            _ = try await client.insertInlineImage(
                documentId: "doc-1", uri: Self.uri, index: 5, width: 0)
        }
        await assertInvalidArgument {
            _ = try await client.insertInlineImage(
                documentId: "doc-1", uri: Self.uri, index: 5, height: -3)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertInlineImagePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad image","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad image") {
            _ = try await client.insertInlineImage(documentId: "doc-1", uri: Self.uri, index: 5)
        }
    }

    // MARK: - replaceImage

    func testReplaceImagePostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let newURI = "https://cdn.example.com/new.png"
        let response = try await client.replaceImage(
            documentId: "doc-1", imageObjectId: "img-1", uri: newURI)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        // The only replace method the API defines is CENTER_CROP; the client
        // always sends it.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceImage":{"imageObjectId":"img-1","imageReplaceMethod":"CENTER_CROP","uri":"https:\/\/cdn.example.com\/new.png"}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testReplaceImageDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.replaceImage(
            documentId: "doc-1", imageObjectId: "img-1", uri: Self.uri)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testReplaceImageWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.replaceImage(
            documentId: "doc-1", imageObjectId: "img-1", uri: Self.uri,
            requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"replaceImage":{"imageObjectId":"img-1","imageReplaceMethod":"CENTER_CROP","uri":"\#(Self.escapedURI)"}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    func testReplaceImageRejectsEmptyIdAndUriWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.replaceImage(documentId: "doc-1", imageObjectId: "", uri: Self.uri)
        }
        await assertInvalidArgument {
            _ = try await client.replaceImage(documentId: "doc-1", imageObjectId: "img-1", uri: "")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testReplaceImagePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":404,"message":"No image","status":"NOT_FOUND"}}"#,
            status: 404
        )

        await assertGoogleError(code: 404, status: "NOT_FOUND", message: "No image") {
            _ = try await client.replaceImage(
                documentId: "doc-1", imageObjectId: "img-1", uri: Self.uri)
        }
    }

    // MARK: - insertSectionBreak

    func testInsertSectionBreakContinuousPostsExactBodyAndDecodesReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.insertSectionBreak(
            documentId: "doc-1", sectionType: "CONTINUOUS", index: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        )
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertSectionBreak":{"location":{"index":3},"sectionType":"CONTINUOUS"}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
        XCTAssertEqual(response.replies?.count, 1)
    }

    func testInsertSectionBreakNextPageEndOfBodyEncodesEmptyEndOfSegment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertSectionBreak(
            documentId: "doc-1", sectionType: "NEXT_PAGE", endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertSectionBreak":{"endOfSegmentLocation":{},"sectionType":"NEXT_PAGE"}}]}"#
        )
    }

    func testInsertSectionBreakAcceptsTheTypeCaseInsensitively() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // A lowercased wire spelling is uppercased before it is matched, so it
        // still encodes the canonical value.
        _ = try await client.insertSectionBreak(
            documentId: "doc-1", sectionType: "next_page", index: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertSectionBreak":{"location":{"index":3},"sectionType":"NEXT_PAGE"}}]}"#
        )
    }

    func testInsertSectionBreakDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.insertSectionBreak(
            documentId: "doc-1", sectionType: "CONTINUOUS", index: 1)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    func testInsertSectionBreakWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertSectionBreak(
            documentId: "doc-1", sectionType: "CONTINUOUS", index: 3,
            requiredRevisionId: "rev-5")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertSectionBreak":{"location":{"index":3},"sectionType":"CONTINUOUS"}}],"writeControl":{"requiredRevisionId":"rev-5"}}"#
        )
    }

    func testInsertSectionBreakRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Unknown section type.
        await assertInvalidArgument {
            _ = try await client.insertSectionBreak(
                documentId: "doc-1", sectionType: "SIDEWAYS", index: 3)
        }
        // Body index 0 lands inside the initial section break.
        await assertInvalidArgument {
            _ = try await client.insertSectionBreak(
                documentId: "doc-1", sectionType: "CONTINUOUS", index: 0)
        }
        await assertInvalidArgument {
            _ = try await client.insertSectionBreak(
                documentId: "doc-1", sectionType: "CONTINUOUS", index: -1)
        }
        // Neither an index nor end-of-body is provided.
        await assertInvalidArgument {
            _ = try await client.insertSectionBreak(documentId: "doc-1", sectionType: "NEXT_PAGE")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertSectionBreakRejectsBothIndexAndEndOfBodyWithoutSendingARequest() async {
        // Passing both an index and end-of-body is ambiguous; the client rejects
        // it instead of silently picking one, and sends nothing.
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.insertSectionBreak(
                documentId: "doc-1", sectionType: "CONTINUOUS", index: 3, endOfSegment: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testInsertSectionBreakPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad section","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "Bad section") {
            _ = try await client.insertSectionBreak(
                documentId: "doc-1", sectionType: "CONTINUOUS", index: 3)
        }
    }

    // MARK: - Enum wire spellings and union discriminators

    /// The body-only page-break and section-break requests are body-only by
    /// construction: their public entry points build a location / end-of-segment
    /// with no segment id, so no illegal non-body request is representable.
    func testBodyOnlyRequestsCarryNoSegmentId() {
        let pageIndex = DocsInsertPageBreakRequest(bodyIndex: 5)
        XCTAssertEqual(pageIndex.location?.index, 5)
        XCTAssertNil(pageIndex.location?.segmentId)
        XCTAssertNil(pageIndex.endOfSegmentLocation)

        let pageEnd = DocsInsertPageBreakRequest.endOfBody
        XCTAssertNil(pageEnd.location)
        XCTAssertNil(pageEnd.endOfSegmentLocation?.segmentId)

        let sectionIndex = DocsInsertSectionBreakRequest(sectionType: .continuous, bodyIndex: 3)
        XCTAssertEqual(sectionIndex.location?.index, 3)
        XCTAssertNil(sectionIndex.location?.segmentId)
        XCTAssertNil(sectionIndex.endOfSegmentLocation)

        let sectionEnd = DocsInsertSectionBreakRequest.endOfBody(sectionType: .nextPage)
        XCTAssertNil(sectionEnd.location)
        XCTAssertNil(sectionEnd.endOfSegmentLocation?.segmentId)
        XCTAssertEqual(sectionEnd.sectionType, .nextPage)
    }

    /// The section-type and image-replace-method raw values match the discovery
    /// document exactly, so the enums never drift from the wire spellings.
    func testStructureEnumRawValuesMatchTheWireSpellings() {
        XCTAssertEqual(DocsSectionType.continuous.rawValue, "CONTINUOUS")
        XCTAssertEqual(DocsSectionType.nextPage.rawValue, "NEXT_PAGE")
        XCTAssertEqual(DocsImageReplaceMethod.centerCrop.rawValue, "CENTER_CROP")
    }

    /// The union encodes each new case under its own JSON key, so a caller can
    /// mix these operations in one batch. This locks the four discriminators.
    func testEveryStructureRequestTypeEncodesUnderItsOwnKey() throws {
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .insertPageBreak(DocsInsertPageBreakRequest(bodyIndex: 5)),
                #"{"insertPageBreak":{"location":{"index":5}}}"#
            ),
            (
                .insertInlineImage(DocsInsertInlineImageRequest(
                    uri: "u", location: DocsLocation(index: 5))),
                #"{"insertInlineImage":{"location":{"index":5},"uri":"u"}}"#
            ),
            (
                .replaceImage(DocsReplaceImageRequest(
                    imageObjectId: "img-1", uri: "u", imageReplaceMethod: .centerCrop)),
                #"{"replaceImage":{"imageObjectId":"img-1","imageReplaceMethod":"CENTER_CROP","uri":"u"}}"#
            ),
            (
                .insertSectionBreak(DocsInsertSectionBreakRequest(
                    sectionType: .continuous, bodyIndex: 3)),
                #"{"insertSectionBreak":{"location":{"index":3},"sectionType":"CONTINUOUS"}}"#
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
