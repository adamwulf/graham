import Foundation

/// The standard Google error envelope, for example:
/// `{"error": {"code": 403, "message": "...", "status": "PERMISSION_DENIED"}}`
///
/// Rate-limit replies (429, or 403 with a rate-limit status) often carry a
/// `google.rpc.RetryInfo` inside `error.details` telling the client exactly how
/// long to wait, for example:
/// `{"error": {"code": 429, "status": "RESOURCE_EXHAUSTED",
///   "details": [{"@type": "type.googleapis.com/google.rpc.RetryInfo",
///   "retryDelay": "30s"}]}}`
struct GoogleErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: Int?
        let message: String?
        let status: String?
        let details: [ErrorDetail]?
    }

    /// One entry in `error.details`. Only the `@type` discriminator and the
    /// `RetryInfo.retryDelay` are modelled; other detail payloads decode to nil.
    struct ErrorDetail: Decodable {
        let type: String?
        let retryDelay: String?

        enum CodingKeys: String, CodingKey {
            case type = "@type"
            case retryDelay
        }
    }

    let error: Detail

    /// True when the envelope reports a rate limit. Google surfaces these as a
    /// 429 `RESOURCE_EXHAUSTED`, or as a 403 whose status is
    /// `rateLimitExceeded`/`userRateLimitExceeded` (see the CLAUDE.md gotcha).
    var isRateLimit: Bool {
        switch error.status {
        case "RESOURCE_EXHAUSTED", "rateLimitExceeded", "userRateLimitExceeded":
            return true
        default:
            return false
        }
    }

    /// The server-requested wait from a `RetryInfo` detail, in seconds, if the
    /// reply carries one. The value is a protobuf `Duration` string such as
    /// `"30s"` or `"1.500s"`.
    var retryDelaySeconds: TimeInterval? {
        guard let details = error.details else { return nil }
        for detail in details where detail.type?.hasSuffix("RetryInfo") == true {
            if let raw = detail.retryDelay, let seconds = Self.parseDuration(raw) {
                return seconds
            }
        }
        return nil
    }

    /// Parses a protobuf `Duration` string (a decimal number of seconds with a
    /// trailing `s`) into a `TimeInterval`.
    static func parseDuration(_ raw: String) -> TimeInterval? {
        let trimmed = raw.hasSuffix("s") ? String(raw.dropLast()) : raw
        return TimeInterval(trimmed)
    }
}

/// The low-level executor for all Google API requests.
///
/// This is the only place that:
/// - adds the `Authorization` header,
/// - refreshes the access token after a 401 (one time per request),
/// - retries rate-limit and transient errors (429, 5xx, and 403 rate-limit
///   envelopes) with exponential backoff, honoring the `Retry-After` header
///   and any `RetryInfo.retryDelay` the error body carries,
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

    /// Sends a request that returns no body to decode, such as a `DELETE` that
    /// replies with HTTP 204 and an empty body. The token refresh after a 401
    /// and the 429/5xx retry and backoff behave exactly as for every other
    /// request; only the (empty) response body is ignored.
    public func sendNoContent(method: String, url: URL) async throws {
        _ = try await send(HTTPRequest(method: method, url: url))
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
        default:
            let envelope = try? GoogleJSON.decoder.decode(GoogleErrorEnvelope.self, from: response.body)
            guard isRetryable(statusCode: response.statusCode, envelope: envelope) else {
                throw error(from: response, envelope: envelope)
            }
            guard retryCount < maxRetries else {
                throw error(from: response, envelope: envelope)
            }
            let serverHint = serverRetryHint(response: response, envelope: envelope)
            let backoff = min(maxBackoff, pow(2.0, Double(retryCount)))
            let delay = max(backoff, serverHint ?? 0)
            let status = envelope?.error.status.map { " (\($0))" } ?? ""
            let hint = serverHint.map { String(format: "%.0fs", $0) } ?? "none"
            GrahamLog.log(
                "Got status \(response.statusCode)\(status). Server retry hint: \(hint). "
                + "Retrying in \(delay) seconds (attempt \(retryCount + 1) of \(maxRetries))."
            )
            await sleep(delay)
            return try await send(request, retryCount: retryCount + 1, hasRefreshedToken: hasRefreshedToken)
        }
    }

    /// Whether a non-2xx, non-401 response should be retried: any 429 or 5xx,
    /// plus a 403 whose error envelope reports a rate limit.
    private func isRetryable(statusCode: Int, envelope: GoogleErrorEnvelope?) -> Bool {
        switch statusCode {
        case 429, 500...599:
            return true
        case 403:
            return envelope?.isRateLimit ?? false
        default:
            return false
        }
    }

    /// The wait the server explicitly asked for, taking the larger of the
    /// `Retry-After` header and any `RetryInfo.retryDelay` in the body. Returns
    /// nil when the server gave no hint, so the caller falls back to backoff.
    private func serverRetryHint(response: HTTPResponse, envelope: GoogleErrorEnvelope?) -> TimeInterval? {
        let header = TimeInterval(response.value(forHeader: "Retry-After") ?? "")
        let body = envelope?.retryDelaySeconds
        let hints = [header, body].compactMap { $0 }
        return hints.max()
    }

    func error(from response: HTTPResponse, envelope: GoogleErrorEnvelope? = nil) -> GrahamError {
        if let envelope = envelope
            ?? (try? GoogleJSON.decoder.decode(GoogleErrorEnvelope.self, from: response.body)) {
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
