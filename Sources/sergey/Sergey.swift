import ArgumentParser
import Foundation
import SergeyKit

@main
struct Sergey: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sergey",
        abstract: "A command-line tool for Google Drive, Docs, Sheets, and Slides.",
        version: "0.1.0",
        subcommands: [Auth.self, Drive.self, Sheets.self, Docs.self, Slides.self]
    )
}

extension OutputFormat: ExpressibleByArgument {}
