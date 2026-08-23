import ArgumentParser
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
}

extension OutputFormat: ExpressibleByArgument {}
