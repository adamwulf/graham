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
///
/// Some quota limits carry no `RetryInfo` at all. Slides' per-minute *write*
/// quota returns a bare 429 whose only hint is a `google.rpc.ErrorInfo` naming
/// the quota window in its `metadata` — `quota_unit` (for example
/// `"1/min/{project}/{user}"`) and `window_start_time` (epoch seconds). The
/// window resets at `window_start_time + windowLength`, so the client can wait
/// out the time still left in the window instead of guessing with backoff.
struct GoogleErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: Int?
        let message: String?
        let status: String?
        let details: [ErrorDetail]?
    }

    /// One entry in `error.details`. Only the `@type` discriminator, the
    /// `RetryInfo.retryDelay`, and the `ErrorInfo` quota fields (`reason` plus
    /// the `metadata` map) are modelled; other detail payloads decode to nil.
    struct ErrorDetail: Decodable {
        let type: String?
        let retryDelay: String?
        let reason: String?
        let metadata: [String: String]?

        enum CodingKeys: String, CodingKey {
            case type = "@type"
            case retryDelay
            case reason
            case metadata
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

    /// The wait implied by a quota-window rate limit that carries a
    /// `google.rpc.ErrorInfo` but no `RetryInfo`. Slides' per-minute *write*
    /// quota returns exactly this: a bare 429 whose `ErrorInfo.metadata` names
    /// the window (`quota_unit`, for example `"1/min/{project}/{user}"`) and
    /// the window's start (`window_start_time`, epoch seconds). The window
    /// resets at `window_start_time + windowLength`, so this returns the time
    /// still left in the window.
    ///
    /// - Parameter serverNow: the server's clock in epoch seconds, read from
    ///   the `Date` response header, used to measure how much of the window is
    ///   left. When nil (no readable clock), the full window length is returned
    ///   instead — it always outlasts the window, whatever the clock skew.
    /// - Returns: the seconds to wait, or nil when the reply carries no quota
    ///   window, or names a window too long to wait out inside a CLI run (an
    ///   hourly or daily quota will not clear before the run ends).
    func quotaWindowRetrySeconds(serverNow: TimeInterval?) -> TimeInterval? {
        guard let details = error.details else { return nil }
        for detail in details {
            guard let metadata = detail.metadata,
                  let unit = metadata["quota_unit"],
                  let windowLength = Self.windowSeconds(forQuotaUnit: unit) else {
                continue
            }
            // Return the raw time left in the window. The caller adds a single
            // boundary buffer to whichever hint wins, so a coarse server clock
            // does not throttle the very first retry all over again — the
            // buffer lives in one place rather than in each hint source.
            if let serverNow,
               let startRaw = metadata["window_start_time"],
               let start = TimeInterval(startRaw) {
                let remaining = (start + windowLength) - serverNow
                return max(0, remaining)
            }
            return windowLength
        }
        return nil
    }

    /// Maps a Google `quota_unit` to the length of its window in seconds, for
    /// the short windows worth waiting out. The unit looks like
    /// `"1/min/{project}/{user}"`; its second `/`-separated segment names the
    /// period. Per-hour and per-day quotas return nil: they will not clear
    /// inside a CLI run, so the caller falls back to plain backoff and fails
    /// fast rather than blocking the process for hours.
    static func windowSeconds(forQuotaUnit unit: String) -> TimeInterval? {
        let segments = unit.split(separator: "/")
        guard segments.count >= 2 else { return nil }
        switch segments[1] {
        case "s": return 1
        case "min": return 60
        default: return nil
        }
    }
}

/// The low-level executor for all Google API requests.
///
/// This is the only place that:
/// - adds the `Authorization` header,
/// - refreshes the access token after a 401 (one time per request),
/// - retries rate-limit and transient errors (429, 5xx, and 403 rate-limit
///   envelopes) with exponential backoff, honoring the `Retry-After` header,
///   any `RetryInfo.retryDelay` the error body carries, and — when neither is
///   present — the quota window an `ErrorInfo` names (Slides' per-minute write
///   quota returns only this),
/// - decodes JSON and the Google error envelope.
///
/// The service clients (``DriveClient``, ``SheetsClient``, ``DocsClient``,
/// ``SlidesClient``) sit on top and hold the pagination and the endpoints.
public final class GoogleAPI: @unchecked Sendable {
    private let tokenProvider: OAuthTokenProvider
    private let transport: any HTTPTransport
    private let maxRetries: Int
    private let maxBackoff: TimeInterval = 60
    /// Added to a server-supplied wait so a retry lands just after Google's
    /// boundary, not just before it. A hint names the moment Google clears the
    /// quota window; waiting the exact amount risks retrying a hair too early
    /// (clock skew between our clock and Google's, network latency, sub-second
    /// rounding) and burning a retry on the same 429. One extra second lands us
    /// safely past the boundary. Pure backoff has no such boundary, so it gets
    /// no buffer.
    private let boundaryBuffer: TimeInterval = 1
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
            // Overshoot a server-supplied boundary by `boundaryBuffer`; pure
            // backoff has no boundary and keeps its bare schedule.
            let delay = max(backoff, serverHint.map { $0 + boundaryBuffer } ?? 0)
            let status = envelope?.error.status.map { " (\($0))" } ?? ""
            let hint = serverHint.map { String(format: "%.0fs", $0) } ?? "none"
            GrahamLog.log(
                "Got status \(response.statusCode)\(status). Server retry hint: \(hint). "
                + "Retrying in \(delay) seconds (attempt \(retryCount + 1) of \(maxRetries))."
            )
            // When no hint parsed, dump the raw reply so a later investigation
            // can see what the server actually sent — an unparsed `Retry-After`
            // date, a quota header, or a `RetryInfo` variant we do not model.
            if serverHint == nil {
                GrahamLog.log(
                    "No retry hint parsed; dumping the raw reply to diagnose. "
                    + "Response headers: \(Self.formatHeaders(response.headers)). "
                    + "Response body: \(Self.formatBody(response.body))."
                )
            }
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

    /// The wait the server explicitly asked for, taking the largest of three
    /// hints: the `Retry-After` header, any `RetryInfo.retryDelay` in the body,
    /// and the time left in the quota window an `ErrorInfo` names (measured
    /// against the server's own `Date` header). Returns nil when the server
    /// gave no hint, so the caller falls back to backoff.
    private func serverRetryHint(response: HTTPResponse, envelope: GoogleErrorEnvelope?) -> TimeInterval? {
        let header = TimeInterval(response.value(forHeader: "Retry-After") ?? "")
        let body = envelope?.retryDelaySeconds
        let window = envelope?.quotaWindowRetrySeconds(serverNow: Self.serverEpoch(from: response))
        let hints = [header, body, window].compactMap { $0 }
        return hints.max()
    }

    /// The server's clock in epoch seconds, parsed from the RFC 7231 `Date`
    /// response header (for example `"Tue, 25 Aug 2026 21:27:10 GMT"`). Used to
    /// measure how much of a quota window is still left, so the wait does not
    /// depend on the local clock. Returns nil when the header is absent or
    /// unparseable.
    static func serverEpoch(from response: HTTPResponse) -> TimeInterval? {
        guard let raw = response.value(forHeader: "Date") else { return nil }
        return httpDateFormatter.date(from: raw)?.timeIntervalSince1970
    }

    /// Parses an RFC 7231 IMF-fixdate. Fixed to `en_US_POSIX` and GMT so it
    /// never drifts with the machine's locale or time zone.
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// Renders response headers on one line for diagnostic logging: names
    /// sorted case-insensitively, joined as `name: value` pairs. Used when a
    /// retryable reply carries no parseable retry hint, so a later look can see
    /// exactly what the server sent (an unparsed `Retry-After` date, a quota
    /// header, ...). Response headers hold no bearer token, so this is safe.
    static func formatHeaders(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "(none)" }
        return headers
            .sorted { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "; ")
    }

    /// A compact, single-line rendering of a diagnostic response body,
    /// truncated so a large reply cannot flood the log. A `RetryInfo` variant
    /// we do not model would show up here.
    static func formatBody(_ body: Data, limit: Int = 2000) -> String {
        guard !body.isEmpty else { return "(empty)" }
        guard let text = String(data: body, encoding: .utf8) else {
            return "(\(body.count) non-UTF-8 bytes)"
        }
        let collapsed = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…(truncated)" : collapsed
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
