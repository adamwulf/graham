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
