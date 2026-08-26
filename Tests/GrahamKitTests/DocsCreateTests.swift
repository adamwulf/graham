import XCTest
@testable import GrahamKit

/// Offline coverage for `documents.create`: the exact method and URL, the
/// encoded request body, the decoded reply, an empty reply, and Google error
/// propagation. Every fixture is static JSON; no test touches the network.
final class DocsCreateTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    func testCreatePostsTitleInTheBodyAndDecodesTheDocument() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/v1/documents",
            json: #"{"documentId":"doc-new","title":"My Doc"}"#
        )

        let document = try await client.create(title: "My Doc")

        let request = try XCTUnwrap(transport.requests(urlContains: "/v1/documents").first)
        // A POST to the collection, with no id in the path.
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        // The title is carried in the JSON body, never in the URL.
        XCTAssertEqual(Self.bodyString(request), #"{"title":"My Doc"}"#)
        // The response is decoded and returned.
        XCTAssertEqual(document.documentId, "doc-new")
        XCTAssertEqual(document.title, "My Doc")
    }

    func testCreateDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/v1/documents", json: "{}")

        let document = try await client.create(title: "Empty")

        XCTAssertNil(document.documentId)
        XCTAssertNil(document.title)
        XCTAssertNil(document.body)
    }

    func testCreateEncodesTrickyTitlesSafely() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/v1/documents", json: #"{"documentId":"x"}"#)

        // Quotes, a backslash, a newline, and a non-ASCII character.
        let tricky = "Q3 \"Report\"\n\\path — café"
        _ = try await client.create(title: tricky)

        let request = try XCTUnwrap(transport.requests(urlContains: "/v1/documents").first)
        // The title round-trips exactly through the JSON body, and never
        // appears in the URL.
        let body = try GoogleJSON.decoder.decode(
            DocsCreateRequest.self, from: XCTUnwrap(request.body))
        XCTAssertEqual(body.title, tricky)
        XCTAssertEqual(
            request.url.absoluteString,
            "https://docs.googleapis.com/v1/documents"
        )
    }

    func testCreatePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/v1/documents",
            json: #"{"error":{"code":403,"message":"No access","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )

        do {
            _ = try await client.create(title: "x")
            XCTFail("Expected an error")
        } catch GrahamError.googleAPIError(let code, let status, let message) {
            XCTAssertEqual(code, 403)
            XCTAssertEqual(status, "PERMISSION_DENIED")
            XCTAssertEqual(message, "No access")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testCreateRequestEncodesTitleOnly() throws {
        let body = DocsCreateRequest(title: "Budget")
        let data = try GoogleJSON.encoder.encode(body)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"title":"Budget"}"#)
    }

    private static func bodyString(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
