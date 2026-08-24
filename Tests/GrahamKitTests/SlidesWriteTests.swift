import XCTest
@testable import GrahamKit

/// Tests for the Slides write path: the `presentations.batchUpdate` executor,
/// the typed request union, and the high-level `createSlide`, `moveSlide`, and
/// `deleteObject` methods. Every fixture is static JSON; no test touches the
/// network, and the JSON bodies are asserted exactly (the shared encoder sorts
/// keys, so the strings are deterministic).
final class SlidesWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SlidesClient {
        transport.stubTokenEndpoint()
        return SlidesClient(api: TestSupport.makeAPI(transport: transport))
    }

    /// A four-slide presentation, ids only, as the move fields mask returns it.
    private static let fourSlidesJSON =
        #"{"slides":[{"objectId":"s1"},{"objectId":"s2"},{"objectId":"s3"},{"objectId":"s4"}]}"#

    // MARK: - Request-union encoding

    func testCreateSlideRequestEncodesUnderItsOperationKey() throws {
        let request = SlidesBatchUpdateRequest.createSlide(CreateSlideRequest(
            insertionIndex: 0,
            slideLayoutReference: SlideLayoutReference(predefinedLayout: "BLANK")
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createSlide":{"insertionIndex":0,"slideLayoutReference":{"predefinedLayout":"BLANK"}}}"#
        )
    }

    func testCreateSlideRequestOmitsUnsetFields() throws {
        // With nothing set, the operation object is empty: Google then appends
        // a BLANK slide with an assigned id.
        XCTAssertEqual(
            try encode(.createSlide(CreateSlideRequest())),
            #"{"createSlide":{}}"#
        )
    }

    func testLayoutReferenceByLayoutIdEncodesOnlyTheId() throws {
        let request = SlidesBatchUpdateRequest.createSlide(CreateSlideRequest(
            slideLayoutReference: SlideLayoutReference(layoutId: "layout-7")
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createSlide":{"slideLayoutReference":{"layoutId":"layout-7"}}}"#
        )
    }

    func testUpdateSlidesPositionRequestEncodesBothRequiredFields() throws {
        let request = SlidesBatchUpdateRequest.updateSlidesPosition(
            UpdateSlidesPositionRequest(slideObjectIds: ["s1"], insertionIndex: 3)
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updateSlidesPosition":{"insertionIndex":3,"slideObjectIds":["s1"]}}"#
        )
    }

    func testDeleteObjectRequestEncodesTheObjectId() throws {
        XCTAssertEqual(
            try encode(.deleteObject(DeleteObjectRequest(objectId: "slide-2"))),
            #"{"deleteObject":{"objectId":"slide-2"}}"#
        )
    }

    // MARK: - The batch-update executor

    func testBatchUpdatePostsAllRequestsInOrder() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "p-1:batchUpdate",
            json: #"{"presentationId":"p-1","replies":[{"createSlide":{"objectId":"new-slide"}},{}]}"#
        )

        let response = try await client.batchUpdate(presentationId: "p-1", requests: [
            .createSlide(CreateSlideRequest()),
            .deleteObject(DeleteObjectRequest(objectId: "old")),
        ])

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createSlide":{}},{"deleteObject":{"objectId":"old"}}]}"#
        )
        // The response decodes: an id-bearing reply and an empty reply.
        XCTAssertEqual(response.presentationId, "p-1")
        XCTAssertEqual(response.replies?.count, 2)
        XCTAssertEqual(response.replies?.first?.createSlide?.objectId, "new-slide")
    }

    func testBatchUpdateEscapesThePresentationIdInThePath() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        _ = try await client.batchUpdate(
            presentationId: "p 1/x",
            requests: [.deleteObject(DeleteObjectRequest(objectId: "o"))]
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertTrue(
            request.url.absoluteString.hasSuffix("/v1/presentations/p%201%2Fx:batchUpdate"),
            "unexpected URL: \(request.url.absoluteString)"
        )
    }

    func testBatchUpdatePropagatesAGoogleError() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Invalid requests[0]","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        do {
            _ = try await client.batchUpdate(
                presentationId: "p-1",
                requests: [.deleteObject(DeleteObjectRequest(objectId: "missing"))]
            )
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
        }
    }

    // MARK: - createSlide

    func testCreateSlideAppendsABlankSlideByDefault() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"presentationId":"p-1","replies":[{"createSlide":{"objectId":"new-slide"}}]}"#
        )

        let objectId = try await client.createSlide(presentationId: "p-1")

        XCTAssertEqual(objectId, "new-slide")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // No insertionIndex: the slide is appended. The BLANK layout is explicit.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createSlide":{"slideLayoutReference":{"predefinedLayout":"BLANK"}}}]}"#
        )
    }

    func testCreateSlideAtPositionOneUsesInsertionIndexZero() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createSlide":{"objectId":"first"}}]}"#
        )

        let objectId = try await client.createSlide(presentationId: "p-1", at: 1)

        XCTAssertEqual(objectId, "first")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createSlide":{"insertionIndex":0,"#
            + #""slideLayoutReference":{"predefinedLayout":"BLANK"}}}]}"#
        )
    }

    func testCreateSlideNormalizesTheLayoutName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createSlide":{"objectId":"x"}}]}"#
        )

        _ = try await client.createSlide(presentationId: "p-1", layout: " title-and-body ")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createSlide":{"slideLayoutReference":{"predefinedLayout":"TITLE_AND_BODY"}}}]}"#
        )
    }

    func testCreateSlideRejectsANonPositivePositionWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createSlide(presentationId: "p-1", at: 0)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty, "no request should be sent")
    }

    func testCreateSlideRejectsAnEmptyLayoutName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createSlide(presentationId: "p-1", layout: "   ")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty, "no request should be sent")
    }

    func testCreateSlideThrowsWhenTheReplyHasNoObjectId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        do {
            _ = try await client.createSlide(presentationId: "p-1")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testNormalizeLayoutMapsSeparatorsAndCase() {
        XCTAssertEqual(SlidesClient.normalizeLayout("blank"), "BLANK")
        XCTAssertEqual(SlidesClient.normalizeLayout("Title-And-Body"), "TITLE_AND_BODY")
        XCTAssertEqual(SlidesClient.normalizeLayout(" section header "), "SECTION_HEADER")
        XCTAssertEqual(SlidesClient.normalizeLayout("TITLE_ONLY"), "TITLE_ONLY")
    }

    // MARK: - moveSlide

    /// Stubs the ids-only presentation read and an empty batch-update reply.
    private func stubMoveEndpoints(
        _ transport: StubTransport,
        presentationJSON: String = SlidesWriteTests.fourSlidesJSON
    ) {
        transport.stub(urlContains: "presentations/p-1?fields=", json: presentationJSON)
        transport.stub(urlContains: ":batchUpdate", json: #"{"presentationId":"p-1","replies":[{}]}"#)
    }

    func testMoveSlideReadsOnlyTheSlideIds() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        try await client.moveSlide(presentationId: "p-1", slideId: "s1", to: 3)

        let read = try XCTUnwrap(transport.requests(urlContains: "presentations/p-1?").first)
        XCTAssertEqual(read.method, "GET")
        XCTAssertTrue(
            read.url.absoluteString.contains("fields=slides.objectId"),
            "the read should mask to the slide ids: \(read.url.absoluteString)"
        )
    }

    func testMoveSlideForwardAddsOneToTheInsertionIndex() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        // s1 (index 0) to final position 3 (index 2): the pre-move insertion
        // index must count s1 itself, so it is 3, not 2.
        try await client.moveSlide(presentationId: "p-1", slideId: "s1", to: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSlidesPosition":{"insertionIndex":3,"slideObjectIds":["s1"]}}]}"#
        )
    }

    func testMoveSlideForwardFromAMiddleIndex() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        // s2 (index 1) to final position 3 (index 2): a forward move that
        // neither starts at the first slide nor ends at the last one still
        // adds one, so the insertion index is 3.
        try await client.moveSlide(presentationId: "p-1", slideId: "s2", to: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSlidesPosition":{"insertionIndex":3,"slideObjectIds":["s2"]}}]}"#
        )
    }

    func testMoveSlideBackwardUsesTheFinalIndexDirectly() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        // s4 (index 3) to final position 2 (index 1): moving backward, the
        // insertion index equals the final index.
        try await client.moveSlide(presentationId: "p-1", slideId: "s4", to: 2)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSlidesPosition":{"insertionIndex":1,"slideObjectIds":["s4"]}}]}"#
        )
    }

    func testMoveSlideToTheFirstPosition() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        try await client.moveSlide(presentationId: "p-1", slideId: "s3", to: 1)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSlidesPosition":{"insertionIndex":0,"slideObjectIds":["s3"]}}]}"#
        )
    }

    func testMoveSlideToTheLastPosition() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        // s1 (index 0) to final position 4 (index 3), the end of four slides:
        // the pre-move insertion index is 4, one past the last slide.
        try await client.moveSlide(presentationId: "p-1", slideId: "s1", to: 4)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSlidesPosition":{"insertionIndex":4,"slideObjectIds":["s1"]}}]}"#
        )
    }

    func testMoveSlideToItsCurrentPositionSendsNoWrite() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        try await client.moveSlide(presentationId: "p-1", slideId: "s2", to: 2)

        XCTAssertEqual(transport.requests(urlContains: "presentations/p-1?").count, 1)
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty,
                      "a no-op move must not send a batch update")
    }

    func testMoveSlideRejectsAMissingSlideId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        do {
            try await client.moveSlide(presentationId: "p-1", slideId: "nope", to: 1)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testMoveSlideRejectsAnOutOfRangePosition() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubMoveEndpoints(transport)

        do {
            try await client.moveSlide(presentationId: "p-1", slideId: "s2", to: 5)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testMoveSlideRejectsANonPositivePositionBeforeAnyRequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            try await client.moveSlide(presentationId: "p-1", slideId: "s1", to: 0)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty, "no request should be sent")
    }

    // MARK: - deleteObject

    func testDeleteObjectPostsExactlyTheGivenId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        // A delete reply is empty; the response still decodes.
        transport.stub(urlContains: ":batchUpdate", json: #"{"presentationId":"p-1","replies":[{}]}"#)

        try await client.deleteObject(presentationId: "p-1", objectId: "slide-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteObject":{"objectId":"slide-2"}}]}"#
        )
        // Exactly one write; nothing is read, inferred, or expanded.
        XCTAssertEqual(transport.requests(urlContains: "presentations/").count, 1)
    }

    func testDeleteObjectDecodesAnEmptyResponseBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // Must not throw: a response with no replies at all is valid.
        try await client.deleteObject(presentationId: "p-1", objectId: "slide-2")
    }

    // MARK: - Helpers

    /// Encodes one union request with the shared encoder (sorted keys).
    private func encode(_ request: SlidesBatchUpdateRequest) throws -> String {
        let data = try GoogleJSON.encoder.encode(request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The JSON body of a request, as the exact encoded string.
    private static func bodyString(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The path of a URL, with no query, for endpoint assertions.
    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
}
