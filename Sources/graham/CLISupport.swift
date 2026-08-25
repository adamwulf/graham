import Foundation
import GrahamKit
import Logging

/// Shared wiring for all commands.
enum CLI {
    /// The swift-log logger the file backend (FellerBuncher) captures. It is a
    /// lazy static so it binds to whatever `LoggingSystem` backend is installed
    /// when it is first used; `Graham.main` bootstraps FellerBuncher before the
    /// first `installLogHandler` call, so seam lines land in the log file.
    private static let logger = Logger(label: "graham.api")

    /// Builds the API executor: resolve credentials once, then share one
    /// transport and one token provider.
    static func makeAPI() throws -> GoogleAPI {
        let credentials = try CredentialsResolver.resolve()
        let transport = URLSessionTransport()
        let tokenProvider = OAuthTokenProvider(credentials: credentials, transport: transport)
        installLogHandler()
        return GoogleAPI(tokenProvider: tokenProvider, transport: transport)
    }

    /// Sends library log lines (retries, token refreshes) to two sinks: stderr,
    /// so the user sees them live without polluting stdout, and a swift-log
    /// logger the FellerBuncher backend persists to `~/Library/Logs/graham/`.
    static func installLogHandler() {
        GrahamLog.handler = { message in
            FileHandle.standardError.write(Data("graham: \(message)\n".utf8))
            logger.notice("\(message)")
        }
    }

    /// Prints a pretty JSON dump of one model.
    static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try GoogleJSON.prettyEncoder.encode(value)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}
