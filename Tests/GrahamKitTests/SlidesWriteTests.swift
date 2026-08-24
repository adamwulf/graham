import XCTest
@testable import GrahamKit

/// Tests for the Slides write path: the `presentations.batchUpdate` executor,
/// the typed request union, and the high-level slide and text-box write
/// methods. Every fixture is static JSON; no test touches the network, and the
/// JSON bodies are asserted exactly (the shared encoder sorts keys, so the
/// strings are deterministic).
final class SlidesWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SlidesClient {
        transport.stubTokenEndpoint()
        return SlidesClient(api: TestSupport.makeAPI(transport: transport))
    }

    /// A four-slide presentation, ids only, as the move fields mask returns it.
    private static let fourSlidesJSON =
        #"{"slides":[{"objectId":"s1"},{"objectId":"s2"},{"objectId":"s3"},{"objectId":"s4"}]}"#

    /// Geometry fixture with a sheared EMU element, a nested group child, and
    /// a PT element. Computed edits read this fixture before sending one
    /// absolute transform update.
    private static let geometryPresentationJSON = #"""
    {
      "presentationId": "p-geometry",
      "slides": [{
        "objectId": "slide-1",
        "pageElements": [
          {
            "objectId": "top",
            "size": {
              "width": {"magnitude": 100, "unit": "EMU"},
              "height": {"magnitude": 40, "unit": "EMU"}
            },
            "transform": {
              "scaleX": 2, "scaleY": 3,
              "shearX": 0.25, "shearY": 0.5,
              "translateX": 1000, "translateY": 2000,
              "unit": "EMU"
            },
            "shape": {"shapeType": "RECTANGLE"}
          },
          {
            "objectId": "group",
            "elementGroup": {"children": [{
              "objectId": "child",
              "size": {
                "width": {"magnitude": 10, "unit": "EMU"},
                "height": {"magnitude": 20, "unit": "EMU"}
              },
              "transform": {
                "scaleX": 1.5, "scaleY": 0.5,
                "shearX": -0.25, "shearY": 0.75,
                "translateX": 100, "translateY": 200,
                "unit": "EMU"
              },
              "image": {"contentUrl": "https://example.test/child"}
            }]}
          },
          {
            "objectId": "pt-element",
            "size": {
              "width": {"magnitude": 20, "unit": "PT"},
              "height": {"magnitude": 10, "unit": "PT"}
            },
            "transform": {
              "scaleX": 1, "scaleY": 1,
              "shearX": 0, "shearY": 0,
              "translateX": 5, "translateY": 6,
              "unit": "PT"
            },
            "shape": {"shapeType": "RECTANGLE"}
          }
        ]
      }]
    }
    """#

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

    func testCreateShapeRequestEncodesFullGeometry() throws {
        let request = SlidesBatchUpdateRequest.createShape(CreateShapeRequest(
            objectId: "textbox-1",
            elementProperties: PageElementProperties(
                pageObjectId: "slide-1",
                size: ElementSize(
                    width: ElementDimension(magnitude: 300, unit: .pt),
                    height: ElementDimension(magnitude: 50, unit: .pt)
                ),
                transform: ElementTransform(
                    scaleX: 1.5,
                    scaleY: 2,
                    shearX: 0.1,
                    shearY: 0.2,
                    translateX: 25,
                    translateY: 75,
                    unit: .pt
                )
            ),
            shapeType: "TEXT_BOX"
        ))

        XCTAssertEqual(
            try encode(request),
            #"{"createShape":{"elementProperties":{"pageObjectId":"slide-1","size":{"height":{"magnitude":50,"unit":"PT"},"width":{"magnitude":300,"unit":"PT"}},"transform":{"scaleX":1.5,"scaleY":2,"shearX":0.1,"shearY":0.2,"translateX":25,"translateY":75,"unit":"PT"}},"objectId":"textbox-1","shapeType":"TEXT_BOX"}}"#
        )
    }

    func testCreateShapeRequestWithoutObjectIdOmitsTheKey() throws {
        let request = SlidesBatchUpdateRequest.createShape(CreateShapeRequest(
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            shapeType: "TEXT_BOX"
        ))

        XCTAssertEqual(
            try encode(request),
            #"{"createShape":{"elementProperties":{"pageObjectId":"slide-1"},"shapeType":"TEXT_BOX"}}"#
        )
    }

    func testInsertTextRequestEncodesAllRequiredFields() throws {
        XCTAssertEqual(
            try encode(.insertText(InsertTextRequest(
                objectId: "textbox-1", text: "Hello", insertionIndex: 3))),
            #"{"insertText":{"insertionIndex":3,"objectId":"textbox-1","text":"Hello"}}"#
        )
    }

    func testUpdatePageElementTransformRequestEncodesAbsoluteAndOmitsNilShears() throws {
        let request = SlidesBatchUpdateRequest.updatePageElementTransform(
            UpdatePageElementTransformRequest(
                objectId: "element-1",
                transform: ElementTransform(
                    scaleX: 2,
                    scaleY: 3,
                    translateX: 4,
                    translateY: 5,
                    unit: .pt
                ),
                applyMode: .absolute
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updatePageElementTransform":{"applyMode":"ABSOLUTE","objectId":"element-1","transform":{"scaleX":2,"scaleY":3,"translateX":4,"translateY":5,"unit":"PT"}}}"#
        )
    }

    func testUpdatePageElementTransformRequestEncodesRelative() throws {
        let request = SlidesBatchUpdateRequest.updatePageElementTransform(
            UpdatePageElementTransformRequest(
                objectId: "element-2",
                transform: ElementTransform(
                    scaleX: 1,
                    scaleY: 1,
                    shearX: 6,
                    shearY: 7,
                    translateX: 8,
                    translateY: 9,
                    unit: .emu
                ),
                applyMode: .relative
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updatePageElementTransform":{"applyMode":"RELATIVE","objectId":"element-2","transform":{"scaleX":1,"scaleY":1,"shearX":6,"shearY":7,"translateX":8,"translateY":9,"unit":"EMU"}}}"#
        )
    }

    func testUpdatePageElementsZOrderRequestEncodesExactly() throws {
        let request = SlidesBatchUpdateRequest.updatePageElementsZOrder(
            UpdatePageElementsZOrderRequest(
                pageElementObjectIds: ["a", "b"],
                operation: .sendToBack
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updatePageElementsZOrder":{"operation":"SEND_TO_BACK","pageElementObjectIds":["a","b"]}}"#
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

    // MARK: - createTextBox and insertText

    func testCreateTextBoxPostsCreateThenInsertAtomicallyAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createShape":{"objectId":"reply-id"}},{}]}"#
        )

        let objectId = try await client.createTextBox(
            presentationId: "p-1",
            slideId: "slide-1",
            text: "Hello",
            objectId: "textbox-1",
            x: 25,
            y: 75,
            width: 300,
            height: 50
        )

        XCTAssertEqual(objectId, "reply-id")
        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createShape":{"elementProperties":{"pageObjectId":"slide-1","size":{"height":{"magnitude":50,"unit":"PT"},"width":{"magnitude":300,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":25,"translateY":75,"unit":"PT"}},"objectId":"textbox-1","shapeType":"TEXT_BOX"}},{"insertText":{"insertionIndex":0,"objectId":"textbox-1","text":"Hello"}}]}"#
        )
    }

    func testCreateTextBoxFallsBackToTheSentIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createTextBox(
            presentationId: "p-1",
            slideId: "slide-1",
            text: "",
            objectId: "sent-id"
        )

        XCTAssertEqual(objectId, "sent-id")
    }

    func testCreateTextBoxWithEmptyTextSendsOnlyCreateShape() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.createTextBox(
            presentationId: "p-1",
            slideId: "slide-1",
            text: "",
            objectId: "textbox-1"
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createShape":{"elementProperties":{"pageObjectId":"slide-1","size":{"height":{"magnitude":50,"unit":"PT"},"width":{"magnitude":300,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":50,"translateY":50,"unit":"PT"}},"objectId":"textbox-1","shapeType":"TEXT_BOX"}}]}"#
        )
    }

    func testCreateTextBoxGeneratesAValidObjectId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createTextBox(
            presentationId: "p-1", slideId: "slide-1", text: "Hello")

        XCTAssertNotNil(
            objectId.range(
                of: #"^[a-zA-Z0-9_][a-zA-Z0-9_:-]{4,49}$"#,
                options: .regularExpression
            )
        )
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        let body = Self.bodyString(request)
        XCTAssertEqual(body.components(separatedBy: objectId).count - 1, 2)
    }

    func testCreateTextBoxEscapesThePresentationIdInThePath() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        _ = try await client.createTextBox(
            presentationId: "p 1/x",
            slideId: "slide-1",
            text: "",
            objectId: "textbox-1"
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertTrue(
            request.url.absoluteString.hasSuffix("/v1/presentations/p%201%2Fx:batchUpdate"),
            "unexpected URL: \(request.url.absoluteString)"
        )
    }

    func testInsertTextPostsTheRequestedIndex() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.insertText(
            presentationId: "p-1",
            objectId: "textbox-1",
            text: " world",
            insertionIndex: 5
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"insertText":{"insertionIndex":5,"objectId":"textbox-1","text":" world"}}]}"#
        )
    }

    func testInsertTextWithEmptyTextSendsNoRequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        try await client.insertText(
            presentationId: "p-1", objectId: "textbox-1", text: "")

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testCreateTextBoxPropagatesAGoogleError() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Invalid requests[0]","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        do {
            _ = try await client.createTextBox(
                presentationId: "p-1",
                slideId: "missing",
                text: "",
                objectId: "textbox-1"
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

    // MARK: - Element-creation request encoding

    func testCreateImageRequestEncodesFullGeometryAndUrl() throws {
        let request = SlidesBatchUpdateRequest.createImage(CreateImageRequest(
            objectId: "image-1",
            elementProperties: PageElementProperties(
                pageObjectId: "slide-1",
                size: ElementSize(
                    width: ElementDimension(magnitude: 300, unit: .pt),
                    height: ElementDimension(magnitude: 50, unit: .pt)
                ),
                transform: ElementTransform(translateX: 25, translateY: 75, unit: .pt)
            ),
            url: "https://example.com/pic.png"
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createImage":{"elementProperties":{"pageObjectId":"slide-1","size":{"height":{"magnitude":50,"unit":"PT"},"width":{"magnitude":300,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":25,"translateY":75,"unit":"PT"}},"objectId":"image-1","url":"https:\/\/example.com\/pic.png"}}"#
        )
    }

    func testCreateImageRequestWithoutObjectIdOmitsTheKey() throws {
        let request = SlidesBatchUpdateRequest.createImage(CreateImageRequest(
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            url: "https://example.com/pic.png"
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createImage":{"elementProperties":{"pageObjectId":"slide-1"},"url":"https:\/\/example.com\/pic.png"}}"#
        )
    }

    func testCreateVideoRequestEncodesSourceAndId() throws {
        let request = SlidesBatchUpdateRequest.createVideo(CreateVideoRequest(
            objectId: "video-1",
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            source: .youtube,
            id: "abc123"
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createVideo":{"elementProperties":{"pageObjectId":"slide-1"},"id":"abc123","objectId":"video-1","source":"YOUTUBE"}}"#
        )
    }

    func testCreateVideoRequestEncodesTheDriveSourceAndOmitsObjectId() throws {
        let request = SlidesBatchUpdateRequest.createVideo(CreateVideoRequest(
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            source: .drive,
            id: "drive-file-id"
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createVideo":{"elementProperties":{"pageObjectId":"slide-1"},"id":"drive-file-id","source":"DRIVE"}}"#
        )
    }

    func testCreateLineRequestEncodesCategoryAndNeverLineCategory() throws {
        let request = SlidesBatchUpdateRequest.createLine(CreateLineRequest(
            objectId: "line-1",
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            category: .curved
        ))
        let json = try encode(request)
        XCTAssertEqual(
            json,
            #"{"createLine":{"category":"CURVED","elementProperties":{"pageObjectId":"slide-1"},"objectId":"line-1"}}"#
        )
        // The live field is `category`; the deprecated `lineCategory` alias must
        // never be sent.
        XCTAssertTrue(json.contains(#""category":"CURVED""#))
        XCTAssertFalse(json.contains("lineCategory"))
    }

    func testCreateTableRequestEncodesRowsAndColumns() throws {
        let request = SlidesBatchUpdateRequest.createTable(CreateTableRequest(
            objectId: "table-1",
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            rows: 3,
            columns: 4
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createTable":{"columns":4,"elementProperties":{"pageObjectId":"slide-1"},"objectId":"table-1","rows":3}}"#
        )
    }

    func testCreateSheetsChartRequestOmitsLinkingModeWhenNil() throws {
        let request = SlidesBatchUpdateRequest.createSheetsChart(CreateSheetsChartRequest(
            objectId: "chart-1",
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            spreadsheetId: "sheet-1",
            chartId: 42,
            linkingMode: nil
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createSheetsChart":{"chartId":42,"elementProperties":{"pageObjectId":"slide-1"},"objectId":"chart-1","spreadsheetId":"sheet-1"}}"#
        )
    }

    func testCreateSheetsChartRequestIncludesLinkingModeWhenLinked() throws {
        let request = SlidesBatchUpdateRequest.createSheetsChart(CreateSheetsChartRequest(
            objectId: "chart-1",
            elementProperties: PageElementProperties(pageObjectId: "slide-1"),
            spreadsheetId: "sheet-1",
            chartId: 42,
            linkingMode: .linked
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"createSheetsChart":{"chartId":42,"elementProperties":{"pageObjectId":"slide-1"},"linkingMode":"LINKED","objectId":"chart-1","spreadsheetId":"sheet-1"}}"#
        )
    }

    func testGroupObjectsRequestEncodesChildrenAndGroupId() throws {
        let request = SlidesBatchUpdateRequest.groupObjects(GroupObjectsRequest(
            groupObjectId: "group-1",
            childrenObjectIds: ["a", "b"]
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"groupObjects":{"childrenObjectIds":["a","b"],"groupObjectId":"group-1"}}"#
        )
    }

    func testGroupObjectsRequestWithoutGroupIdOmitsTheKey() throws {
        let request = SlidesBatchUpdateRequest.groupObjects(GroupObjectsRequest(
            childrenObjectIds: ["a", "b"]
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"groupObjects":{"childrenObjectIds":["a","b"]}}"#
        )
    }

    func testUngroupObjectsRequestEncodesObjectIds() throws {
        let request = SlidesBatchUpdateRequest.ungroupObjects(UngroupObjectsRequest(
            objectIds: ["g1", "g2"]
        ))
        XCTAssertEqual(
            try encode(request),
            #"{"ungroupObjects":{"objectIds":["g1","g2"]}}"#
        )
    }

    // MARK: - Geometry helper behavior (exercised through createImage)

    func testCreateImageWithNoGeometryOmitsSizeAndTransform() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createImage":{"objectId":"img"}}]}"#
        )

        _ = try await client.createImage(
            presentationId: "p-1", slideId: "s1", url: "u", objectId: "img")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // With no geometry arguments the element carries only its page; Google
        // then chooses the default placement and the image keeps its native size.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createImage":{"elementProperties":{"pageObjectId":"s1"},"objectId":"img","url":"u"}}]}"#
        )
        let body = Self.bodyString(request)
        XCTAssertFalse(body.contains("\"size\""))
        XCTAssertFalse(body.contains("\"transform\""))
    }

    func testCreateImageWithPositionOnlySendsTransformNotSize() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createImage":{"objectId":"img"}}]}"#
        )

        _ = try await client.createImage(
            presentationId: "p-1", slideId: "s1", url: "u", objectId: "img",
            x: 25, y: 75)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createImage":{"elementProperties":{"pageObjectId":"s1","transform":{"scaleX":1,"scaleY":1,"translateX":25,"translateY":75,"unit":"PT"}},"objectId":"img","url":"u"}}]}"#
        )
    }

    func testCreateImageWithXOnlyTranslatesYToZero() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createImage":{"objectId":"img"}}]}"#
        )

        // Only x is given: the transform still appears, with y defaulted to 0.
        _ = try await client.createImage(
            presentationId: "p-1", slideId: "s1", url: "u", objectId: "img", x: 25)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createImage":{"elementProperties":{"pageObjectId":"s1","transform":{"scaleX":1,"scaleY":1,"translateX":25,"translateY":0,"unit":"PT"}},"objectId":"img","url":"u"}}]}"#
        )
    }

    func testCreateImageRejectsWidthWithoutHeight() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createImage(
                presentationId: "p-1", slideId: "s1", url: "u", width: 300)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateImageRejectsHeightWithoutWidth() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createImage(
                presentationId: "p-1", slideId: "s1", url: "u", height: 50)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateImageRejectsAZeroWidth() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createImage(
                presentationId: "p-1", slideId: "s1", url: "u", width: 0, height: 50)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateImageRejectsANegativeHeight() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createImage(
                presentationId: "p-1", slideId: "s1", url: "u", width: 50, height: -1)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - createImage

    func testCreateImagePostsFullGeometryAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createImage":{"objectId":"reply-image"}}]}"#
        )

        let objectId = try await client.createImage(
            presentationId: "p-1",
            slideId: "s1",
            url: "https://example.com/pic.png",
            objectId: "image-1",
            x: 25, y: 75, width: 300, height: 50
        )

        XCTAssertEqual(objectId, "reply-image")
        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createImage":{"elementProperties":{"pageObjectId":"s1","size":{"height":{"magnitude":50,"unit":"PT"},"width":{"magnitude":300,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":25,"translateY":75,"unit":"PT"}},"objectId":"image-1","url":"https:\/\/example.com\/pic.png"}}]}"#
        )
    }

    func testCreateImageFallsBackToTheSentIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createImage(
            presentationId: "p-1", slideId: "s1", url: "u", objectId: "sent-image")

        XCTAssertEqual(objectId, "sent-image")
    }

    func testCreateImageGeneratesAValidObjectId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createImage(
            presentationId: "p-1", slideId: "s1", url: "u")

        XCTAssertNotNil(
            objectId.range(
                of: #"^[a-zA-Z0-9_][a-zA-Z0-9_:-]{4,49}$"#,
                options: .regularExpression
            )
        )
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        let body = Self.bodyString(request)
        XCTAssertEqual(body.components(separatedBy: objectId).count - 1, 1)
    }

    func testCreateImageRejectsAnEmptyUrl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createImage(presentationId: "p-1", slideId: "s1", url: "")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateImagePropagatesAGoogleError() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Invalid requests[0]","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        do {
            _ = try await client.createImage(
                presentationId: "p-1", slideId: "s1", url: "u", objectId: "image-1")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
        }
    }

    // MARK: - createVideo

    func testCreateVideoPostsSourceAndIdAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createVideo":{"objectId":"reply-video"}}]}"#
        )

        let objectId = try await client.createVideo(
            presentationId: "p-1",
            slideId: "s1",
            source: .youtube,
            videoId: "abc123",
            objectId: "video-1",
            x: 10, y: 20, width: 200, height: 150
        )

        XCTAssertEqual(objectId, "reply-video")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createVideo":{"elementProperties":{"pageObjectId":"s1","size":{"height":{"magnitude":150,"unit":"PT"},"width":{"magnitude":200,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":10,"translateY":20,"unit":"PT"}},"id":"abc123","objectId":"video-1","source":"YOUTUBE"}}]}"#
        )
    }

    func testCreateVideoDefaultsToTheYouTubeSource() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createVideo":{"objectId":"v"}}]}"#
        )

        // Source is omitted, so the default (.youtube) must be sent.
        _ = try await client.createVideo(
            presentationId: "p-1", slideId: "s1", videoId: "abc", objectId: "video-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createVideo":{"elementProperties":{"pageObjectId":"s1"},"id":"abc","objectId":"video-1","source":"YOUTUBE"}}]}"#
        )
    }

    func testCreateVideoSendsTheDriveSource() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createVideo":{"objectId":"v"}}]}"#
        )

        _ = try await client.createVideo(
            presentationId: "p-1", slideId: "s1", source: .drive,
            videoId: "file-1", objectId: "video-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createVideo":{"elementProperties":{"pageObjectId":"s1"},"id":"file-1","objectId":"video-1","source":"DRIVE"}}]}"#
        )
    }

    func testCreateVideoFallsBackToTheSentIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createVideo(
            presentationId: "p-1", slideId: "s1", videoId: "abc", objectId: "sent-video")

        XCTAssertEqual(objectId, "sent-video")
    }

    func testCreateVideoRejectsAnEmptyVideoId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createVideo(
                presentationId: "p-1", slideId: "s1", videoId: "")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - createLine

    func testCreateLinePostsCategoryAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createLine":{"objectId":"reply-line"}}]}"#
        )

        let objectId = try await client.createLine(
            presentationId: "p-1",
            slideId: "s1",
            category: .bent,
            objectId: "line-1",
            x: 5, y: 6, width: 100, height: 2
        )

        XCTAssertEqual(objectId, "reply-line")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createLine":{"category":"BENT","elementProperties":{"pageObjectId":"s1","size":{"height":{"magnitude":2,"unit":"PT"},"width":{"magnitude":100,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":5,"translateY":6,"unit":"PT"}},"objectId":"line-1"}}]}"#
        )
    }

    func testCreateLineDefaultsToTheStraightCategory() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createLine":{"objectId":"l"}}]}"#
        )

        _ = try await client.createLine(
            presentationId: "p-1", slideId: "s1", objectId: "line-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createLine":{"category":"STRAIGHT","elementProperties":{"pageObjectId":"s1"},"objectId":"line-1"}}]}"#
        )
    }

    func testCreateLineFallsBackToTheSentIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createLine(
            presentationId: "p-1", slideId: "s1", objectId: "sent-line")

        XCTAssertEqual(objectId, "sent-line")
    }

    // MARK: - createTable

    func testCreateTablePostsRowsAndColumnsAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createTable":{"objectId":"reply-table"}}]}"#
        )

        let objectId = try await client.createTable(
            presentationId: "p-1",
            slideId: "s1",
            rows: 3,
            columns: 4,
            objectId: "table-1",
            x: 10, y: 20, width: 400, height: 200
        )

        XCTAssertEqual(objectId, "reply-table")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createTable":{"columns":4,"elementProperties":{"pageObjectId":"s1","size":{"height":{"magnitude":200,"unit":"PT"},"width":{"magnitude":400,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":10,"translateY":20,"unit":"PT"}},"objectId":"table-1","rows":3}}]}"#
        )
    }

    func testCreateTableFallsBackToTheSentIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createTable(
            presentationId: "p-1", slideId: "s1", rows: 2, columns: 2, objectId: "sent-table")

        XCTAssertEqual(objectId, "sent-table")
    }

    func testCreateTableRejectsNonPositiveRows() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createTable(
                presentationId: "p-1", slideId: "s1", rows: 0, columns: 4)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCreateTableRejectsNonPositiveColumns() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createTable(
                presentationId: "p-1", slideId: "s1", rows: 3, columns: 0)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - createSheetsChart

    func testCreateSheetsChartUnlinkedByDefaultPostsAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createSheetsChart":{"objectId":"reply-chart"}}]}"#
        )

        let objectId = try await client.createSheetsChart(
            presentationId: "p-1",
            slideId: "s1",
            spreadsheetId: "sheet-1",
            chartId: 42,
            linked: false,
            objectId: "chart-1",
            x: 10, y: 20, width: 400, height: 300
        )

        XCTAssertEqual(objectId, "reply-chart")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        // linked:false omits the linkingMode key; the API default is NOT_LINKED_IMAGE.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createSheetsChart":{"chartId":42,"elementProperties":{"pageObjectId":"s1","size":{"height":{"magnitude":300,"unit":"PT"},"width":{"magnitude":400,"unit":"PT"}},"transform":{"scaleX":1,"scaleY":1,"translateX":10,"translateY":20,"unit":"PT"}},"objectId":"chart-1","spreadsheetId":"sheet-1"}}]}"#
        )
    }

    func testCreateSheetsChartLinkedIncludesTheLinkingMode() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"createSheetsChart":{"objectId":"c"}}]}"#
        )

        _ = try await client.createSheetsChart(
            presentationId: "p-1", slideId: "s1", spreadsheetId: "sheet-1",
            chartId: 7, linked: true, objectId: "chart-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"createSheetsChart":{"chartId":7,"elementProperties":{"pageObjectId":"s1"},"linkingMode":"LINKED","objectId":"chart-1","spreadsheetId":"sheet-1"}}]}"#
        )
    }

    func testCreateSheetsChartFallsBackToTheSentIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.createSheetsChart(
            presentationId: "p-1", slideId: "s1", spreadsheetId: "sheet-1",
            chartId: 1, objectId: "sent-chart")

        XCTAssertEqual(objectId, "sent-chart")
    }

    func testCreateSheetsChartRejectsAnEmptySpreadsheetId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.createSheetsChart(
                presentationId: "p-1", slideId: "s1", spreadsheetId: "", chartId: 1)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - groupElements

    func testGroupElementsPostsChildrenAndReturnsReplyId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"groupObjects":{"objectId":"reply-group"}}]}"#
        )

        let objectId = try await client.groupElements(
            presentationId: "p-1", childIds: ["a", "b", "c"], groupObjectId: "group-1")

        XCTAssertEqual(objectId, "reply-group")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"groupObjects":{"childrenObjectIds":["a","b","c"],"groupObjectId":"group-1"}}]}"#
        )
    }

    func testGroupElementsFallsBackToTheSentGroupIdForAnEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.groupElements(
            presentationId: "p-1", childIds: ["a", "b"], groupObjectId: "sent-group")

        XCTAssertEqual(objectId, "sent-group")
    }

    func testGroupElementsGeneratesAValidGroupId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        let objectId = try await client.groupElements(
            presentationId: "p-1", childIds: ["a", "b"])

        XCTAssertNotNil(
            objectId.range(
                of: #"^[a-zA-Z0-9_][a-zA-Z0-9_:-]{4,49}$"#,
                options: .regularExpression
            )
        )
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        let body = Self.bodyString(request)
        XCTAssertEqual(body.components(separatedBy: objectId).count - 1, 1)
    }

    func testGroupElementsRejectsFewerThanTwoChildren() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            _ = try await client.groupElements(
                presentationId: "p-1", childIds: ["only-one"])
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - ungroupElements

    func testUngroupElementsPostsTheObjectIds() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.ungroupElements(presentationId: "p-1", objectIds: ["g1", "g2"])

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"ungroupObjects":{"objectIds":["g1","g2"]}}]}"#
        )
    }

    func testUngroupElementsToleratesAnEmptyResponseBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // ungroupObjects returns an empty reply; this must not throw.
        try await client.ungroupElements(presentationId: "p-1", objectIds: ["g1"])
    }

    func testUngroupElementsRejectsAnEmptyList() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            try await client.ungroupElements(presentationId: "p-1", objectIds: [])
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Element geometry and z-order

    private func stubGeometryEndpoints(
        _ transport: StubTransport,
        writeJSON: String = #"{"presentationId":"p-geometry","replies":[{}]}"#,
        writeStatus: Int = 200
    ) {
        transport.stub(
            urlContains: "presentations/p-geometry?fields=",
            json: Self.geometryPresentationJSON
        )
        transport.stub(urlContains: ":batchUpdate", json: writeJSON, status: writeStatus)
    }

    func testMoveElementToConvertsPointsToEmuAndPreservesTheLinearMatrix() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.moveElement(
            presentationId: "p-geometry", objectId: "top", toX: 2, toY: -3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updatePageElementTransform":{"applyMode":"ABSOLUTE","objectId":"top","transform":{"scaleX":2,"scaleY":3,"shearX":0.25,"shearY":0.5,"translateX":25400,"translateY":-38100,"unit":"EMU"}}}]}"#
        )
        let read = try XCTUnwrap(transport.requests(urlContains: "presentations/p-geometry?").first)
        XCTAssertEqual(read.method, "GET")
        XCTAssertTrue(read.url.absoluteString.contains("fields=slides.pageElements"))
        XCTAssertEqual(Self.path(read.url), "/v1/presentations/p-geometry")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-geometry:batchUpdate")
    }

    func testMoveElementToDoesNotConvertPointsForAPtElement() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.moveElement(
            presentationId: "p-geometry", objectId: "pt-element", toX: -2.5, toY: 7)

        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.applyMode, .absolute)
        XCTAssertEqual(sent.transform.translateX, -2.5)
        XCTAssertEqual(sent.transform.translateY, 7)
        XCTAssertEqual(sent.transform.unit, .pt)
    }

    func testMoveElementByAddsConvertedDeltas() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.moveElement(
            presentationId: "p-geometry", objectId: "top", byX: 2, byY: -1)

        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.transform.translateX, 26_400)
        XCTAssertEqual(sent.transform.translateY, -10_700)
        XCTAssertEqual(sent.transform.unit, .emu)
    }

    func testMoveElementFindsAChildInsideAGroup() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.moveElement(
            presentationId: "p-geometry", objectId: "child", byX: 1, byY: 0)

        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.objectId, "child")
        XCTAssertEqual(sent.transform.scaleX, 1.5)
        XCTAssertEqual(sent.transform.scaleY, 0.5)
        XCTAssertEqual(sent.transform.shearX, -0.25)
        XCTAssertEqual(sent.transform.shearY, 0.75)
        XCTAssertEqual(sent.transform.translateX, 12_800)
        XCTAssertEqual(sent.transform.translateY, 200)
    }

    func testScaleElementPrecomputesAbsoluteBTimesTAboutTheCenter() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.scaleElement(
            presentationId: "p-geometry", objectId: "top", factorX: 2, factorY: 0.5)

        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.applyMode, .absolute)
        XCTAssertEqual(sent.transform.scaleX, 4, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.scaleY, 1.5, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(sent.transform.shearX), 0.5, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(sent.transform.shearY), 0.25, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.translateX, 895, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.translateY, 2042.5, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.unit, .emu)
    }

    func testScaleElementRejectsNonPositiveFactorsBeforeReading() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            try await client.scaleElement(
                presentationId: "p-geometry", objectId: "top", factorX: 1, factorY: 0)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRotateElementByPrecomputesClockwiseRotationAboutTheCenter() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.rotateElement(
            presentationId: "p-geometry", objectId: "top", byDegrees: 90)

        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.transform.scaleX, -0.5, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.scaleY, 0.25, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(sent.transform.shearX), -3, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(sent.transform.shearY), 2, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.translateX, 1190, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.translateY, 1980, accuracy: 0.000_000_1)
    }

    func testRotateElementToUsesTheDeltaFromTheCurrentRotation() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(transport)

        try await client.rotateElement(
            presentationId: "p-geometry", objectId: "top", toDegrees: 90)

        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.transform.scaleX, 0, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.scaleY, 0.970_142_500_1, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(sent.transform.shearX), -2.849_793_594, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(sent.transform.shearY), 2.061_552_813, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.translateX, 1161.995_871_9, accuracy: 0.000_000_1)
        XCTAssertEqual(sent.transform.translateY, 1962.519_509_3, accuracy: 0.000_000_1)
    }

    func testUnknownElementRejectsAfterReadAndSendsNoWrite() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "presentations/p-geometry?fields=",
            json: Self.geometryPresentationJSON
        )

        do {
            try await client.moveElement(
                presentationId: "p-geometry", objectId: "missing", toX: 1, toY: 2)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument(let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(message.contains("missing"))
        }
        XCTAssertEqual(transport.requests(urlContains: "presentations/p-geometry?").count, 1)
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testRawTransformSendsVerbatimWithoutARead() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)
        let transform = ElementTransform(
            scaleX: 2,
            scaleY: 3,
            shearX: nil,
            shearY: -4,
            translateX: -5,
            translateY: 6,
            unit: .pt
        )

        try await client.transformElement(
            presentationId: "p-geometry",
            objectId: "top",
            transform: transform,
            mode: .relative
        )

        XCTAssertEqual(transport.requests(urlContains: "presentations/p-geometry").count, 1)
        let sent = try sentTransform(transport)
        XCTAssertEqual(sent.objectId, "top")
        XCTAssertEqual(sent.transform, transform)
        XCTAssertEqual(sent.applyMode, .relative)
    }

    func testReorderElementsSendsExactBodyAndKeepsIdOrder() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.reorderElements(
            presentationId: "p-geometry",
            objectIds: ["a", "b"],
            operation: .bringForward
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updatePageElementsZOrder":{"operation":"BRING_FORWARD","pageElementObjectIds":["a","b"]}}]}"#
        )
    }

    func testReorderElementsRejectsAnEmptyListWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        do {
            try await client.reorderElements(
                presentationId: "p-geometry", objectIds: [], operation: .bringToFront)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testComputedTransformPropagatesAGoogleErrorEnvelope() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubGeometryEndpoints(
            transport,
            writeJSON: #"{"error":{"code":400,"message":"Bad transform","status":"INVALID_ARGUMENT"}}"#,
            writeStatus: 400
        )

        do {
            try await client.moveElement(
                presentationId: "p-geometry", objectId: "top", toX: 1, toY: 2)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "Bad transform")
        }
    }

    // MARK: - OpaqueColor parsing

    func testOpaqueColorParsesShortHexExpandingEachNibble() throws {
        // #F00 expands to #FF0000: red 255/255 = 1, green and blue 0.
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("#F00")),
            #"{"rgbColor":{"blue":0,"green":0,"red":1}}"#
        )
    }

    func testOpaqueColorParsesSixDigitHexCaseInsensitively() throws {
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("#ff0000")),
            #"{"rgbColor":{"blue":0,"green":0,"red":1}}"#
        )
    }

    func testOpaqueColorParsesHexWithoutALeadingHash() throws {
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("ff0000")),
            #"{"rgbColor":{"blue":0,"green":0,"red":1}}"#
        )
        // The short form works without a hash too.
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("00f")),
            #"{"rgbColor":{"blue":1,"green":0,"red":0}}"#
        )
    }

    func testOpaqueColorParsesThemeNamesInAnyCase() throws {
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("accent1")),
            #"{"themeColor":"ACCENT1"}"#
        )
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("DARK1")),
            #"{"themeColor":"DARK1"}"#
        )
        // A multi-word theme name matches case-insensitively as well.
        XCTAssertEqual(
            try encodeJSON(OpaqueColor.parse("followed_hyperlink")),
            #"{"themeColor":"FOLLOWED_HYPERLINK"}"#
        )
    }

    func testOpaqueColorParseRejectsABadHexLength() {
        // Four hex digits is neither the short (3) nor the long (6) form.
        assertColorParseThrows("#FF00")
    }

    func testOpaqueColorParseRejectsBadHexCharacters() {
        assertColorParseThrows("#ZZZ")
        assertColorParseThrows("#GG0011")
    }

    func testOpaqueColorParseRejectsAnUnknownThemeName() {
        assertColorParseThrows("mauve")
    }

    private func assertColorParseThrows(
        _ input: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try OpaqueColor.parse(input)
            XCTFail("Expected a parse failure for \"\(input)\"", file: file, line: line)
        } catch {
            guard case GrahamError.invalidArgument(let message) = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
            // The message names the offending input.
            XCTAssertTrue(message.contains(input), "message should name the input: \(message)",
                          file: file, line: line)
        }
    }

    // MARK: - Element-style request encoding

    /// The exact wire form of a shape style request that sets a fill, an
    /// outline, a shadow, and content alignment. Shared by the model-level
    /// encode test and the client body test so the two never drift.
    private static let shapeStyleUnionJSON =
        #"{"updateShapeProperties":{"fields":"shapeBackgroundFill.solidFill.color,shapeBackgroundFill.solidFill.alpha,outline.outlineFill.solidFill.color,outline.weight,shadow.color,shadow.blurRadius,shadow.transform,contentAlignment","objectId":"shape-1","shapeProperties":{"contentAlignment":"MIDDLE","outline":{"outlineFill":{"solidFill":{"color":{"themeColor":"ACCENT1"}}},"weight":{"magnitude":2,"unit":"PT"}},"shadow":{"blurRadius":{"magnitude":3,"unit":"PT"},"color":{"rgbColor":{"blue":0,"green":0,"red":0}},"transform":{"scaleX":1,"scaleY":1,"shearX":0,"shearY":0,"translateX":4,"translateY":5,"unit":"PT"}},"shapeBackgroundFill":{"solidFill":{"alpha":0.5,"color":{"rgbColor":{"blue":0,"green":0,"red":1}}}}}}}"#

    func testUpdateShapePropertiesRequestEncodesFillOutlineShadowAndAlignment() throws {
        let request = SlidesBatchUpdateRequest.updateShapeProperties(
            UpdateShapePropertiesRequest(
                objectId: "shape-1",
                shapeProperties: ShapeStyle(
                    shapeBackgroundFill: ShapeBackgroundFill(
                        solidFill: SolidFill(
                            color: OpaqueColor(red: 1, green: 0, blue: 0),
                            alpha: 0.5
                        )
                    ),
                    outline: Outline(
                        outlineFill: OutlineFill(
                            solidFill: SolidFill(color: OpaqueColor(theme: .accent1))
                        ),
                        weight: ElementDimension(magnitude: 2, unit: .pt)
                    ),
                    shadow: Shadow(
                        color: OpaqueColor(red: 0, green: 0, blue: 0),
                        blurRadius: ElementDimension(magnitude: 3, unit: .pt),
                        transform: ElementTransform(
                            scaleX: 1, scaleY: 1, shearX: 0, shearY: 0,
                            translateX: 4, translateY: 5, unit: .pt
                        )
                    ),
                    contentAlignment: .middle
                ),
                fields: "shapeBackgroundFill.solidFill.color,shapeBackgroundFill.solidFill.alpha,"
                    + "outline.outlineFill.solidFill.color,outline.weight,"
                    + "shadow.color,shadow.blurRadius,shadow.transform,contentAlignment"
            )
        )
        XCTAssertEqual(try encode(request), Self.shapeStyleUnionJSON)
    }

    func testUpdateShapePropertiesRequestNoFillEncodesNotRendered() throws {
        let request = SlidesBatchUpdateRequest.updateShapeProperties(
            UpdateShapePropertiesRequest(
                objectId: "shape-1",
                shapeProperties: ShapeStyle(
                    shapeBackgroundFill: ShapeBackgroundFill(propertyState: .notRendered)
                ),
                fields: "shapeBackgroundFill.propertyState"
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updateShapeProperties":{"fields":"shapeBackgroundFill.propertyState","objectId":"shape-1","shapeProperties":{"shapeBackgroundFill":{"propertyState":"NOT_RENDERED"}}}}"#
        )
    }

    func testUpdateImagePropertiesRequestUsesTheImagePropertiesKey() throws {
        let request = SlidesBatchUpdateRequest.updateImageProperties(
            UpdateImagePropertiesRequest(
                objectId: "image-1",
                imageProperties: ImageStyle(outline: Outline(propertyState: .notRendered)),
                fields: "outline.propertyState"
            )
        )
        let json = try encode(request)
        XCTAssertEqual(
            json,
            #"{"updateImageProperties":{"fields":"outline.propertyState","imageProperties":{"outline":{"propertyState":"NOT_RENDERED"}},"objectId":"image-1"}}"#
        )
        XCTAssertTrue(json.contains(#""imageProperties""#))
    }

    func testUpdateLinePropertiesRequestUsesTheLinePropertiesKey() throws {
        let request = SlidesBatchUpdateRequest.updateLineProperties(
            UpdateLinePropertiesRequest(
                objectId: "line-1",
                lineProperties: LineStyle(dashStyle: .solid),
                fields: "dashStyle"
            )
        )
        let json = try encode(request)
        XCTAssertEqual(
            json,
            #"{"updateLineProperties":{"fields":"dashStyle","lineProperties":{"dashStyle":"SOLID"},"objectId":"line-1"}}"#
        )
        XCTAssertTrue(json.contains(#""lineProperties""#))
    }

    func testUpdateVideoPropertiesRequestUsesTheVideoPropertiesKey() throws {
        let request = SlidesBatchUpdateRequest.updateVideoProperties(
            UpdateVideoPropertiesRequest(
                objectId: "video-1",
                videoProperties: VideoStyle(mute: true),
                fields: "mute"
            )
        )
        let json = try encode(request)
        XCTAssertEqual(
            json,
            #"{"updateVideoProperties":{"fields":"mute","objectId":"video-1","videoProperties":{"mute":true}}}"#
        )
        XCTAssertTrue(json.contains(#""videoProperties""#))
    }

    func testRefreshSheetsChartRequestEncodesTheObjectId() throws {
        XCTAssertEqual(
            try encode(.refreshSheetsChart(RefreshSheetsChartRequest(objectId: "chart-1"))),
            #"{"refreshSheetsChart":{"objectId":"chart-1"}}"#
        )
    }

    func testArrowStyleNoneEncodesAsNONE() throws {
        // ArrowStyle.none must round-trip as "NONE"; it is a real arrow value,
        // distinct from an absent (Optional.none) arrow.
        XCTAssertEqual(
            try encodeJSON(LineStyle(startArrow: ArrowStyle.none)),
            #"{"startArrow":"NONE"}"#
        )
    }

    // MARK: - styleShape

    func testStyleShapeSendsFillOutlineShadowAndAlignment() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"presentationId":"p-1","replies":[{}]}"#)

        try await client.styleShape(
            presentationId: "p-1",
            objectId: "shape-1",
            fillColor: OpaqueColor(red: 1, green: 0, blue: 0),
            fillAlpha: 0.5,
            outlineColor: OpaqueColor(theme: .accent1),
            outlineWeight: 2,
            shadowColor: OpaqueColor(red: 0, green: 0, blue: 0),
            shadowBlur: 3,
            shadowOffsetX: 4,
            shadowOffsetY: 5,
            contentAlignment: .middle
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":["# + Self.shapeStyleUnionJSON + #"]}"#
        )
    }

    func testStyleShapeWithOnlyAFillColorMasksOnlyThatPath() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleShape(
            presentationId: "p-1", objectId: "shape-1",
            fillColor: OpaqueColor(red: 0, green: 0, blue: 1))

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateShapeProperties":{"fields":"shapeBackgroundFill.solidFill.color","objectId":"shape-1","shapeProperties":{"shapeBackgroundFill":{"solidFill":{"color":{"rgbColor":{"blue":1,"green":0,"red":0}}}}}}}]}"#
        )
    }

    func testStyleShapeNoFillSendsNotRenderedState() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleShape(presentationId: "p-1", objectId: "shape-1", noFill: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateShapeProperties":{"fields":"shapeBackgroundFill.propertyState","objectId":"shape-1","shapeProperties":{"shapeBackgroundFill":{"propertyState":"NOT_RENDERED"}}}}]}"#
        )
    }

    func testStyleShapeShadowOffsetsBuildOneTransformWithAMissingAxisZero() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // Only the x offset is given; the transform still appears once, with a
        // zero y translation and a single shadow.transform mask path.
        try await client.styleShape(
            presentationId: "p-1", objectId: "shape-1", shadowOffsetX: 4)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateShapeProperties":{"fields":"shadow.transform","objectId":"shape-1","shapeProperties":{"shadow":{"transform":{"scaleX":1,"scaleY":1,"shearX":0,"shearY":0,"translateX":4,"translateY":0,"unit":"PT"}}}}}]}"#
        )
    }

    func testStyleShapeRejectsNoOptionsWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleShape(presentationId: "p-1", objectId: "shape-1")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleShapeRejectsNoFillWithAFillColor() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleShape(
                presentationId: "p-1", objectId: "shape-1",
                fillColor: OpaqueColor(theme: .accent1), noFill: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleShapeRejectsNoOutlineWithAnOutlineColor() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleShape(
                presentationId: "p-1", objectId: "shape-1",
                outlineColor: OpaqueColor(theme: .accent1), noOutline: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleShapeRejectsNoShadowWithAShadowColor() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleShape(
                presentationId: "p-1", objectId: "shape-1",
                shadowColor: OpaqueColor(theme: .accent1), noShadow: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleShapeRejectsAnAlphaOutOfRange() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleShape(
                presentationId: "p-1", objectId: "shape-1", fillAlpha: 2)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleShapeRejectsANonPositiveOutlineWeight() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleShape(
                presentationId: "p-1", objectId: "shape-1", outlineWeight: 0)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleShapePropagatesAGoogleError() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Invalid requests[0]","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        do {
            try await client.styleShape(
                presentationId: "p-1", objectId: "shape-1", noFill: true)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
        }
    }

    // MARK: - styleImage

    func testStyleImageSendsOnlyTheOutline() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleImage(
            presentationId: "p-1", objectId: "image-1",
            outlineColor: OpaqueColor(theme: .accent2), outlineAlpha: 0.5,
            outlineWeight: 2, outlineDash: .dash)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateImageProperties":{"fields":"outline.outlineFill.solidFill.color,outline.outlineFill.solidFill.alpha,outline.weight,outline.dashStyle","imageProperties":{"outline":{"dashStyle":"DASH","outlineFill":{"solidFill":{"alpha":0.5,"color":{"themeColor":"ACCENT2"}}},"weight":{"magnitude":2,"unit":"PT"}}},"objectId":"image-1"}}]}"#
        )
    }

    func testStyleImageNoOutlineClearsIt() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleImage(
            presentationId: "p-1", objectId: "image-1", noOutline: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateImageProperties":{"fields":"outline.propertyState","imageProperties":{"outline":{"propertyState":"NOT_RENDERED"}},"objectId":"image-1"}}]}"#
        )
    }

    func testStyleImageRejectsNoOptionsWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleImage(presentationId: "p-1", objectId: "image-1")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleImageRejectsNoOutlineWithAnotherOutlineOption() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleImage(
                presentationId: "p-1", objectId: "image-1",
                outlineWeight: 2, noOutline: true)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - styleLine

    func testStyleLineSendsFillWeightDashAndArrows() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleLine(
            presentationId: "p-1", objectId: "line-1",
            color: OpaqueColor(red: 0, green: 0, blue: 1), alpha: 0.8,
            weight: 3, dash: .dashDot,
            startArrow: ArrowStyle.none, endArrow: ArrowStyle.fillArrow)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateLineProperties":{"fields":"lineFill.solidFill.color,lineFill.solidFill.alpha,weight,dashStyle,startArrow,endArrow","lineProperties":{"dashStyle":"DASH_DOT","endArrow":"FILL_ARROW","lineFill":{"solidFill":{"alpha":0.8,"color":{"rgbColor":{"blue":1,"green":0,"red":0}}}},"startArrow":"NONE","weight":{"magnitude":3,"unit":"PT"}},"objectId":"line-1"}}]}"#
        )
    }

    func testStyleLineMasksOnlyTheProvidedOption() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleLine(presentationId: "p-1", objectId: "line-1", dash: .dot)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateLineProperties":{"fields":"dashStyle","lineProperties":{"dashStyle":"DOT"},"objectId":"line-1"}}]}"#
        )
    }

    func testStyleLineRejectsNoOptionsWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleLine(presentationId: "p-1", objectId: "line-1")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleLineRejectsAnAlphaOutOfRange() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleLine(presentationId: "p-1", objectId: "line-1", alpha: -0.5)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - styleVideo

    func testStyleVideoSendsPlaybackOptionsAndOutline() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleVideo(
            presentationId: "p-1", objectId: "video-1",
            autoPlay: true, mute: false, start: 5, end: 30,
            outlineColor: OpaqueColor(theme: .dark1), outlineWeight: 1.5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateVideoProperties":{"fields":"autoPlay,mute,start,end,outline.outlineFill.solidFill.color,outline.weight","objectId":"video-1","videoProperties":{"autoPlay":true,"end":30,"mute":false,"outline":{"outlineFill":{"solidFill":{"color":{"themeColor":"DARK1"}}},"weight":{"magnitude":1.5,"unit":"PT"}},"start":5}}}]}"#
        )
    }

    func testStyleVideoTreatsFalseFlagsAsProvided() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // autoPlay:false and mute:true are both "provided" (not nil), so both
        // appear in the mask and body; a nil flag would be left unchanged.
        try await client.styleVideo(
            presentationId: "p-1", objectId: "video-1", autoPlay: false, mute: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateVideoProperties":{"fields":"autoPlay,mute","objectId":"video-1","videoProperties":{"autoPlay":false,"mute":true}}}]}"#
        )
    }

    func testStyleVideoRejectsANegativeStartWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleVideo(presentationId: "p-1", objectId: "video-1", start: -1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleVideoRejectsAnEndNotGreaterThanStart() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleVideo(
                presentationId: "p-1", objectId: "video-1", start: 10, end: 10)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testStyleVideoRejectsNoOptionsWithoutARequest() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.styleVideo(presentationId: "p-1", objectId: "video-1")
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - refreshSheetsChart

    func testRefreshSheetsChartSendsOnlyTheObjectId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"presentationId":"p-1","replies":[{}]}"#)

        try await client.refreshSheetsChart(presentationId: "p-1", objectId: "chart-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"refreshSheetsChart":{"objectId":"chart-1"}}]}"#
        )
    }

    // MARK: - Helpers

    /// Fails unless the async body throws ``GrahamError/invalidArgument(_:)``.
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

    /// Encodes any Encodable value with the shared encoder (sorted keys).
    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        String(data: try GoogleJSON.encoder.encode(value), encoding: .utf8) ?? ""
    }

    private struct SentTransformBatch: Decodable {
        let requests: [SentTransformEnvelope]
    }

    private struct SentTransformEnvelope: Decodable {
        let updatePageElementTransform: UpdatePageElementTransformRequest
    }

    private func sentTransform(_ transport: StubTransport) throws
        -> UpdatePageElementTransformRequest
    {
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        let body = try XCTUnwrap(request.body)
        return try GoogleJSON.decoder.decode(SentTransformBatch.self, from: body)
            .requests[0].updatePageElementTransform
    }

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
