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
            abstract: "Insert text at a document index, or at the end of a segment.",
            discussion: """
                The index is zero-based, in UTF-16 code units, exactly as the
                Docs API defines it. Index 1 is the start of the body text. In a
                named segment (--segment) the content starts at index 0. Pass
                --end to append to the end of the body or segment without an
                index; --at is not needed then.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The text to insert.")
        var text: String

        @Option(help: "The zero-based UTF-16 index to insert at (body minimum 1; segment minimum 0). Not needed with --end.")
        var at: Int?

        @Option(help: "A header, footer, or footnote segment id to insert into. Omit for the body.")
        var segment: String?

        @Flag(help: "Append to the end of the body or segment; --at is ignored.")
        var end = false

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            if end && at != nil {
                throw ValidationError(
                    "Pass either --at <index> or --end, not both: --end appends to the "
                    + "end of the segment and takes no index.")
            }
            guard end || at != nil else {
                throw ValidationError(
                    "Provide --at <index>, or pass --end to append to the end of the segment.")
            }
        }

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.insertText(
                documentId: documentID, text: text, index: at ?? 0,
                segmentId: segment, endOfSegment: end,
                requiredRevisionId: requireRevision)
            let count = text.utf16.count
            if end {
                let destination = segment.map { "the end of segment \($0)" } ?? "the end of the body"
                print("Inserted \(count) UTF-16 code units at \(destination).")
            } else {
                print("Inserted \(count) UTF-16 code units at index \(at ?? 0).")
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a range of content.",
            discussion: """
                Both indices are zero-based, in UTF-16 code units. The range is
                half-open: content from --from up to but not including --to is
                deleted. In a named segment (--segment) the content starts at
                index 0; the body starts at 1.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 start index (inclusive; body minimum 1; segment minimum 0).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        @Option(help: "A header, footer, or footnote segment id to delete from. Omit for the body.")
        var segment: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.deleteContentRange(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                segmentId: segment,
                requiredRevisionId: requireRevision
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

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let count = try await client.replaceAllText(
                documentId: documentID,
                find: find,
                replace: replace,
                matchCase: matchCase,
                requiredRevisionId: requireRevision
            )
            print(count)
        }
    }
}
