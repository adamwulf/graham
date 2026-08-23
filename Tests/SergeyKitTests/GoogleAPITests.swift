import XCTest
@testable import SergeyKit

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
            guard case SergeyError.googleAPIError(let code, _, _) = error else {
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
            guard case SergeyError.httpError(let statusCode, _) = error else {
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
            guard case SergeyError.googleAPIError(let code, let status, let message) = error else {
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
            guard case SergeyError.decodeError(let detail) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("id"), "Detail should name the missing key: \(detail)")
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
