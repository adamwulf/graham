import ArgumentParser
import Foundation
import GrahamKit

struct Slides: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Slides presentations.",
        subcommands: [Cat.self, List.self, Images.self, Add.self, Create.self, Move.self, Delete.self]
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

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a new slide and print its object id.",
            discussion: """
                Without --at, the slide is appended at the end. Positions are \
                one-based and match the slide numbers of `slides cat` and \
                `slides list`. The layout is a predefined layout name such as \
                BLANK, TITLE, TITLE_AND_BODY, or SECTION_HEADER; the name is \
                case-insensitive and accepts - for _.
                """
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Option(help: "The one-based position of the new slide; omit to append.")
        var at: Int?

        @Option(help: "The predefined layout of the new slide.")
        var layout: String = "BLANK"

        func validate() throws {
            if let at, at < 1 {
                throw ValidationError("--at must be 1 or greater.")
            }
        }

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            let objectId = try await client.createSlide(
                presentationId: presentationID, at: at, layout: layout)
            print(objectId)
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a page element on a slide.",
            subcommands: [Textbox.self]
        )

        struct Textbox: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "textbox",
                abstract: "Create a text box and print its object id.",
                discussion: """
                    Geometry is measured in points. Empty text creates an empty \
                    text box. Get slide ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the slide that will hold the text box.")
            var slideID: String

            @Option(help: "The initial text; empty creates an empty text box.")
            var text = ""

            @Option(parsing: .unconditional, help: "The horizontal position in points.")
            var x: Double = 50

            @Option(parsing: .unconditional, help: "The vertical position in points.")
            var y: Double = 50

            @Option(
                parsing: .unconditional,
                help: "The width in points; must be greater than zero."
            )
            var width: Double = 300

            @Option(
                parsing: .unconditional,
                help: "The height in points; must be greater than zero."
            )
            var height: Double = 50

            func validate() throws {
                if width <= 0 {
                    throw ValidationError("--width must be greater than zero.")
                }
                if height <= 0 {
                    throw ValidationError("--height must be greater than zero.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let objectId = try await client.createTextBox(
                    presentationId: presentationID,
                    slideId: slideID,
                    text: text,
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )
                print(objectId)
            }
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move one slide to a new position and print its id.",
            discussion: """
                --to is the one-based final position of the slide, matching \
                the slide numbers of `slides cat` and `slides list`. Moving a \
                slide to its current position is a no-op and sends no write.
                """
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Argument(help: "The object id of the slide to move.")
        var slideID: String

        @Option(help: "The one-based final position of the slide.")
        var to: Int

        func validate() throws {
            if to < 1 {
                throw ValidationError("--to must be 1 or greater.")
            }
        }

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            try await client.moveSlide(
                presentationId: presentationID, slideId: slideID, to: to)
            print(slideID)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete one slide by its exact object id and print the id.",
            discussion: """
                The id is sent exactly as given; nothing is inferred or \
                expanded. Get slide ids from `slides list --format json`.
                """
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Argument(help: "The object id of the slide to delete.")
        var slideID: String

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            try await client.deleteObject(
                presentationId: presentationID, objectId: slideID)
            print(slideID)
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
