import ArgumentParser
import Foundation
import GrahamKit

struct Slides: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Slides presentations.",
        subcommands: [Cat.self, List.self, Images.self]
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

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List every element on every slide, groups flattened.",
            discussion: """
                Each row is one page element: its slide, object id, type, \
                position and size (in points), a link count, and its text. A \
                group is listed first, then its children indented under it. Use \
                --format json for the full detail: the raw transform, every \
                hyperlink, the alt text, and image URLs.
                """
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Option(help: "The output format: table, json, jsonl, or id.")
        var format: OutputFormat = .table

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            let presentation = try await client.presentation(id: presentationID)
            print(try OutputFormatter.render(presentation.elementRows, format: format))
        }
    }

    struct Images: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List every image in a presentation, or download them.",
            discussion: """
                Lists each image (including images nested in groups) with its \
                slide, object id, alt text, source URL, and content URL. With \
                --download DIR, every image's content URL is fetched into DIR \
                under a safe, deterministic name; the directory is created if \
                needed and a report of what was written is printed.
                """
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Option(
            name: [.customShort("d"), .long],
            help: "Download every image into this directory instead of listing."
        )
        var download: String?

        @Option(help: "The output format for listing: table, json, jsonl, or id.")
        var format: OutputFormat = .table

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            let presentation = try await client.presentation(id: presentationID)
            let images = presentation.imageRows

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
        private func report(_ results: [SlideImageDownloadResult], directory: URL) -> Int {
            var downloaded = 0
            var failed = 0
            var totalBytes = 0
            for result in results {
                let element = result.objectId ?? "(no id)"
                let slide = "slide\(result.slideIndex + 1)"
                switch result.outcome {
                case let .downloaded(filename, byteCount):
                    downloaded += 1
                    totalBytes += byteCount
                    print("\(slide)  \(element)  downloaded  \(filename)  \(byteCount) bytes")
                case let .failed(reason):
                    failed += 1
                    print("\(slide)  \(element)  failed  \(reason)")
                case let .skipped(reason):
                    print("\(slide)  \(element)  skipped  \(reason)")
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
