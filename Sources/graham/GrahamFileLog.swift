import FellerBuncher
import Foundation
import Logging

/// Routes graham's log lines to rotating files in `~/Library/Logs/graham/`, in
/// addition to the live stderr lines the CLI already prints. If file logging
/// cannot start, the tool still runs — it just notes the problem once on
/// stderr and returns nil, so every call site guards with `logging?.`.
///
/// This mirrors easel's `EaselLog`. graham's library stays print-free behind
/// the `GrahamLog` seam; only this executable installs the FellerBuncher
/// backend, and `CLI.installLogHandler` forwards each seam line into a
/// swift-log `Logger` that FellerBuncher writes to the file.
enum GrahamFileLog {
    /// Starts file logging, except for a `graham ro` run, which writes no file
    /// at all: it never opens the log directory, not even to prune it. Its log
    /// lines still reach stderr through `CLI.installLogHandler`.
    static func bootstrapIfAllowed(arguments: [String]) -> LoggingHandle? {
        guard !ReadOnly.isInvoked(by: arguments) else {
            // With no backend installed, swift-log's default handler would
            // print every line a second time; route the logger to nothing.
            LoggingSystem.bootstrap { _ in SwiftLogNoOpLogHandler() }
            return nil
        }
        return bootstrapIfPossible()
    }

    static func bootstrapIfPossible() -> LoggingHandle? {
        do {
            let logDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/graham", isDirectory: true)
            return try bootstrap(
                processName: "graham",
                logDir: logDir,
                console: .none,
                minimumLevel: .debug
            )
        } catch {
            FileHandle.standardError.write(Data("graham: file logging unavailable: \(error)\n".utf8))
            return nil
        }
    }
}
