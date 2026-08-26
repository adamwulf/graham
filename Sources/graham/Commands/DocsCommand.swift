import ArgumentParser
import Foundation
import GrahamKit

struct Docs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Docs documents.",
        subcommands: [Create.self, Cat.self, Insert.self, Delete.self, Replace.self]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new, blank document from a title and print its id."
        )

        @Argument(help: "The title of the new document.")
        var title: String

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let document = try await client.create(title: title)
            print(document.documentId ?? "")
        }
    }

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

    struct Insert: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Insert text at a document index.",
            discussion: """
                The index is zero-based, in UTF-16 code units, exactly as the
                Docs API defines it. Index 1 is the start of the body text.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The text to insert.")
        var text: String

        @Option(help: "The zero-based UTF-16 index to insert at (minimum 1; the body starts at 1).")
        var at: Int

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.insertText(documentId: documentID, text: text, index: at)
            print("Inserted \(text.utf16.count) UTF-16 code units at index \(at).")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a range of content.",
            discussion: """
                Both indices are zero-based, in UTF-16 code units. The range is
                half-open: content from --from up to but not including --to is
                deleted.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 start index (inclusive; minimum 1; the body starts at 1).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.deleteContentRange(
                documentId: documentID,
                startIndex: from,
                endIndex: to
            )
            print("Deleted content in [\(from), \(to)).")
        }
    }

    struct Replace: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace all matches of a string and print the count."
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The text to find.")
        var find: String

        @Option(help: "The replacement text.")
        var replace: String

        @Flag(help: "Match case exactly (default is case-insensitive).")
        var matchCase = false

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let count = try await client.replaceAllText(
                documentId: documentID,
                find: find,
                replace: replace,
                matchCase: matchCase
            )
            print(count)
        }
    }
}
