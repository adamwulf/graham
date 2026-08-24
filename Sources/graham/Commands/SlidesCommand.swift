import ArgumentParser
import Foundation
import GrahamKit

struct Slides: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Slides presentations.",
        subcommands: [
            Cat.self, List.self, Images.self, Add.self, Create.self, Element.self,
            Group.self, Ungroup.self, Move.self, Delete.self,
        ]
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
            subcommands: [Textbox.self, Image.self, Video.self, Line.self, Table.self, Chart.self]
        )

        /// Optional placement and size shared by non-text-box element creation.
        struct GeometryOptions: ParsableArguments {
            @Option(parsing: .unconditional, help: "The horizontal position in points.")
            var x: Double?

            @Option(parsing: .unconditional, help: "The vertical position in points.")
            var y: Double?

            @Option(
                parsing: .unconditional,
                help: "The width in points; provide it with --height."
            )
            var width: Double?

            @Option(
                parsing: .unconditional,
                help: "The height in points; provide it with --width."
            )
            var height: Double?

            func validate() throws {
                if (width == nil) != (height == nil) {
                    throw ValidationError("--width and --height must be provided together.")
                }
                if let width, !(width > 0) {
                    throw ValidationError("--width must be greater than zero.")
                }
                if let height, !(height > 0) {
                    throw ValidationError("--height must be greater than zero.")
                }
            }
        }

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

        struct Image: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create an image and print its object id.",
                discussion: """
                    Optional geometry is measured in points. Get slide ids \
                    from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the slide that will hold the image.")
            var slideID: String

            @Option(help: "The public URL of the image.")
            var url: String

            @OptionGroup
            var geometry: GeometryOptions

            func validate() throws {
                try geometry.validate()
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let objectId = try await client.createImage(
                    presentationId: presentationID,
                    slideId: slideID,
                    url: url,
                    x: geometry.x,
                    y: geometry.y,
                    width: geometry.width,
                    height: geometry.height
                )
                print(objectId)
            }
        }

        struct Video: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a video and print its object id.",
                discussion: """
                    Optional geometry is measured in points. Get slide ids \
                    from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the slide that will hold the video.")
            var slideID: String

            @Option(name: .customLong("id"), help: "The YouTube or Drive video ID.")
            var id: String

            @Option(help: "The video source: youtube or drive.")
            var source: VideoSource = .youtube

            @OptionGroup
            var geometry: GeometryOptions

            func validate() throws {
                try geometry.validate()
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let objectId = try await client.createVideo(
                    presentationId: presentationID,
                    slideId: slideID,
                    source: source,
                    videoId: id,
                    x: geometry.x,
                    y: geometry.y,
                    width: geometry.width,
                    height: geometry.height
                )
                print(objectId)
            }
        }

        struct Line: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a line and print its object id.",
                discussion: """
                    Optional geometry is measured in points. Get slide ids \
                    from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the slide that will hold the line.")
            var slideID: String

            @Option(help: "The line category: straight, bent, or curved.")
            var category: LineCategory = .straight

            @OptionGroup
            var geometry: GeometryOptions

            func validate() throws {
                try geometry.validate()
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let objectId = try await client.createLine(
                    presentationId: presentationID,
                    slideId: slideID,
                    category: category,
                    x: geometry.x,
                    y: geometry.y,
                    width: geometry.width,
                    height: geometry.height
                )
                print(objectId)
            }
        }

        struct Table: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a table and print its object id.",
                discussion: """
                    Optional geometry is measured in points. Get slide ids \
                    from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the slide that will hold the table.")
            var slideID: String

            @Option(help: "The number of rows; must be 1 or greater.")
            var rows: Int

            @Option(help: "The number of columns; must be 1 or greater.")
            var columns: Int

            @OptionGroup
            var geometry: GeometryOptions

            func validate() throws {
                try geometry.validate()
                if rows < 1 {
                    throw ValidationError("--rows must be 1 or greater.")
                }
                if columns < 1 {
                    throw ValidationError("--columns must be 1 or greater.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let objectId = try await client.createTable(
                    presentationId: presentationID,
                    slideId: slideID,
                    rows: rows,
                    columns: columns,
                    x: geometry.x,
                    y: geometry.y,
                    width: geometry.width,
                    height: geometry.height
                )
                print(objectId)
            }
        }

        struct Chart: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a Sheets chart and print its object id.",
                discussion: """
                    Optional geometry is measured in points. Get slide ids \
                    from `slides list --format json`. The chart id is the \
                    spreadsheet's embedded-chart id; --linked keeps the chart \
                    connected to the sheet.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the slide that will hold the chart.")
            var slideID: String

            @Option(name: .customLong("spreadsheet"), help: "The source spreadsheet ID.")
            var spreadsheet: String

            @Option(help: "The spreadsheet embedded-chart ID.")
            var chartId: Int

            @Flag(help: "Keep the chart connected to its source sheet.")
            var linked = false

            @OptionGroup
            var geometry: GeometryOptions

            func validate() throws {
                try geometry.validate()
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let objectId = try await client.createSheetsChart(
                    presentationId: presentationID,
                    slideId: slideID,
                    spreadsheetId: spreadsheet,
                    chartId: chartId,
                    linked: linked,
                    x: geometry.x,
                    y: geometry.y,
                    width: geometry.width,
                    height: geometry.height
                )
                print(objectId)
            }
        }
    }

    struct Element: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element",
            abstract: "Edit a page element: move, scale, rotate, or reorder it.",
            subcommands: [Move.self, Scale.self, Rotate.self, Transform.self, Reorder.self]
        )

        struct Move: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "move",
                abstract: "Move a page element and print its object id.",
                discussion: """
                    Positions and deltas are measured in points. Use --to-x and \
                    --to-y together to set the element's local origin in its \
                    parent's coordinate space, or --by-x and --by-y to nudge it \
                    by a delta, where a missing axis is 0. The two styles are \
                    mutually exclusive. For an element inside a group, \
                    coordinates are relative to the group. Get object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the page element to move.")
            var objectID: String

            @Option(
                parsing: .unconditional,
                help: "The new horizontal origin in points; use with --to-y."
            )
            var toX: Double?

            @Option(
                parsing: .unconditional,
                help: "The new vertical origin in points; use with --to-x."
            )
            var toY: Double?

            @Option(parsing: .unconditional, help: "The horizontal delta in points.")
            var byX: Double?

            @Option(parsing: .unconditional, help: "The vertical delta in points.")
            var byY: Double?

            func validate() throws {
                let hasTo = toX != nil || toY != nil
                let hasBy = byX != nil || byY != nil
                if hasTo && hasBy {
                    throw ValidationError(
                        "Use either --to-x/--to-y or --by-x/--by-y, not both.")
                }
                if !hasTo && !hasBy {
                    throw ValidationError(
                        "Provide --to-x and --to-y, or --by-x and/or --by-y.")
                }
                if hasTo && (toX == nil || toY == nil) {
                    throw ValidationError("--to-x and --to-y must be provided together.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                if let toX, let toY {
                    try await client.moveElement(
                        presentationId: presentationID,
                        objectId: objectID,
                        toX: toX,
                        toY: toY
                    )
                } else {
                    try await client.moveElement(
                        presentationId: presentationID,
                        objectId: objectID,
                        byX: byX ?? 0,
                        byY: byY ?? 0
                    )
                }
                print(objectID)
            }
        }

        struct Scale: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "scale",
                abstract: "Resize a page element in place and print its object id.",
                discussion: """
                    Scaling keeps the element's center fixed. Use --by for a \
                    uniform factor, or --by-x and --by-y together for separate \
                    horizontal and vertical factors. The two styles are \
                    mutually exclusive and every factor must be greater than \
                    zero. Get object ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the page element to scale.")
            var objectID: String

            @Option(
                parsing: .unconditional,
                help: "A uniform scale factor; must be greater than zero."
            )
            var by: Double?

            @Option(
                parsing: .unconditional,
                help: "The horizontal scale factor; use with --by-y."
            )
            var byX: Double?

            @Option(
                parsing: .unconditional,
                help: "The vertical scale factor; use with --by-x."
            )
            var byY: Double?

            func validate() throws {
                let hasUniform = by != nil
                let hasAxis = byX != nil || byY != nil
                if hasUniform && hasAxis {
                    throw ValidationError("--by cannot be combined with --by-x/--by-y.")
                }
                if !hasUniform && !hasAxis {
                    throw ValidationError("Provide --by, or --by-x and --by-y.")
                }
                if hasAxis && (byX == nil || byY == nil) {
                    throw ValidationError("--by-x and --by-y must be provided together.")
                }
                if let by, !(by > 0) {
                    throw ValidationError("--by must be greater than zero.")
                }
                if let byX, !(byX > 0) {
                    throw ValidationError("--by-x must be greater than zero.")
                }
                if let byY, !(byY > 0) {
                    throw ValidationError("--by-y must be greater than zero.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let factorX: Double
                let factorY: Double
                if let by {
                    factorX = by
                    factorY = by
                } else {
                    factorX = byX ?? 1
                    factorY = byY ?? 1
                }
                try await client.scaleElement(
                    presentationId: presentationID,
                    objectId: objectID,
                    factorX: factorX,
                    factorY: factorY
                )
                print(objectID)
            }
        }

        struct Rotate: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "rotate",
                abstract: "Rotate a page element and print its object id.",
                discussion: """
                    Rotation is about the element's center and measured in \
                    degrees, positive clockwise. Use --by to rotate by a delta, \
                    or --to to set an absolute angle; exactly one is required. \
                    Get object ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the page element to rotate.")
            var objectID: String

            @Option(
                parsing: .unconditional,
                help: "Rotate by this many degrees, clockwise."
            )
            var by: Double?

            @Option(
                parsing: .unconditional,
                help: "Rotate to this absolute angle in degrees, clockwise."
            )
            var to: Double?

            func validate() throws {
                if (by == nil) == (to == nil) {
                    throw ValidationError("Provide exactly one of --by or --to.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                if let by {
                    try await client.rotateElement(
                        presentationId: presentationID,
                        objectId: objectID,
                        byDegrees: by
                    )
                } else if let to {
                    try await client.rotateElement(
                        presentationId: presentationID,
                        objectId: objectID,
                        toDegrees: to
                    )
                }
                print(objectID)
            }
        }

        struct Transform: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "transform",
                abstract: "Set a page element's affine transform and print its object id.",
                discussion: """
                    This is the raw primitive: it sends the six transform \
                    fields verbatim. By default it replaces the element's whole \
                    matrix (absolute mode) with scale 1, no shear, no \
                    translation, in points. --relative instead left-multiplies \
                    the given matrix onto the existing transform; in relative \
                    mode the API does not convert units, so match the element's \
                    existing unit (usually EMU, with --unit emu). Get object \
                    ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the page element to transform.")
            var objectID: String

            @Option(parsing: .unconditional, help: "The scaleX (a) component.")
            var scaleX: Double = 1

            @Option(parsing: .unconditional, help: "The scaleY (d) component.")
            var scaleY: Double = 1

            @Option(parsing: .unconditional, help: "The shearX (c) component.")
            var shearX: Double = 0

            @Option(parsing: .unconditional, help: "The shearY (b) component.")
            var shearY: Double = 0

            @Option(parsing: .unconditional, help: "The translateX (tx) component.")
            var translateX: Double = 0

            @Option(parsing: .unconditional, help: "The translateY (ty) component.")
            var translateY: Double = 0

            @Option(help: "The unit of the transform: pt or emu.")
            var unit: ElementUnit = .pt

            @Flag(help: "Left-multiply onto the existing transform instead of replacing it.")
            var relative = false

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                let transform = ElementTransform(
                    scaleX: scaleX,
                    scaleY: scaleY,
                    shearX: shearX,
                    shearY: shearY,
                    translateX: translateX,
                    translateY: translateY,
                    unit: unit
                )
                let mode: TransformApplyMode = relative ? .relative : .absolute
                try await client.transformElement(
                    presentationId: presentationID,
                    objectId: objectID,
                    transform: transform,
                    mode: mode
                )
                print(objectID)
            }
        }

        struct Reorder: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "reorder",
                abstract: "Reorder page elements front-to-back and print their ids.",
                discussion: """
                    Moves one or more page elements in the z-order with --to \
                    front, forward, backward, or back. The elements must be on \
                    the same page and must not be grouped; when several are \
                    given their relative order is kept. Get object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "One or more page-element object ids, in the order to keep.")
            var objectIDs: [String]

            @Option(help: "The z-order move: front, forward, backward, or back.")
            var to: ReorderPosition

            func validate() throws {
                if objectIDs.isEmpty {
                    throw ValidationError("reorder requires at least one object id.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.reorderElements(
                    presentationId: presentationID,
                    objectIds: objectIDs,
                    operation: to.operation
                )
                for objectID in objectIDs {
                    print(objectID)
                }
            }
        }
    }

    struct Group: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Group page elements and print the new group's object id."
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Argument(help: "Two or more child page-element object ids.")
        var childIDs: [String]

        func validate() throws {
            if childIDs.count < 2 {
                throw ValidationError("group requires at least two child object ids.")
            }
        }

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            let objectId = try await client.groupElements(
                presentationId: presentationID, childIds: childIDs)
            print(objectId)
        }
    }

    struct Ungroup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Ungroup page elements and print each former group id."
        )

        @Argument(help: "The presentation ID.")
        var presentationID: String

        @Argument(help: "One or more top-level group object ids.")
        var objectIDs: [String]

        func validate() throws {
            if objectIDs.isEmpty {
                throw ValidationError("ungroup requires at least one group object id.")
            }
        }

        func run() async throws {
            let client = SlidesClient(api: try CLI.makeAPI())
            try await client.ungroupElements(
                presentationId: presentationID, objectIds: objectIDs)
            for objectId in objectIDs {
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

/// CLI-facing names for a z-order move. This keeps the wire enum
/// ``ZOrderOperation`` out of the command surface; the mapping lives here so
/// the user types `front`/`forward`/`backward`/`back` instead of the API's
/// `BRING_TO_FRONT`/`SEND_TO_BACK` spellings.
enum ReorderPosition: String, ExpressibleByArgument {
    case front
    case forward
    case backward
    case back

    /// The Slides API operation this position maps to.
    var operation: ZOrderOperation {
        switch self {
        case .front: return .bringToFront
        case .forward: return .bringForward
        case .backward: return .sendBackward
        case .back: return .sendToBack
        }
    }
}

/// Lets `--unit pt|emu` bind to the shared ``ElementUnit``. The API's raw
/// values are upper-case (`PT`/`EMU`), so accept either case, matching how
/// ``VideoSource`` and ``LineCategory`` parse in `Graham.swift`.
extension ElementUnit: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}
