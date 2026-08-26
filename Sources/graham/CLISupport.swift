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

/// ANSI colouring for a live-test status word: PASS green, SKIP yellow, FAIL
/// red. Only the leading status word is coloured; the rest of the line stays
/// plain. Colour is applied only when stdout is a terminal, so redirected or
/// piped output stays plain text. Shared by the `slides test` and `docs test`
/// commands.
enum StatusColor {
    case green, yellow, red

    private var code: String {
        switch self {
        case .green: return "32"
        case .yellow: return "33"
        case .red: return "31"
        }
    }

    private static let stdoutIsTerminal = isatty(STDOUT_FILENO) != 0

    func wrap(_ text: String) -> String {
        guard StatusColor.stdoutIsTerminal else { return text }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }
}
