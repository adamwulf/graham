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
        // `ro` goes LAST: a static lookup by type (such as `helpMessage(for:)`)
        // finds the first parent, so a leaf shared with `ro` reports its
        // top-level path.
        subcommands: [Auth.self, Drive.self, Sheets.self, Docs.self, Slides.self, ReadOnly.self]
    )

    /// Start file logging before anything runs, then drain the buffered log on
    /// the way out of BOTH the success and error paths — the CLI is short-lived,
    /// so an un-drained tail would be lost. A `graham ro` run writes no log file.
    static func main() async {
        let logging = GrahamFileLog.bootstrapIfAllowed(arguments: CommandLine.arguments)
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
extension DriveConvertType: ExpressibleByArgument {}
extension DriveExportFormat: ExpressibleByArgument {}

extension VideoSource: UppercasedRawArgument {}
extension LineCategory: UppercasedRawArgument {}
