import XCTest
@testable import GrahamKit

final class GoogleAPITests: XCTestCase {
    private let fileURL = URL(string: "https://www.googleapis.com/drive/v3/files/f1")!
    private let fileJSON = #"{"id":"f1","name":"Report"}"#

    func testAddsAuthAndAcceptHeaders() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint(accessToken: "abc")
        transport.stub(urlContains: "/files/f1", json: fileJSON)
        let api = TestSupport.makeAPI(transport: transport)

        _ = try await api.getJSON(DriveFile.self, from: fileURL)

        let request = try XCTUnwrap(transport.requests(urlContains: "/files/f1").first)
        XCTAssertEqual(request.headers["Authorization"], "Bearer abc")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    func testRefreshesTheTokenOn401AndRetriesOnce() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json(#"{"error":{"code":401,"message":"expired","status":"UNAUTHENTICATED"}}"#, status: 401),
            StubTransport.json(fileJSON),
        ])
        let api = TestSupport.makeAPI(transport: transport)

        let file = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 2)
        // One refresh at the start, and one more after the 401.
        XCTAssertEqual(transport.requests(urlContains: "oauth2.googleapis.com/token").count, 2)
    }

    func testDoesNotLoopOnRepeated401() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(
            urlContains: "/files/f1",
            json: #"{"error":{"code":401,"message":"nope","status":"UNAUTHENTICATED"}}"#,
            status: 401
        )
        let api = TestSupport.makeAPI(transport: transport)

        do {
            _ = try await api.getJSON(DriveFile.self, from: fileURL)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, _, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 401)
        }
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 2)
    }

    func testHonorsRetryAfterOn429() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            HTTPResponse(statusCode: 429, headers: ["Retry-After": "7"], body: Data()),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        let file = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(recorder.delays, [7])
    }

    func testHonorsRetryInfoDelayOn429() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        let body = """
            {"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"Quota exceeded",\
            "details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"30s"}]}}
            """
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json(body, status: 429),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        let file = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(file.id, "f1")
        // The 30s RetryInfo hint beats the 1s exponential backoff floor.
        XCTAssertEqual(recorder.delays, [30])
    }

    func testLogsResponseHeadersWhenNoRetryHint() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            HTTPResponse(
                statusCode: 429,
                headers: ["Content-Type": "application/json", "X-RateLimit-Scope": "write-per-minute"],
                body: Data(#"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"Quota exceeded"}}"#.utf8)
            ),
            StubTransport.json(fileJSON),
        ])
        let recorder = LogRecorder()
        let previous = GrahamLog.handler
        GrahamLog.handler = { recorder.record($0) }
        defer { GrahamLog.handler = previous }
        let api = TestSupport.makeAPI(transport: transport) { _ in }

        let file = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(file.id, "f1")
        let dump = try XCTUnwrap(
            recorder.lines.first { $0.contains("Response headers:") },
            "Expected a header dump when no retry hint was found. Lines: \(recorder.lines)"
        )
        // The raw headers and body are both present, so a later look can spot a
        // hint we failed to parse.
        XCTAssertTrue(dump.contains("X-RateLimit-Scope: write-per-minute"), "Missing headers in: \(dump)")
        XCTAssertTrue(dump.contains("Content-Type: application/json"), "Missing headers in: \(dump)")
        XCTAssertTrue(dump.contains("RESOURCE_EXHAUSTED"), "Missing body in: \(dump)")
    }

    func testDoesNotDumpHeadersWhenServerGaveARetryHint() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            HTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "3", "X-RateLimit-Scope": "write-per-minute"],
                body: Data()
            ),
            StubTransport.json(fileJSON),
        ])
        let recorder = LogRecorder()
        let previous = GrahamLog.handler
        GrahamLog.handler = { recorder.record($0) }
        defer { GrahamLog.handler = previous }
        let api = TestSupport.makeAPI(transport: transport) { _ in }

        _ = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertFalse(
            recorder.lines.contains { $0.contains("Response headers:") },
            "A parsed hint needs no diagnostic dump. Lines: \(recorder.lines)"
        )
    }

    func testHonorsRetryInfoDelayWithFractionalSeconds() {
        XCTAssertEqual(GoogleErrorEnvelope.parseDuration("1.500s"), 1.5)
        XCTAssertEqual(GoogleErrorEnvelope.parseDuration("42s"), 42)
        XCTAssertNil(GoogleErrorEnvelope.parseDuration("nonsense"))
    }

    // MARK: - Quota-window rate limit (ErrorInfo, no RetryInfo)

    /// A realistic Slides per-minute write-quota 429: an `ErrorInfo` names the
    /// window, but the reply carries no `RetryInfo` and no `Retry-After`
    /// header. `window_start_time` is the epoch second the one-minute window
    /// opened, so the window resets at `windowStart + 60`.
    private func quotaWindowBody(windowStart: Int) -> String {
        """
        {"error":{"code":429,"status":"RESOURCE_EXHAUSTED",\
        "message":"Quota exceeded for quota metric 'Write requests' and limit \
        'Write requests per minute per user' of service 'slides.googleapis.com'.",\
        "details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo",\
        "reason":"RATE_LIMIT_EXCEEDED","domain":"googleapis.com","metadata":{\
        "quota_limit":"WriteRequestsPerMinutePerUser",\
        "service":"slides.googleapis.com",\
        "quota_unit":"1/min/{project}/{user}",\
        "window_start_time":"\(windowStart)",\
        "quota_limit_value":"60",\
        "quota_metric":"slides.googleapis.com/write_requests"}}]}}
        """
    }

    func testHonorsQuotaWindowFromErrorInfoWhenServerGaveNoOtherHint() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        // The window opened at 1787693188, so the one-minute window resets at
        // 1787693248. The server's own Date header reads 1787693230, leaving
        // 18s in the window; the client adds a 1s buffer to land past the reset.
        transport.stub(urlContains: "/files/f1", responses: [
            HTTPResponse(
                statusCode: 429,
                headers: ["Date": "Tue, 25 Aug 2026 21:27:10 GMT"],
                body: Data(quotaWindowBody(windowStart: 1787693188).utf8)
            ),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        let file = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(file.id, "f1")
        // The 19s window wait beats the 1s exponential-backoff floor.
        XCTAssertEqual(recorder.delays, [19])
    }

    func testWaitsTheFullQuotaWindowWhenNoServerClock() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        // With no Date header the client cannot measure the window, so it waits
        // the whole minute (plus buffer), which always outlasts the window.
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json(quotaWindowBody(windowStart: 1787693188), status: 429),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        _ = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(recorder.delays, [61])
    }

    func testDoesNotWaitOutADailyQuotaWindow() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        let body = """
            {"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"Daily limit exceeded",\
            "details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo",\
            "reason":"RATE_LIMIT_EXCEEDED","metadata":{\
            "quota_unit":"1/d/{project}","window_start_time":"1787693188"}}]}}
            """
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json(body, status: 429),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        _ = try await api.getJSON(DriveFile.self, from: fileURL)

        // A per-day quota will not clear inside a CLI run, so it is not waited
        // out: the client falls back to the 1s exponential-backoff floor.
        XCTAssertEqual(recorder.delays, [1])
    }

    func testWindowSecondsMapsOnlyShortQuotaUnits() {
        XCTAssertEqual(GoogleErrorEnvelope.windowSeconds(forQuotaUnit: "1/min/{project}/{user}"), 60)
        XCTAssertEqual(GoogleErrorEnvelope.windowSeconds(forQuotaUnit: "1/s/{project}"), 1)
        XCTAssertNil(GoogleErrorEnvelope.windowSeconds(forQuotaUnit: "1/h/{project}"))
        XCTAssertNil(GoogleErrorEnvelope.windowSeconds(forQuotaUnit: "1/d/{project}"))
        XCTAssertNil(GoogleErrorEnvelope.windowSeconds(forQuotaUnit: "garbage"))
    }

    func testQuotaWindowRetrySecondsComputesRemainingTime() throws {
        let envelope = try GoogleJSON.decoder.decode(
            GoogleErrorEnvelope.self,
            from: Data(quotaWindowBody(windowStart: 1787693188).utf8)
        )
        // 1787693188 window start + 60s window - 1787693230 now = 18s left, +1s buffer.
        XCTAssertEqual(envelope.quotaWindowRetrySeconds(serverNow: 1787693230), 19)
        // No clock: fall back to the full window plus buffer.
        XCTAssertEqual(envelope.quotaWindowRetrySeconds(serverNow: nil), 61)
    }

    func testQuotaWindowRetrySecondsIsNilWithoutQuotaMetadata() throws {
        let body = #"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"x"}}"#
        let envelope = try GoogleJSON.decoder.decode(GoogleErrorEnvelope.self, from: Data(body.utf8))
        XCTAssertNil(envelope.quotaWindowRetrySeconds(serverNow: 1787693230))
    }

    func testServerEpochParsesTheHTTPDateHeader() {
        let response = HTTPResponse(
            statusCode: 429,
            headers: ["Date": "Tue, 25 Aug 2026 21:27:10 GMT"]
        )
        XCTAssertEqual(GoogleAPI.serverEpoch(from: response), 1787693230)
        // No header, no clock.
        XCTAssertNil(GoogleAPI.serverEpoch(from: HTTPResponse(statusCode: 429)))
    }

    func testRetriesOn403RateLimitEnvelope() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        let body = #"{"error":{"code":403,"status":"rateLimitExceeded","message":"Rate limit exceeded"}}"#
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json(body, status: 403),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        let file = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(recorder.delays, [1])
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 2)
    }

    func testDoesNotRetryNonRateLimit403() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(
            urlContains: "/files/f1",
            json: #"{"error":{"code":403,"message":"No permission.","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        do {
            _ = try await api.getJSON(DriveFile.self, from: fileURL)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, _, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 403)
        }
        // A permission 403 is terminal: no retry and no backoff.
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 1)
        XCTAssertEqual(recorder.delays, [])
    }

    func testUsesExponentialBackoffOn5xx() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json("oops", status: 500),
            StubTransport.json("oops", status: 503),
            StubTransport.json(fileJSON),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        _ = try await api.getJSON(DriveFile.self, from: fileURL)

        XCTAssertEqual(recorder.delays, [1, 2])
    }

    func testGivesUpAfterMaxRetries() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", json: "oops", status: 500)
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        do {
            _ = try await api.getJSON(DriveFile.self, from: fileURL)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.httpError(let statusCode, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(statusCode, 500)
        }
        // The first try plus three retries.
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 4)
        XCTAssertEqual(recorder.delays, [1, 2, 4])
    }

    func testMapsTheGoogleErrorEnvelope() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(
            urlContains: "/files/f1",
            json: #"{"error":{"code":403,"message":"The user does not have permission.","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )
        let api = TestSupport.makeAPI(transport: transport)

        do {
            _ = try await api.getJSON(DriveFile.self, from: fileURL)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 403)
            XCTAssertEqual(status, "PERMISSION_DENIED")
            XCTAssertEqual(message, "The user does not have permission.")
        }
    }

    func testDecodeErrorNamesTheFieldPath() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        // "id" is required by the model but missing here.
        transport.stub(urlContains: "/files/f1", json: #"{"name":"Report"}"#)
        let api = TestSupport.makeAPI(transport: transport)

        do {
            _ = try await api.getJSON(DriveFile.self, from: fileURL)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.decodeError(let detail) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("id"), "Detail should name the missing key: \(detail)")
        }
    }

    // MARK: - No-content path (sendNoContent)

    func testSendNoContentSucceedsOnAnEmpty204() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint(accessToken: "abc")
        transport.stub(urlContains: "/files/f1", responses: [
            HTTPResponse(statusCode: 204, body: Data()),
        ])
        let api = TestSupport.makeAPI(transport: transport)

        try await api.sendNoContent(method: "DELETE", url: fileURL)

        let request = try XCTUnwrap(transport.requests(urlContains: "/files/f1").first)
        // The method is carried through, and the auth header is still attached.
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.headers["Authorization"], "Bearer abc")
    }

    func testSendNoContentRefreshesTheTokenOn401AndRetriesOnce() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json(#"{"error":{"code":401,"message":"expired","status":"UNAUTHENTICATED"}}"#, status: 401),
            HTTPResponse(statusCode: 204, body: Data()),
        ])
        let api = TestSupport.makeAPI(transport: transport)

        try await api.sendNoContent(method: "DELETE", url: fileURL)

        // One try, one retry after the 401; one token refresh at the start and
        // one more after the 401.
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 2)
        XCTAssertEqual(transport.requests(urlContains: "oauth2.googleapis.com/token").count, 2)
    }

    func testSendNoContentRetriesOn5xx() async throws {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(urlContains: "/files/f1", responses: [
            StubTransport.json("oops", status: 500),
            HTTPResponse(statusCode: 204, body: Data()),
        ])
        let recorder = SleepRecorder()
        let api = TestSupport.makeAPI(transport: transport) { recorder.record($0) }

        try await api.sendNoContent(method: "DELETE", url: fileURL)

        XCTAssertEqual(recorder.delays, [1])
        XCTAssertEqual(transport.requests(urlContains: "/files/f1").count, 2)
    }

    func testSendNoContentPropagatesTheGoogleError() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(
            urlContains: "/files/f1",
            json: #"{"error":{"code":403,"message":"The user does not have permission.","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )
        let api = TestSupport.makeAPI(transport: transport)

        do {
            try await api.sendNoContent(method: "DELETE", url: fileURL)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 403)
            XCTAssertEqual(status, "PERMISSION_DENIED")
        }
    }
}

/// Records backoff delays from the injected sleep closure.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(delay)
    }
}

/// Captures `GrahamLog` output so a test can assert on the logged lines.
final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(line)
    }
}
