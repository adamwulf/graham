import ArgumentParser
import Foundation
import GrahamKit

struct Docs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Docs documents.",
        subcommands: [Cat.self]
    )

    struct Cat: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the text of a document."
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Flag(help: "Print the decoded document as JSON instead of plain text.")
        var json = false

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let document = try await client.document(id: documentID)
            if json {
                try CLI.printJSON(document)
                return
            }
            print(document.plainText, terminator: "")
        }
    }
}
