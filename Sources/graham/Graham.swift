import ArgumentParser
import FellerBuncher
import Foundation
import GrahamKit

@main
struct Graham: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "graham",
        abstract: "A command-line tool for Google Drive, Docs, Sheets, and Slides.",
        version: "0.1.0",
        subcommands: [Auth.self, Drive.self, Sheets.self, Docs.self, Slides.self]
    )

    /// Start file logging before anything runs, then drain the buffered log on
    /// the way out of BOTH the success and error paths — the CLI is short-lived,
    /// so an un-drained tail would be lost.
    static func main() async {
        let logging = GrahamFileLog.bootstrapIfPossible()
        CLI.installLogHandler()
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            await logging?.drain()
        } catch {
            await logging?.drain()
            exit(withError: error)
        }
    }
}

extension OutputFormat: ExpressibleByArgument {}
extension DriveFileType: ExpressibleByArgument {}

extension VideoSource: UppercasedRawArgument {}
extension LineCategory: UppercasedRawArgument {}
