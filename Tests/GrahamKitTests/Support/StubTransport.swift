import Foundation
@testable import GrahamKit

/// A fake transport for offline tests.
///
/// Tests register stubs that match on a URL fragment. A stub with more than
/// one response serves them in order, and keeps serving the last one. An
/// unmatched request returns HTTP 599, so a test fails loudly instead of
/// touching the network.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private struct Stub {
        let matches: (HTTPRequest) -> Bool
        var responses: [HTTPResponse]
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private var allRequests: [HTTPRequest] = []

    /// All requests seen so far.
    var requests: [HTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return allRequests
    }

    func requests(urlContains fragment: String) -> [HTTPRequest] {
        requests.filter { $0.url.absoluteString.contains(fragment) }
    }

    func stub(urlContains fragment: String, responses: [HTTPResponse]) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(
            matches: { $0.url.absoluteString.contains(fragment) },
            responses: responses
        ))
    }

    func stub(urlContains fragment: String, json: String, status: Int = 200) {
        stub(urlContains: fragment, responses: [Self.json(json, status: status)])
    }

    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: headers, body: Data(body.utf8))
    }

    /// The standard token endpoint stub, so `OAuthTokenProvider` can refresh.
    func stubTokenEndpoint(accessToken: String = "test-token") {
        stub(
            urlContains: "oauth2.googleapis.com/token",
            json: #"{"access_token":"\#(accessToken)","expires_in":3600,"token_type":"Bearer"}"#
        )
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        respond(to: request)
    }

    private func respond(to request: HTTPRequest) -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        allRequests.append(request)
        for index in stubs.indices where stubs[index].matches(request) {
            if stubs[index].responses.count > 1 {
                return stubs[index].responses.removeFirst()
            }
            return stubs[index].responses[0]
        }
        return HTTPResponse(statusCode: 599, body: Data("unmatched request: \(request.url)".utf8))
    }
}

/// Shared builders for tests.
enum TestSupport {
    static let credentials = GoogleCredentials(
        clientID: "test-client-id",
        clientSecret: "test-client-secret",
        refreshToken: "test-refresh-token"
    )

    /// Builds a `GoogleAPI` over a stub transport. The `sleep` closure records
    /// backoff delays instead of waiting, so retry tests run instantly.
    static func makeAPI(
        transport: StubTransport,
        credentials: GoogleCredentials = credentials,
        onSleep: (@Sendable (TimeInterval) -> Void)? = nil
    ) -> GoogleAPI {
        let provider = OAuthTokenProvider(credentials: credentials, transport: transport)
        return GoogleAPI(
            tokenProvider: provider,
            transport: transport,
            sleep: { seconds in onSleep?(seconds) }
        )
    }
}
