import ArgumentParser
import Foundation
import GrahamKit

struct Docs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Docs documents.",
        subcommands: [Create.self, Cat.self, Structure.self, Insert.self, Delete.self, Replace.self, Images.self]
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
            abstract: "Print the text of a document.",
            discussion: """
                By default the body text is printed as-is. Pass --markdown to \
                render the document as GitHub-flavored Markdown (headings, bold / \
                italic / strikethrough, links, lists, tables, horizontal rules, \
                page-break markers, footnotes, and inline images), or --json for \
                the full decoded document. --markdown and --json are mutually \
                exclusive.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Flag(help: "Print the decoded document as JSON instead of plain text.")
        var json = false

        @Flag(help: "Render the document as Markdown instead of plain text.")
        var markdown = false

        func validate() throws {
            if json && markdown {
                throw ValidationError(
                    "Pass either --json or --markdown, not both: --json prints the "
                    + "decoded document and --markdown renders it as Markdown.")
            }
        }

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let document = try await client.document(id: documentID)
            if json {
                try CLI.printJSON(document)
                return
            }
            if markdown {
                print(document.markdown)
                return
            }
            print(document.plainText, terminator: "")
        }
    }

    struct Structure: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List the document's blocks with their index ranges.",
            discussion: """
                Each row is one structural block: its zero-based UTF-16 index \
                range, kind (paragraph, heading, list item, table, section \
                break, or table of contents), named style, list id and nesting, \
                referenced object ids, and a short text preview. A table is \
                listed first, then the blocks inside its cells indented under \
                it. The indices are shown exactly as the API reports them — they \
                are the values the range-based write commands (docs insert, \
                docs delete) consume. Use --format json for the full detail.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The output format: table, json, jsonl, or id.")
        var format: OutputFormat = .table

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let document = try await client.document(id: documentID)
            print(try OutputFormatter.render(document.blockRows, format: format))
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

    struct Images: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List every image in a document, or download them.",
            discussion: """
                Lists each inline and positioned image with its origin, object \
                id, size, source URI, and content URI. With --download DIR, \
                every image's content URI is fetched into DIR under a safe, \
                deterministic name; the directory is created if needed and a \
                report of what was written is printed. A content URI is \
                short-lived and pre-authorized, so it is fetched with a plain \
                GET and no OAuth header.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(
            name: [.customShort("d"), .long],
            help: "Download every image into this directory instead of listing."
        )
        var download: String?

        @Option(help: "The output format for listing: table, json, jsonl, or id.")
        var format: OutputFormat = .table

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let document = try await client.document(id: documentID)
            let images = document.imageRows

            guard let download else {
                print(try OutputFormatter.render(images, format: format))
                return
            }

            let directory = URL(fileURLWithPath: download, isDirectory: true)
            let results = try await client.downloadImages(images, to: directory)
            let failures = report(results, directory: directory)
            // A partial run exits non-zero so a script can notice it.
            if failures > 0 {
                throw ExitCode.failure
            }
        }

        /// Prints one line per image and a summary, and returns how many
        /// downloads failed.
        private func report(_ results: [DocImageDownloadResult], directory: URL) -> Int {
            var downloaded = 0
            var failed = 0
            var totalBytes = 0
            for result in results {
                let object = result.objectId ?? "(no id)"
                let origin = result.origin.rawValue
                switch result.outcome {
                case let .downloaded(filename, byteCount):
                    downloaded += 1
                    totalBytes += byteCount
                    print("\(origin)  \(object)  downloaded  \(filename)  \(byteCount) bytes")
                case let .failed(reason):
                    failed += 1
                    print("\(origin)  \(object)  failed  \(reason)")
                case let .skipped(reason):
                    print("\(origin)  \(object)  skipped  \(reason)")
                }
            }
            print(
                "Downloaded \(downloaded) of \(results.count) image(s), "
                + "\(totalBytes) bytes, into \(directory.path)"
            )
            return failed
        }
    }
}
