import ArgumentParser
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

    /// Returns the timestamp label shared by all three live-test runners.
    static func iso8601Label(now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: now)
    }

    /// Builds the service-independent live-test step printer.
    static func liveTestStepHandler<Step: LiveTestStepReporting>(
        for _: Step.Type
    ) -> @Sendable (Step) -> Void {
        { step in
            let ids = step.createdIDs.isEmpty
                ? ""
                : " [\(step.createdIDs.joined(separator: ", "))]"
            switch step.reportOutcome {
            case .pass:
                print("\(StatusColor.green.wrap("PASS")) \(step.name)\(ids)")
            case .fail(let reason):
                print("\(StatusColor.red.wrap("FAIL")) \(step.name): \(reason)\(ids)")
            case .skip(let reason):
                print("\(StatusColor.yellow.wrap("SKIP")) \(step.name): \(reason)\(ids)")
            }
        }
    }

    /// Prints the shared live-test summary and preserves the nonzero failure exit.
    static func printLiveTestSummary<Summary: LiveTestSummaryReporting>(
        _ summary: Summary
    ) throws {
        print(
            "Summary: \(summary.passed) passed, \(summary.failed) failed, "
                + "\(summary.skipped) skipped"
        )
        if summary.failed > 0 {
            throw ExitCode.failure
        }
    }

    /// Prints image-download results, their shared tally, and returns failures.
    static func printImageDownloadReport<Outcome: ImageDownloadOutcomeReporting>(
        _ items: [(prefix: String, outcome: Outcome)],
        directory: URL
    ) -> Int {
        var downloaded = 0
        var failed = 0
        var totalBytes = 0
        for item in items {
            switch item.outcome.reportOutcome {
            case let .downloaded(filename, byteCount):
                downloaded += 1
                totalBytes += byteCount
                print("\(item.prefix)  downloaded  \(filename)  \(byteCount) bytes")
            case let .failed(reason):
                failed += 1
                print("\(item.prefix)  failed  \(reason)")
            case let .skipped(reason):
                print("\(item.prefix)  skipped  \(reason)")
            }
        }
        print(
            "Downloaded \(downloaded) of \(items.count) image(s), "
                + "\(totalBytes) bytes, into \(directory.path)"
        )
        return failed
    }
}

/// The service-independent form of one image-download outcome.
enum ImageDownloadReportOutcome {
    case downloaded(filename: String, byteCount: Int)
    case failed(reason: String)
    case skipped(reason: String)
}

/// An image-download outcome that the shared CLI reporter can render.
protocol ImageDownloadOutcomeReporting {
    var reportOutcome: ImageDownloadReportOutcome { get }
}

extension SlideImageDownloadOutcome: ImageDownloadOutcomeReporting {
    var reportOutcome: ImageDownloadReportOutcome {
        switch self {
        case let .downloaded(filename, byteCount):
            return .downloaded(filename: filename, byteCount: byteCount)
        case let .failed(reason):
            return .failed(reason: reason)
        case let .skipped(reason):
            return .skipped(reason: reason)
        }
    }
}

extension DocImageDownloadOutcome: ImageDownloadOutcomeReporting {
    var reportOutcome: ImageDownloadReportOutcome {
        switch self {
        case let .downloaded(filename, byteCount):
            return .downloaded(filename: filename, byteCount: byteCount)
        case let .failed(reason):
            return .failed(reason: reason)
        case let .skipped(reason):
            return .skipped(reason: reason)
        }
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
