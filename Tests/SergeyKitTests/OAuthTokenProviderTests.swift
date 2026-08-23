import XCTest
@testable import SergeyKit

final class OAuthTokenProviderTests: XCTestCase {
    func testRefreshesAndCachesTheAccessToken() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint(accessToken: "fresh-token")
        let provider = OAuthTokenProvider(credentials: TestSupport.credentials, transport: transport)

        let first = try await provider.validAccessToken()
        let second = try await provider.validAccessToken()

        XCTAssertEqual(first, "fresh-token")
        XCTAssertEqual(second, "fresh-token")
        XCTAssertEqual(transport.requests(urlContains: "oauth2.googleapis.com/token").count, 1)
    }

    func testSendsTheRefreshGrant() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        let provider = OAuthTokenProvider(credentials: TestSupport.credentials, transport: transport)

        _ = try await provider.validAccessToken()

        let request = try XCTUnwrap(transport.requests(urlContains: "oauth2.googleapis.com/token").first)
        let body = String(data: try XCTUnwrap(request.body), encoding: .utf8) ?? ""
        XCTAssertEqual(request.method, "POST")
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=test-refresh-token"))
        XCTAssertTrue(body.contains("client_id=test-client-id"))
    }

    func testInvalidateForcesANewRefresh() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        let provider = OAuthTokenProvider(credentials: TestSupport.credentials, transport: transport)

        _ = try await provider.validAccessToken()
        await provider.invalidate()
        _ = try await provider.validAccessToken()

        XCTAssertEqual(transport.requests(urlContains: "oauth2.googleapis.com/token").count, 2)
    }

    func testThrowsWithoutARefreshToken() async {
        let transport = StubTransport()
        let credentials = GoogleCredentials(clientID: "id", clientSecret: "secret", refreshToken: nil)
        let provider = OAuthTokenProvider(credentials: credentials, transport: transport)

        do {
            _ = try await provider.validAccessToken()
            XCTFail("Expected an error")
        } catch {
            guard case SergeyError.missingRefreshToken = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testThrowsOnTokenEndpointFailure() async {
        let transport = StubTransport()
        transport.stub(
            urlContains: "oauth2.googleapis.com/token",
            json: #"{"error":"invalid_grant"}"#,
            status: 400
        )
        let provider = OAuthTokenProvider(credentials: TestSupport.credentials, transport: transport)

        do {
            _ = try await provider.validAccessToken()
            XCTFail("Expected an error")
        } catch {
            guard case SergeyError.oauthError(let detail) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("400"))
        }
    }
}
