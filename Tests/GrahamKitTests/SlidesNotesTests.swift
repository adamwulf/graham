import XCTest
@testable import GrahamKit

/// Tests for the speaker-notes read facade and the notes read/set/clear client
/// methods. Every fixture is static JSON; no test touches the network, and the
/// batch-update bodies are asserted exactly (the shared encoder sorts keys).
final class SlidesNotesTests: XCTestCase {

    /// Three slides: one with notes text, one whose notes shape is missing from
    /// the notes page, and one whose notes shape exists but is empty.
    private static let notesJSON = #"""
    {
      "presentationId": "p-notes",
      "slides": [
        {
          "objectId": "slide-1",
          "slideProperties": {
            "notesPage": {
              "objectId": "notes-page-1",
              "notesProperties": {"speakerNotesObjectId": "notes-1"},
              "pageElements": [
                {"objectId": "notes-1", "shape": {"shapeType": "TEXT_BOX",
                  "text": {"textElements": [
                    {"textRun": {"content": "Remember to smile"}}
                  ]}}}
              ]
            }
          }
        },
        {
          "objectId": "slide-2",
          "slideProperties": {
            "notesPage": {
              "objectId": "notes-page-2",
              "notesProperties": {"speakerNotesObjectId": "notes-2"},
              "pageElements": []
            }
          }
        },
        {
          "objectId": "slide-3",
          "slideProperties": {
            "notesPage": {
              "objectId": "notes-page-3",
              "notesProperties": {"speakerNotesObjectId": "notes-3"},
              "pageElements": [
                {"objectId": "notes-3", "shape": {"shapeType": "TEXT_BOX",
                  "text": {"textElements": [
                    {"paragraphMarker": {}},
                    {"textRun": {"content": "\n"}}
                  ]}}}
              ]
            }
          }
        }
      ]
    }
    """#

    private func decodeNotes() throws -> Presentation {
        try GoogleJSON.decoder.decode(Presentation.self, from: Data(Self.notesJSON.utf8))
    }

    // MARK: - Read facade

    func testSpeakerNotesRowsCoverTextMissingAndEmpty() throws {
        let rows = try decodeNotes().speakerNotesRows
        XCTAssertEqual(rows.count, 3)

        // A slide with notes text.
        XCTAssertEqual(rows[0].slideNumber, 1)
        XCTAssertEqual(rows[0].slideId, "slide-1")
        XCTAssertEqual(rows[0].notesShapeId, "notes-1")
        XCTAssertEqual(rows[0].notes, "Remember to smile")

        // A slide whose notes shape is missing from the notes page: the shape
        // id is still reported, but the notes text is empty.
        XCTAssertEqual(rows[1].slideNumber, 2)
        XCTAssertEqual(rows[1].slideId, "slide-2")
        XCTAssertEqual(rows[1].notesShapeId, "notes-2")
        XCTAssertEqual(rows[1].notes, "")

        // A slide whose notes shape exists but has no text.
        XCTAssertEqual(rows[2].slideNumber, 3)
        XCTAssertEqual(rows[2].notesShapeId, "notes-3")
        XCTAssertEqual(rows[2].notes, "")
    }

    func testSpeakerNotesRowsAreEmptyWithoutNotesProperties() throws {
        // A slide with no slideProperties at all yields an empty row, not a crash.
        let json = #"{"slides":[{"objectId":"s1"}]}"#
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(json.utf8))
        let rows = presentation.speakerNotesRows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].slideNumber, 1)
        XCTAssertNil(rows[0].notesShapeId)
        XCTAssertEqual(rows[0].notes, "")
    }

    func testSpeakerNotesTableRendersColumns() throws {
        let rows = try decodeNotes().speakerNotesRows
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let header = try XCTUnwrap(lines.first)
        XCTAssertTrue(header.hasPrefix("SLIDE"), header)
        for column in ["SLIDE_ID", "NOTES_SHAPE"] {
            XCTAssertTrue(header.contains(column), "\(column) missing from header: \(header)")
        }
        XCTAssertTrue(header.hasSuffix("NOTES"), header)

        let first = try XCTUnwrap(lines.first { $0.contains("slide-1") })
        XCTAssertTrue(first.hasPrefix("1 "), first)
        XCTAssertTrue(first.hasSuffix("Remember to smile"), first)
    }

    // MARK: - speakerNotes (read)

    func testSpeakerNotesMasksTheReadToTheNotesPages() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(urlContains: "presentations/p-notes?fields=", json: Self.notesJSON)

        let rows = try await client.speakerNotes(presentationId: "p-notes")

        let read = try XCTUnwrap(transport.requests(urlContains: "presentations/p-notes?").first)
        XCTAssertEqual(read.method, "GET")
        XCTAssertTrue(
            read.url.absoluteString.contains("fields=slides.objectId"),
            "the read should mask to the notes pages: \(read.url.absoluteString)"
        )
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].notes, "Remember to smile")
        // A read sends no write.
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - setSpeakerNotes

    func testSetSpeakerNotesOnAShapeWithTextSendsDeleteThenInsertInOneBatch() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        stubNotesEndpoints(transport)

        try await client.setSpeakerNotes(
            presentationId: "p-notes", slideId: "slide-1", text: "New notes")

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v1/presentations/p-notes:batchUpdate")
        // Delete then insert, both targeting the speaker-notes shape id, in one
        // atomic batch.
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"deleteText":{"objectId":"notes-1","textRange":{"type":"ALL"}}},{"insertText":{"insertionIndex":0,"objectId":"notes-1","text":"New notes"}}]}"#
        )
    }

    func testSetSpeakerNotesOnAMissingShapeSendsOnlyInsert() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        stubNotesEndpoints(transport)

        // slide-2's notes shape is absent from the notes page, so there is no
        // text to delete first: inserting text creates the shape.
        try await client.setSpeakerNotes(
            presentationId: "p-notes", slideId: "slide-2", text: "Hello")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertText":{"insertionIndex":0,"objectId":"notes-2","text":"Hello"}}]}"#
        )
    }

    func testSetSpeakerNotesOnAnEmptyShapeSendsOnlyInsert() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        stubNotesEndpoints(transport)

        // slide-3's notes shape exists but is empty, so no delete is needed.
        try await client.setSpeakerNotes(
            presentationId: "p-notes", slideId: "slide-3", text: "Hi")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertText":{"insertionIndex":0,"objectId":"notes-3","text":"Hi"}}]}"#
        )
    }

    func testSetSpeakerNotesRejectsAnUnknownSlideWithNoWrite() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        stubNotesEndpoints(transport)

        do {
            try await client.setSpeakerNotes(
                presentationId: "p-notes", slideId: "nope", text: "x")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testSetSpeakerNotesThrowsWhenTheSlideHasNoNotesShapeId() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        // A slide whose notes page names no speaker-notes shape id.
        let json = #"""
        {"slides":[{"objectId":"slide-1","slideProperties":{"notesPage":{"notesProperties":{}}}}]}
        """#
        transport.stub(urlContains: "presentations/p-notes?fields=", json: json)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        do {
            try await client.setSpeakerNotes(
                presentationId: "p-notes", slideId: "slide-1", text: "x")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - clearSpeakerNotes

    func testClearSpeakerNotesOnAShapeWithTextSendsOnlyDelete() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        stubNotesEndpoints(transport)

        try await client.clearSpeakerNotes(presentationId: "p-notes", slideId: "slide-1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"deleteText":{"objectId":"notes-1","textRange":{"type":"ALL"}}}]}"#
        )
    }

    func testClearSpeakerNotesOnAnEmptyShapeSendsNothing() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        stubNotesEndpoints(transport)

        // Clearing already-empty notes is a no-op (the moveSlide precedent).
        try await client.clearSpeakerNotes(presentationId: "p-notes", slideId: "slide-3")

        XCTAssertEqual(transport.requests(urlContains: "presentations/p-notes?").count, 1)
        XCTAssertTrue(
            transport.requests(urlContains: ":batchUpdate").isEmpty,
            "clearing an empty notes shape must not send a batch update")
    }

    // MARK: - Helpers

    /// Stubs the masked notes read and an empty batch-update reply.
    private func stubNotesEndpoints(_ transport: StubTransport) {
        transport.stub(urlContains: "presentations/p-notes?fields=", json: Self.notesJSON)
        transport.stub(urlContains: ":batchUpdate", json: #"{"presentationId":"p-notes","replies":[{}]}"#)
    }


    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
}
