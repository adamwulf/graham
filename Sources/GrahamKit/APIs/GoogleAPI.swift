import Foundation

/// The standard Google error envelope, for example:
/// `{"error": {"code": 403, "message": "...", "status": "PERMISSION_DENIED"}}`
struct GoogleErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }

    let error: Detail
}

/// The low-level executor for all Google API requests.
///
/// This is the only place that:
/// - adds the `Authorization` header,
/// - refreshes the access token after a 401 (one time per request),
/// - retries 429 and 5xx responses with exponential backoff, and honors
///   the `Retry-After` header,
/// - decodes JSON and the Google error envelope.
///
/// The service clients (``DriveClient``, ``SheetsClient``, ``DocsClient``,
/// ``SlidesClient``) sit on top and hold the pagination and the endpoints.
public final class GoogleAPI: @unchecked Sendable {
    private let tokenProvider: OAuthTokenProvider
    private let transport: any HTTPTransport
    private let maxRetries: Int
    private let maxBackoff: TimeInterval = 60
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(
        tokenProvider: OAuthTokenProvider,
        transport: any HTTPTransport,
        maxRetries: Int = 3,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.maxRetries = maxRetries
        self.sleep = sleep
    }

    /// Sends a GET request and decodes the JSON response.
    public func getJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let response = try await send(HTTPRequest(method: "GET", url: url))
        return try decode(type, from: response.body)
    }

    /// Sends a GET request and returns the raw body, for downloads and exports.
    public func getData(from url: URL) async throws -> Data {
        try await send(HTTPRequest(method: "GET", url: url)).body
    }

    /// Sends a request with a JSON body and decodes the JSON response.
    /// Used for POST/PUT endpoints such as `values.update` and `batchUpdate`.
    public func sendJSON<T: Decodable, Body: Encodable>(
        _ type: T.Type,
        method: String,
        url: URL,
        body: Body
    ) async throws -> T {
        let data = try GoogleJSON.encoder.encode(body)
        let request = HTTPRequest(
            method: method,
            url: url,
            headers: ["Content-Type": "application/json"],
            body: data
        )
        let response = try await send(request)
        return try decode(type, from: response.body)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try GoogleJSON.decoder.decode(type, from: data)
        } catch {
            throw GrahamError.decodeError(detail: GrahamError.decodingDetail(error))
        }
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await send(request, retryCount: 0, hasRefreshedToken: false)
    }

    private func send(
        _ request: HTTPRequest,
        retryCount: Int,
        hasRefreshedToken: Bool
    ) async throws -> HTTPResponse {
        var authorized = request
        let token = try await tokenProvider.validAccessToken()
        authorized.headers["Authorization"] = "Bearer \(token)"
        if authorized.headers["Accept"] == nil {
            authorized.headers["Accept"] = "application/json"
        }
        let response = try await transport.send(authorized)
        switch response.statusCode {
        case 200..<300:
            return response
        case 401 where !hasRefreshedToken:
            GrahamLog.log("Got 401. Refreshing the access token and retrying.")
            await tokenProvider.invalidate()
            return try await send(request, retryCount: retryCount, hasRefreshedToken: true)
        case 429, 500...599:
            guard retryCount < maxRetries else {
                throw error(from: response)
            }
            let retryAfter = TimeInterval(response.value(forHeader: "Retry-After") ?? "") ?? 0
            let backoff = min(maxBackoff, pow(2.0, Double(retryCount)))
            let delay = max(retryAfter, backoff)
            GrahamLog.log(
                "Got status \(response.statusCode). Retrying in \(delay) seconds "
                + "(attempt \(retryCount + 1) of \(maxRetries))."
            )
            await sleep(delay)
            return try await send(request, retryCount: retryCount + 1, hasRefreshedToken: hasRefreshedToken)
        default:
            throw error(from: response)
        }
    }

    func error(from response: HTTPResponse) -> GrahamError {
        if let envelope = try? GoogleJSON.decoder.decode(GoogleErrorEnvelope.self, from: response.body) {
            return .googleAPIError(
                code: envelope.error.code ?? response.statusCode,
                status: envelope.error.status,
                message: envelope.error.message ?? "Unknown error"
            )
        }
        let text = String(data: response.body, encoding: .utf8) ?? ""
        return .httpError(statusCode: response.statusCode, body: String(text.prefix(500)))
    }
}
