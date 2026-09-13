import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 smart-chip inserts: `insertPerson`,
/// `insertRichLink`, and `insertDate`. Every fixture is static JSON; no test
/// touches the network, and the request bodies are asserted exactly (the shared
/// encoder sorts keys, so the strings are deterministic).
final class DocsSmartChipsWriteTests: GrahamTestCase {

    // MARK: - insertPerson

    func testInsertPersonAtIndexEncodesEmailAndNameAndLocation() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#
        )

        let response = try await client.insertPerson(
            documentId: "doc-1", email: "a@b.com", name: "Ada", index: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertPerson":{"location":{"index":5},"personProperties":{"email":"a@b.com","name":"Ada"}}}]}"#
        )
        XCTAssertEqual(response.documentId, "doc-1")
    }

    func testInsertPersonAtEndEncodesEndOfSegmentAndTabIdOmitsName() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertPerson(
            documentId: "doc-1", email: "a@b.com", endOfSegment: true, tabId: "t.0")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertPerson":{"endOfSegmentLocation":{"tabId":"t.0"},"personProperties":{"email":"a@b.com"}}}]}"#
        )
    }

    func testInsertPersonInSegmentAllowsIndexZero() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertPerson(
            documentId: "doc-1", email: "a@b.com", index: 0, segmentId: "h.0")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertPerson":{"location":{"index":0,"segmentId":"h.0"},"personProperties":{"email":"a@b.com"}}}]}"#
        )
    }

    func testInsertPersonRejectsBadInputWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // An empty email.
        await assertInvalidArgument {
            _ = try await client.insertPerson(documentId: "doc-1", email: "  ", index: 1)
        }
        // A body index of 0 (the body starts at 1).
        await assertInvalidArgument {
            _ = try await client.insertPerson(documentId: "doc-1", email: "a@b.com", index: 0)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - insertRichLink

    func testInsertRichLinkAtIndexEncodesAllPropertiesAndLocation() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertRichLink(
            documentId: "doc-1",
            uri: "https://drive.google.com/x",
            title: "Doc",
            mimeType: "application/pdf",
            index: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertRichLink":{"location":{"index":3},"richLinkProperties":{"mimeType":"application\/pdf","title":"Doc","uri":"https:\/\/drive.google.com\/x"}}}]}"#
        )
    }

    func testInsertRichLinkAtEndUriOnly() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertRichLink(
            documentId: "doc-1", uri: "https://youtu.be/x", endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertRichLink":{"endOfSegmentLocation":{},"richLinkProperties":{"uri":"https:\/\/youtu.be\/x"}}}]}"#
        )
    }

    func testInsertRichLinkRejectsEmptyUriWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        await assertInvalidArgument {
            _ = try await client.insertRichLink(documentId: "doc-1", uri: "  ", index: 1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // graham forwards the `--uri` unchanged; the Docs API alone decides which
    // URLs it accepts. A live experiment (2026-09-13) confirmed the
    // `insertRichLink` operation accepts ONLY Google Drive / Workspace file
    // URLs: a Drive file URL succeeds (the API fetches the file's title and MIME
    // type), while a YouTube watch URL, a youtu.be short URL, and a plain web
    // URL are each rejected with `400 INVALID_ARGUMENT` "The URL is invalid."
    // These cases lock the encoding — every form is forwarded verbatim — so the
    // accept/reject decision stays the API's, never graham's.
    func testInsertRichLinkForwardsEveryURLFormVerbatim() async throws {
        let cases: [(uri: String, encoded: String)] = [
            // Accepted live: a Drive file URL.
            (
                "https://docs.google.com/spreadsheets/d/SHEET_ID/edit",
                #"https:\/\/docs.google.com\/spreadsheets\/d\/SHEET_ID\/edit"#
            ),
            // Accepted live: the drive.google.com/open?id= form.
            (
                "https://drive.google.com/open?id=SHEET_ID",
                #"https:\/\/drive.google.com\/open?id=SHEET_ID"#
            ),
            // Rejected live (400 "The URL is invalid"): a YouTube watch URL.
            (
                "https://www.youtube.com/watch?v=b5v43xfIqO0",
                #"https:\/\/www.youtube.com\/watch?v=b5v43xfIqO0"#
            ),
            // Rejected live: a youtu.be short URL.
            ("https://youtu.be/b5v43xfIqO0", #"https:\/\/youtu.be\/b5v43xfIqO0"#),
            // Rejected live: a plain web URL.
            ("https://example.com/", #"https:\/\/example.com\/"#),
        ]
        for (uri, encoded) in cases {
            let transport = StubTransport()
            let client = TestSupport.docsClient(transport)
            transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

            _ = try await client.insertRichLink(
                documentId: "doc-1", uri: uri, endOfSegment: true)

            let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
            XCTAssertEqual(
                TestSupport.bodyString(request),
                #"{"requests":[{"insertRichLink":{"endOfSegmentLocation":{},"richLinkProperties":{"uri":""#
                    + encoded + #""}}}]}"#,
                "unexpected encoded body for \(uri)")
        }
    }

    // The omitted-key cases: a nil `title` or `mimeType` drops out of the body
    // entirely (it is never sent as null), so a caller can send only the URI and
    // let the API fetch the rest, or hint just one of the two.
    func testInsertRichLinkWithTitleOmitsMimeType() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertRichLink(
            documentId: "doc-1",
            uri: "https://docs.google.com/document/d/DOC_ID/edit",
            title: "Report",
            index: 1)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertRichLink":{"location":{"index":1},"richLinkProperties":{"title":"Report","uri":"https:\/\/docs.google.com\/document\/d\/DOC_ID\/edit"}}}]}"#
        )
    }

    func testInsertRichLinkWithMimeTypeOmitsTitle() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertRichLink(
            documentId: "doc-1",
            uri: "https://docs.google.com/document/d/DOC_ID/edit",
            mimeType: "application/vnd.google-apps.document",
            index: 1)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertRichLink":{"location":{"index":1},"richLinkProperties":{"mimeType":"application\/vnd.google-apps.document","uri":"https:\/\/docs.google.com\/document\/d\/DOC_ID\/edit"}}}]}"#
        )
    }

    // MARK: - insertDate

    func testInsertDateAtIndexEncodesEveryPropertyAndLocation() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertDate(
            documentId: "doc-1",
            timestamp: "2026-08-27T00:00:00Z",
            locale: "en-US",
            timeZoneId: "America/Chicago",
            dateFormat: .iso8601,
            timeFormat: .disabled,
            index: 2)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertDate":{"dateElementProperties":{"dateFormat":"DATE_FORMAT_ISO8601","locale":"en-US","timeFormat":"TIME_FORMAT_DISABLED","timeZoneId":"America\/Chicago","timestamp":"2026-08-27T00:00:00Z"},"location":{"index":2}}}]}"#
        )
    }

    func testInsertDateAtEndTimestampOnly() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        _ = try await client.insertDate(
            documentId: "doc-1", timestamp: "2026-08-27T00:00:00Z", endOfSegment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"insertDate":{"dateElementProperties":{"timestamp":"2026-08-27T00:00:00Z"},"endOfSegmentLocation":{}}}]}"#
        )
    }

    func testInsertDateRejectsEmptyTimestampWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        await assertInvalidArgument {
            _ = try await client.insertDate(documentId: "doc-1", timestamp: "   ", index: 1)
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Union discriminators

    /// Each chip encodes under its own JSON key, so a caller can mix them in one
    /// batch. This locks the three discriminators.
    func testEachChipRequestEncodesUnderItsOwnKey() throws {
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .insertPerson(DocsInsertPersonRequest(
                    personProperties: DocsPersonProperties(email: "a@b.com"),
                    location: DocsLocation(index: 1))),
                #"{"insertPerson":{"location":{"index":1},"personProperties":{"email":"a@b.com"}}}"#
            ),
            (
                .insertRichLink(DocsInsertRichLinkRequest(
                    richLinkProperties: DocsRichLinkProperties(uri: "u"),
                    location: DocsLocation(index: 1))),
                #"{"insertRichLink":{"location":{"index":1},"richLinkProperties":{"uri":"u"}}}"#
            ),
            (
                .insertDate(DocsInsertDateRequest(
                    dateElementProperties: DocsDateElementProperties(timestamp: "t"),
                    location: DocsLocation(index: 1))),
                #"{"insertDate":{"dateElementProperties":{"timestamp":"t"},"location":{"index":1}}}"#
            ),
        ]
        for (request, expected) in cases {
            let data = try GoogleJSON.encoder.encode(request)
            XCTAssertEqual(String(data: data, encoding: .utf8), expected)
        }
    }


}
