import Foundation
import Network

/// A minimal HTTP listener on 127.0.0.1 for the OAuth loopback redirect.
///
/// Google removed the out-of-band (`oob`) flow, so desktop apps must receive
/// the authorization code on a local loopback port.
final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "graham.loopback")
    private var callbackContinuation: CheckedContinuation<[String: String], Error>?

    /// Starts the listener on an ephemeral port and returns that port.
    func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                semaphore.signal()
            case .failed(let error):
                startError = error
                semaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw GrahamError.oauthError("The local callback server did not start in 10 seconds.")
        }
        if let startError {
            throw GrahamError.oauthError("The local callback server failed: \(startError)")
        }
        guard let port = listener.port?.rawValue else {
            throw GrahamError.oauthError("The local callback server has no port.")
        }
        return port
    }

    /// Waits until the browser redirect delivers query parameters that contain
    /// `code` or `error`.
    func waitForCallback(timeout: TimeInterval = 300) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.callbackContinuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let waiting = self.callbackContinuation {
                        self.callbackContinuation = nil
                        waiting.resume(throwing: GrahamError.oauthError(
                            "No OAuth callback arrived in \(Int(timeout)) seconds."
                        ))
                    }
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let query = Self.parseQuery(fromRequest: request)
            let html = "<html><body><p>Login complete. You can close this window "
                + "and go back to the terminal.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: text/html\r\n"
                + "Content-Length: \(html.utf8.count)\r\n"
                + "Connection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            // Browsers also request /favicon.ico. Only the real redirect has
            // a code or an error parameter.
            if query["code"] != nil || query["error"] != nil, let waiting = self.callbackContinuation {
                self.callbackContinuation = nil
                waiting.resume(returning: query)
            }
        }
    }

    /// Parses the query parameters from the first line of an HTTP request,
    /// for example: `GET /?code=abc&state=xyz HTTP/1.1`.
    static func parseQuery(fromRequest request: String) -> [String: String] {
        guard let firstLine = request.split(separator: "\r\n").first else { return [:] }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return [:] }
        let target = String(parts[1])
        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else { return [:] }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value
        }
        return query
    }
}
