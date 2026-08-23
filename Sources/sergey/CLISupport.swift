import Foundation
import SergeyKit

/// Shared wiring for all commands.
enum CLI {
    /// Builds the API executor: resolve credentials once, then share one
    /// transport and one token provider.
    static func makeAPI() throws -> GoogleAPI {
        let credentials = try CredentialsResolver.resolve()
        let transport = URLSessionTransport()
        let tokenProvider = OAuthTokenProvider(credentials: credentials, transport: transport)
        installLogHandler()
        return GoogleAPI(tokenProvider: tokenProvider, transport: transport)
    }

    /// Sends library log lines (retries, token refreshes) to stderr, so they
    /// do not mix with the command output on stdout.
    static func installLogHandler() {
        SergeyLog.handler = { message in
            FileHandle.standardError.write(Data("sergey: \(message)\n".utf8))
        }
    }

    /// Prints a pretty JSON dump of one model.
    static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try GoogleJSON.prettyEncoder.encode(value)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}
