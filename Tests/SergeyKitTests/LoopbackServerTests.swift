import XCTest
@testable import SergeyKit

final class LoopbackServerTests: XCTestCase {
    func testParsesTheCallbackQuery() {
        let request = "GET /?state=xyz&code=4%2Fabc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let query = LoopbackServer.parseQuery(fromRequest: request)
        XCTAssertEqual(query["state"], "xyz")
        XCTAssertEqual(query["code"], "4/abc")
    }

    func testParsesAnErrorCallback() {
        let request = "GET /?error=access_denied&state=xyz HTTP/1.1\r\n\r\n"
        let query = LoopbackServer.parseQuery(fromRequest: request)
        XCTAssertEqual(query["error"], "access_denied")
    }

    func testIgnoresARequestWithoutAQuery() {
        let request = "GET /favicon.ico HTTP/1.1\r\n\r\n"
        let query = LoopbackServer.parseQuery(fromRequest: request)
        XCTAssertTrue(query.isEmpty)
    }

    func testAuthorizationURLContainsTheRequiredParameters() throws {
        let url = try OAuthLoginFlow.authorizationURL(
            clientID: "client-1",
            redirectURI: "http://127.0.0.1:9004",
            scopes: [.documents, .presentations],
            state: "state-1"
        )
        let text = url.absoluteString
        XCTAssertTrue(text.hasPrefix(OAuthLoginFlow.authEndpoint))
        XCTAssertTrue(text.contains("client_id=client-1"))
        XCTAssertTrue(text.contains("response_type=code"))
        XCTAssertTrue(text.contains("access_type=offline"))
        XCTAssertTrue(text.contains("prompt=consent"))
        XCTAssertTrue(text.contains("state=state-1"))
        // The two scope URLs, separated by an encoded space.
        XCTAssertTrue(text.contains("documents%20https"))
    }
}
