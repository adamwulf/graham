import ArgumentParser
import Foundation
import SergeyKit

struct Slides: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Slides presentations.",
        subcommands: [Cat.self]
    )

    struct Cat: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the text of each slide in a presentation."
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Flag(help: "Print the decoded presentation as JSON instead of plain text.")
        var json = false

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            let presentation = try await client.presentation(id: presentationID)
            if json {
                try CLI.printJSON(presentation)
                return
            }
            if let title = presentation.title {
                print("# \(title)\n")
            }
            for (index, slide) in (presentation.slides ?? []).enumerated() {
                print("-- Slide \(index + 1) --")
                let text = slide.plainText
                if !text.isEmpty {
                    print(text)
                }
                print("")
            }
        }
    }
}
