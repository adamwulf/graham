import ArgumentParser
import Foundation
import GrahamKit

struct Slides: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Slides presentations.",
        subcommands: [
            Cat.self, List.self, Images.self, Add.self, Create.self, Element.self,
            Group.self, Ungroup.self, Move.self, Delete.self, Style.self, Table.self,
            Chart.self,
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

    struct Style: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "style",
            abstract: "Style a page element: shape, image, line, or video.",
            subcommands: [Shape.self, Image.self, Line.self, Video.self]
        )

        /// The outline options shared by `style shape`, `style image`, and
        /// `style video`. The color is a hex value or a theme name; it is parsed
        /// by ``OpaqueColor/parse(_:)`` in each command's `run()`, so here it is
        /// only captured as a string.
        struct OutlineOptions: ParsableArguments {
            @Option(help: "The outline color: a hex value like #FF0000 or a theme name like accent1.")
            var outline: String?

            @Option(parsing: .unconditional, help: "The outline fill alpha, from 0 to 1.")
            var outlineAlpha: Double?

            @Option(
                parsing: .unconditional,
                help: "The outline weight in points; must be greater than zero."
            )
            var outlineWeight: Double?

            @Option(help: "The outline dash: solid, dot, dash, dash-dot, long-dash, or long-dash-dot.")
            var outlineDash: DashStyleArgument?

            @Flag(help: "Remove the outline; cannot be combined with the other outline flags.")
            var noOutline = false

            /// Whether any outline flag was given at all.
            var hasAnyFlag: Bool {
                outline != nil || outlineAlpha != nil || outlineWeight != nil
                    || outlineDash != nil || noOutline
            }

            func validate() throws {
                if noOutline
                    && (outline != nil || outlineAlpha != nil || outlineWeight != nil
                        || outlineDash != nil)
                {
                    throw ValidationError(
                        "--no-outline cannot be combined with the other outline flags.")
                }
                try validateAlpha(outlineAlpha, name: "--outline-alpha")
                try validatePositive(outlineWeight, name: "--outline-weight")
            }
        }

        struct Shape: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "shape",
                abstract: "Style a shape and print its object id.",
                discussion: """
                    Sets a shape's background fill, outline, shadow, and content \
                    alignment; at least one flag is required. Colors are a hex \
                    value like #FF0000 (or #F00) or a theme name like accent1. \
                    Alphas are 0 to 1; weights, blur, and offsets are in points. \
                    --no-fill, --no-outline, and --no-shadow each remove that \
                    part and cannot be combined with the other flags of the same \
                    group. This changes appearance only; use `slides element` to \
                    move, scale, or rotate. Get object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the shape to style.")
            var objectID: String

            @Option(help: "The fill color: a hex value like #FF0000 or a theme name like accent1.")
            var fill: String?

            @Option(parsing: .unconditional, help: "The fill alpha, from 0 to 1.")
            var fillAlpha: Double?

            @Flag(help: "Remove the fill; cannot be combined with the other fill flags.")
            var noFill = false

            @OptionGroup
            var outlineOptions: OutlineOptions

            @Option(help: "The shadow color: a hex value like #FF0000 or a theme name like accent1.")
            var shadowColor: String?

            @Option(parsing: .unconditional, help: "The shadow alpha, from 0 to 1.")
            var shadowAlpha: Double?

            @Option(
                parsing: .unconditional,
                help: "The shadow blur radius in points; must be greater than zero."
            )
            var shadowBlur: Double?

            @Option(parsing: .unconditional, help: "The shadow horizontal offset in points.")
            var shadowOffsetX: Double?

            @Option(parsing: .unconditional, help: "The shadow vertical offset in points.")
            var shadowOffsetY: Double?

            @Flag(help: "Remove the shadow; cannot be combined with the other shadow flags.")
            var noShadow = false

            @Option(help: "The content alignment: top, middle, or bottom.")
            var align: ContentAlignmentArgument?

            func validate() throws {
                let hasFill = fill != nil || fillAlpha != nil || noFill
                let hasShadow =
                    shadowColor != nil || shadowAlpha != nil || shadowBlur != nil
                    || shadowOffsetX != nil || shadowOffsetY != nil || noShadow
                guard hasFill || hasShadow || align != nil || outlineOptions.hasAnyFlag
                else {
                    throw ValidationError("Provide at least one style flag.")
                }
                try outlineOptions.validate()
                if noFill && (fill != nil || fillAlpha != nil) {
                    throw ValidationError(
                        "--no-fill cannot be combined with the other fill flags.")
                }
                if noShadow
                    && (shadowColor != nil || shadowAlpha != nil || shadowBlur != nil
                        || shadowOffsetX != nil || shadowOffsetY != nil)
                {
                    throw ValidationError(
                        "--no-shadow cannot be combined with the other shadow flags.")
                }
                try validateAlpha(fillAlpha, name: "--fill-alpha")
                try validateAlpha(shadowAlpha, name: "--shadow-alpha")
                try validatePositive(shadowBlur, name: "--shadow-blur")
            }

            func run() async throws {
                let fillColor = try fill.map { try OpaqueColor.parse($0) }
                let outlineColor = try outlineOptions.outline.map { try OpaqueColor.parse($0) }
                let shadow = try shadowColor.map { try OpaqueColor.parse($0) }
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.styleShape(
                    presentationId: presentationID,
                    objectId: objectID,
                    fillColor: fillColor,
                    fillAlpha: fillAlpha,
                    noFill: noFill,
                    outlineColor: outlineColor,
                    outlineAlpha: outlineOptions.outlineAlpha,
                    outlineWeight: outlineOptions.outlineWeight,
                    outlineDash: outlineOptions.outlineDash?.dashStyle,
                    noOutline: outlineOptions.noOutline,
                    shadowColor: shadow,
                    shadowAlpha: shadowAlpha,
                    shadowBlur: shadowBlur,
                    shadowOffsetX: shadowOffsetX,
                    shadowOffsetY: shadowOffsetY,
                    noShadow: noShadow,
                    contentAlignment: align?.contentAlignment
                )
                print(objectID)
            }
        }

        struct Image: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "image",
                abstract: "Style an image's outline and print its object id.",
                discussion: """
                    Sets an image's outline only; at least one outline flag is \
                    required. The color is a hex value like #FF0000 (or #F00) or \
                    a theme name like accent1; the weight is in points and the \
                    alpha is 0 to 1. The Slides API exposes an image's \
                    brightness, contrast, transparency, crop, recolor, and \
                    shadow as read-only, so graham cannot change them. Get object \
                    ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the image to style.")
            var objectID: String

            @OptionGroup
            var outlineOptions: OutlineOptions

            func validate() throws {
                guard outlineOptions.hasAnyFlag else {
                    throw ValidationError("Provide at least one outline flag.")
                }
                try outlineOptions.validate()
            }

            func run() async throws {
                let outlineColor = try outlineOptions.outline.map { try OpaqueColor.parse($0) }
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.styleImage(
                    presentationId: presentationID,
                    objectId: objectID,
                    outlineColor: outlineColor,
                    outlineAlpha: outlineOptions.outlineAlpha,
                    outlineWeight: outlineOptions.outlineWeight,
                    outlineDash: outlineOptions.outlineDash?.dashStyle,
                    noOutline: outlineOptions.noOutline
                )
                print(objectID)
            }
        }

        struct Line: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "line",
                abstract: "Style a line and print its object id.",
                discussion: """
                    Sets a line's fill color, weight, dash style, and arrow \
                    ends; at least one flag is required. The color is a hex \
                    value like #FF0000 (or #F00) or a theme name like accent1; \
                    the weight is in points and the alpha is 0 to 1. The dash \
                    style is solid, dot, dash, dash-dot, long-dash, or \
                    long-dash-dot; each arrow is none, stealth-arrow, \
                    fill-arrow, fill-circle, fill-square, fill-diamond, \
                    open-arrow, open-circle, open-square, or open-diamond. Get \
                    object ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the line to style.")
            var objectID: String

            @Option(help: "The line color: a hex value like #FF0000 or a theme name like accent1.")
            var color: String?

            @Option(parsing: .unconditional, help: "The line fill alpha, from 0 to 1.")
            var alpha: Double?

            @Option(
                parsing: .unconditional,
                help: "The line weight in points; must be greater than zero."
            )
            var weight: Double?

            @Option(help: "The dash style: solid, dot, dash, dash-dot, long-dash, or long-dash-dot.")
            var dash: DashStyleArgument?

            @Option(help: "The start arrow style, such as none, open-arrow, or fill-circle.")
            var startArrow: ArrowStyleArgument?

            @Option(help: "The end arrow style, such as none, open-arrow, or fill-circle.")
            var endArrow: ArrowStyleArgument?

            func validate() throws {
                guard color != nil || alpha != nil || weight != nil || dash != nil
                    || startArrow != nil || endArrow != nil
                else {
                    throw ValidationError("Provide at least one style flag.")
                }
                try validateAlpha(alpha, name: "--alpha")
                try validatePositive(weight, name: "--weight")
            }

            func run() async throws {
                let lineColor = try color.map { try OpaqueColor.parse($0) }
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.styleLine(
                    presentationId: presentationID,
                    objectId: objectID,
                    color: lineColor,
                    alpha: alpha,
                    weight: weight,
                    dash: dash?.dashStyle,
                    startArrow: startArrow?.arrowStyle,
                    endArrow: endArrow?.arrowStyle
                )
                print(objectID)
            }
        }

        struct Video: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "video",
                abstract: "Style a video and print its object id.",
                discussion: """
                    Sets a video's playback options and outline; at least one \
                    flag is required. --autoplay/--no-autoplay and \
                    --mute/--no-mute toggle those settings, and omitting them \
                    leaves the setting unchanged. --start and --end are whole \
                    seconds from the beginning; when both are given, --end must \
                    be after --start. The outline color is a hex value like \
                    #FF0000 (or #F00) or a theme name like accent1 and its \
                    weight is in points. Get object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the video to style.")
            var objectID: String

            @Flag(inversion: .prefixedNo, help: "Play the video automatically.")
            var autoplay: Bool?

            @Flag(inversion: .prefixedNo, help: "Mute the video's audio.")
            var mute: Bool?

            @Option(parsing: .unconditional, help: "The start time in whole seconds; 0 or greater.")
            var start: Int?

            @Option(parsing: .unconditional, help: "The end time in whole seconds; after --start.")
            var end: Int?

            @OptionGroup
            var outlineOptions: OutlineOptions

            func validate() throws {
                guard autoplay != nil || mute != nil || start != nil || end != nil
                    || outlineOptions.hasAnyFlag
                else {
                    throw ValidationError("Provide at least one style flag.")
                }
                try outlineOptions.validate()
                if let start, start < 0 {
                    throw ValidationError("--start must be 0 or greater.")
                }
                if let end, end < 0 {
                    throw ValidationError("--end must be 0 or greater.")
                }
                if let start, let end, !(end > start) {
                    throw ValidationError("--end must be greater than --start.")
                }
            }

            func run() async throws {
                let outlineColor = try outlineOptions.outline.map { try OpaqueColor.parse($0) }
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.styleVideo(
                    presentationId: presentationID,
                    objectId: objectID,
                    autoPlay: autoplay,
                    mute: mute,
                    start: start,
                    end: end,
                    outlineColor: outlineColor,
                    outlineAlpha: outlineOptions.outlineAlpha,
                    outlineWeight: outlineOptions.outlineWeight,
                    outlineDash: outlineOptions.outlineDash?.dashStyle,
                    noOutline: outlineOptions.noOutline
                )
                print(objectID)
            }
        }
    }

    struct Table: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "table",
            abstract: "Edit a table's rows, columns, cells, and borders.",
            subcommands: [
                InsertRows.self, InsertColumns.self, DeleteRow.self, DeleteColumn.self,
                Merge.self, Unmerge.self, StyleCells.self, RowHeight.self,
                ColumnWidth.self, Borders.self,
            ]
        )

        /// Optional one-based range flags shared by cell and border styling.
        struct RangeOptions: ParsableArguments {
            @Option(parsing: .unconditional, help: "The one-based first row of the range.")
            var row: Int?

            @Option(parsing: .unconditional, help: "The one-based first column of the range.")
            var column: Int?

            @Option(parsing: .unconditional, help: "The number of rows; defaults to 1 for a range.")
            var rowSpan: Int?

            @Option(parsing: .unconditional, help: "The number of columns; defaults to 1 for a range.")
            var columnSpan: Int?

            func validate() throws {
                let hasAny = row != nil || column != nil || rowSpan != nil || columnSpan != nil
                guard hasAny else { return }
                guard row != nil, column != nil else {
                    throw ValidationError(
                        "A table range requires both --row and --column; spans alone are invalid.")
                }
                try validateOneBased(row, name: "--row")
                try validateOneBased(column, name: "--column")
                try validateOneBased(rowSpan, name: "--row-span")
                try validateOneBased(columnSpan, name: "--column-span")
            }
        }

        struct InsertRows: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "insert-rows",
                abstract: "Insert table rows and print the table object id.",
                discussion: """
                    Rows are one-based. Give exactly one of --below or --above; \
                    --count defaults to 1 and can be at most 20. Get table \
                    object ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The table object id.")
            var tableID: String

            @Option(parsing: .unconditional, help: "Insert below this one-based row.")
            var below: Int?

            @Option(parsing: .unconditional, help: "Insert above this one-based row.")
            var above: Int?

            @Option(parsing: .unconditional, help: "The number of rows to insert (1...20).")
            var count: Int = 1

            func validate() throws {
                guard (below == nil) != (above == nil) else {
                    throw ValidationError("Provide exactly one of --below or --above.")
                }
                try validateOneBased(below ?? above, name: "the reference row")
                guard (1...20).contains(count) else {
                    throw ValidationError("--count must be between 1 and 20.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                if let below {
                    try await client.insertTableRows(
                        presentationId: presentationID, tableId: tableID,
                        row: below, below: true, count: count)
                } else if let above {
                    try await client.insertTableRows(
                        presentationId: presentationID, tableId: tableID,
                        row: above, below: false, count: count)
                }
                print(tableID)
            }
        }

        struct InsertColumns: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "insert-columns",
                abstract: "Insert table columns and print the table object id.",
                discussion: """
                    Columns are one-based. Give exactly one of --right-of or \
                    --left-of; --count defaults to 1 and can be at most 20. Get \
                    table object ids from `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The table object id.")
            var tableID: String

            @Option(parsing: .unconditional, help: "Insert right of this one-based column.")
            var rightOf: Int?

            @Option(parsing: .unconditional, help: "Insert left of this one-based column.")
            var leftOf: Int?

            @Option(parsing: .unconditional, help: "The number of columns to insert (1...20).")
            var count: Int = 1

            func validate() throws {
                guard (rightOf == nil) != (leftOf == nil) else {
                    throw ValidationError("Provide exactly one of --right-of or --left-of.")
                }
                try validateOneBased(rightOf ?? leftOf, name: "the reference column")
                guard (1...20).contains(count) else {
                    throw ValidationError("--count must be between 1 and 20.")
                }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                if let rightOf {
                    try await client.insertTableColumns(
                        presentationId: presentationID, tableId: tableID,
                        column: rightOf, right: true, count: count)
                } else if let leftOf {
                    try await client.insertTableColumns(
                        presentationId: presentationID, tableId: tableID,
                        column: leftOf, right: false, count: count)
                }
                print(tableID)
            }
        }

        struct DeleteRow: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete-row",
                abstract: "Delete a table row and print the table object id.",
                discussion: """
                    Rows are one-based. A merged reference cell deletes every \
                    row it spans. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @Option(parsing: .unconditional, help: "The one-based row to delete.")
            var row: Int

            func validate() throws { try validateOneBased(row, name: "--row") }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.deleteTableRow(
                    presentationId: presentationID, tableId: tableID, row: row)
                print(tableID)
            }
        }

        struct DeleteColumn: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete-column",
                abstract: "Delete a table column and print the table object id.",
                discussion: """
                    Columns are one-based. A merged reference cell deletes \
                    every column it spans. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @Option(parsing: .unconditional, help: "The one-based column to delete.")
            var column: Int

            func validate() throws { try validateOneBased(column, name: "--column") }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.deleteTableColumn(
                    presentationId: presentationID, tableId: tableID, column: column)
                print(tableID)
            }
        }

        struct Merge: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "merge",
                abstract: "Merge table cells and print the table object id.",
                discussion: """
                    Row and column indices are one-based. Text is concatenated \
                    into the upper-left cell. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @Option(parsing: .unconditional, help: "The one-based first row.")
            var row: Int
            @Option(parsing: .unconditional, help: "The one-based first column.")
            var column: Int
            @Option(parsing: .unconditional, help: "The number of rows to merge.")
            var rowSpan: Int
            @Option(parsing: .unconditional, help: "The number of columns to merge.")
            var columnSpan: Int

            func validate() throws {
                try validateOneBased(row, name: "--row")
                try validateOneBased(column, name: "--column")
                try validateOneBased(rowSpan, name: "--row-span")
                try validateOneBased(columnSpan, name: "--column-span")
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.mergeTableCells(
                    presentationId: presentationID, tableId: tableID,
                    row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
                print(tableID)
            }
        }

        struct Unmerge: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "unmerge",
                abstract: "Unmerge table cells and print the table object id.",
                discussion: """
                    Row and column indices are one-based. Every merged cell in \
                    the range is unmerged. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @Option(parsing: .unconditional, help: "The one-based first row.")
            var row: Int
            @Option(parsing: .unconditional, help: "The one-based first column.")
            var column: Int
            @Option(parsing: .unconditional, help: "The number of rows to unmerge.")
            var rowSpan: Int
            @Option(parsing: .unconditional, help: "The number of columns to unmerge.")
            var columnSpan: Int

            func validate() throws {
                try validateOneBased(row, name: "--row")
                try validateOneBased(column, name: "--column")
                try validateOneBased(rowSpan, name: "--row-span")
                try validateOneBased(columnSpan, name: "--column-span")
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.unmergeTableCells(
                    presentationId: presentationID, tableId: tableID,
                    row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
                print(tableID)
            }
        }

        struct StyleCells: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "style-cells",
                abstract: "Style table cells and print the table object id.",
                discussion: """
                    Row and column indices are one-based. Omit the complete \
                    range to style the whole table; with --row and --column, \
                    omitted spans default to 1. At least one style flag is \
                    required. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @OptionGroup var range: RangeOptions
            @Option(help: "The fill color: a hex value or theme color name.")
            var fill: String?
            @Option(parsing: .unconditional, help: "The fill alpha, from 0 to 1.")
            var fillAlpha: Double?
            @Flag(help: "Remove the fill; cannot be combined with fill or fill-alpha.")
            var noFill = false
            @Option(help: "The content alignment: top, middle, or bottom.")
            var align: ContentAlignmentArgument?

            func validate() throws {
                try range.validate()
                guard fill != nil || fillAlpha != nil || noFill || align != nil else {
                    throw ValidationError("Provide at least one style flag.")
                }
                if noFill && (fill != nil || fillAlpha != nil) {
                    throw ValidationError(
                        "--no-fill cannot be combined with --fill or --fill-alpha.")
                }
                try validateAlpha(fillAlpha, name: "--fill-alpha")
            }

            func run() async throws {
                let color = try fill.map { try OpaqueColor.parse($0) }
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.styleTableCells(
                    presentationId: presentationID, tableId: tableID,
                    row: range.row, column: range.column,
                    rowSpan: range.rowSpan, columnSpan: range.columnSpan,
                    fillColor: color, fillAlpha: fillAlpha, noFill: noFill,
                    alignment: align?.contentAlignment)
                print(tableID)
            }
        }

        struct RowHeight: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "row-height",
                abstract: "Set table row height and print the table object id.",
                discussion: """
                    Rows are one-based. Repeat values after --rows; omitting \
                    --rows updates every row. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @Option(parsing: .unconditional, help: "The positive minimum height in points.")
            var minHeight: Double
            @Option(
                parsing: .upToNextOption,
                help: "One-based rows to update; omit to update every row."
            )
            var rows: [Int] = []

            func validate() throws {
                try validatePositive(minHeight, name: "--min-height")
                for row in rows { try validateOneBased(row, name: "--rows") }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.setTableRowHeight(
                    presentationId: presentationID, tableId: tableID,
                    rows: rows, minHeight: minHeight)
                print(tableID)
            }
        }

        struct ColumnWidth: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "column-width",
                abstract: "Set table column width and print the table object id.",
                discussion: """
                    Columns are one-based. Repeat values after --columns; \
                    omitting --columns updates every column. Width must be at \
                    least 32 points (406400 EMU). Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @Option(parsing: .unconditional, help: "The width in points; at least 32.")
            var width: Double
            @Option(
                parsing: .upToNextOption,
                help: "One-based columns to update; omit to update every column."
            )
            var columns: [Int] = []

            func validate() throws {
                guard width >= 32 else {
                    throw ValidationError("--width must be at least 32 points (406400 EMU).")
                }
                for column in columns { try validateOneBased(column, name: "--columns") }
            }

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.setTableColumnWidth(
                    presentationId: presentationID, tableId: tableID,
                    columns: columns, width: width)
                print(tableID)
            }
        }

        struct Borders: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "borders",
                abstract: "Style table borders and print the table object id.",
                discussion: """
                    Row and column indices are one-based. Omit the complete \
                    range to style the whole table; with --row and --column, \
                    omitted spans default to 1. At least one style flag is \
                    required. Get table object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String
            @Argument(help: "The table object id.")
            var tableID: String
            @OptionGroup var range: RangeOptions
            @Option(help: "The border position, such as all or inner-horizontal.")
            var position: TableBorderPositionArgument = .all
            @Option(help: "The border color: a hex value or theme color name.")
            var color: String?
            @Option(parsing: .unconditional, help: "The border alpha, from 0 to 1.")
            var alpha: Double?
            @Option(parsing: .unconditional, help: "The positive border weight in points.")
            var weight: Double?
            @Option(help: "The dash style, such as solid, dash-dot, or long-dash.")
            var dash: DashStyleArgument?

            func validate() throws {
                try range.validate()
                guard color != nil || alpha != nil || weight != nil || dash != nil else {
                    throw ValidationError("Provide at least one style flag.")
                }
                try validateAlpha(alpha, name: "--alpha")
                try validatePositive(weight, name: "--weight")
            }

            func run() async throws {
                let borderColor = try color.map { try OpaqueColor.parse($0) }
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.styleTableBorders(
                    presentationId: presentationID, tableId: tableID,
                    row: range.row, column: range.column,
                    rowSpan: range.rowSpan, columnSpan: range.columnSpan,
                    position: position.borderPosition,
                    color: borderColor, alpha: alpha, weight: weight,
                    dash: dash?.dashStyle)
                print(tableID)
            }
        }
    }

    struct Chart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "chart",
            abstract: "Work with charts on slides.",
            subcommands: [Refresh.self]
        )

        struct Refresh: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "refresh",
                abstract: "Refresh a linked Sheets chart and print its object id.",
                discussion: """
                    Re-fetches the chart from its source spreadsheet. This works \
                    only on a chart that was added linked to a sheet; an \
                    unlinked chart cannot be refreshed. Get object ids from \
                    `slides list --format json`.
                    """
            )

            @Argument(help: "The presentation ID.")
            var presentationID: String

            @Argument(help: "The object id of the linked chart to refresh.")
            var objectID: String

            func run() async throws {
                let client = SlidesClient(api: try CLI.makeAPI())
                try await client.refreshSheetsChart(
                    presentationId: presentationID, objectId: objectID)
                print(objectID)
            }
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

/// CLI-facing dash-style names. Keeps the API's SCREAMING wire spellings
/// (``DashStyle``) out of the command surface: the user types lower-kebab words
/// like `dash-dot`, following the ``ReorderPosition`` precedent.
enum DashStyleArgument: String, ExpressibleByArgument {
    case solid
    case dot
    case dash
    case dashDot = "dash-dot"
    case longDash = "long-dash"
    case longDashDot = "long-dash-dot"

    /// The Slides API dash style this argument maps to.
    var dashStyle: DashStyle {
        switch self {
        case .solid: return .solid
        case .dot: return .dot
        case .dash: return .dash
        case .dashDot: return .dashDot
        case .longDash: return .longDash
        case .longDashDot: return .longDashDot
        }
    }
}

/// CLI-facing arrow-style names, lower-kebab, mapping to the API ``ArrowStyle``.
enum ArrowStyleArgument: String, ExpressibleByArgument {
    case none
    case stealthArrow = "stealth-arrow"
    case fillArrow = "fill-arrow"
    case fillCircle = "fill-circle"
    case fillSquare = "fill-square"
    case fillDiamond = "fill-diamond"
    case openArrow = "open-arrow"
    case openCircle = "open-circle"
    case openSquare = "open-square"
    case openDiamond = "open-diamond"

    /// The Slides API arrow style this argument maps to.
    var arrowStyle: ArrowStyle {
        switch self {
        case .none: return .none
        case .stealthArrow: return .stealthArrow
        case .fillArrow: return .fillArrow
        case .fillCircle: return .fillCircle
        case .fillSquare: return .fillSquare
        case .fillDiamond: return .fillDiamond
        case .openArrow: return .openArrow
        case .openCircle: return .openCircle
        case .openSquare: return .openSquare
        case .openDiamond: return .openDiamond
        }
    }
}

/// CLI-facing content-alignment names mapping to the API ``ContentAlignment``.
enum ContentAlignmentArgument: String, ExpressibleByArgument {
    case top
    case middle
    case bottom

    /// The Slides API content alignment this argument maps to.
    var contentAlignment: ContentAlignment {
        switch self {
        case .top: return .top
        case .middle: return .middle
        case .bottom: return .bottom
        }
    }
}

/// CLI-facing lower-kebab table-border positions mapping to the Slides API
/// wire enum.
enum TableBorderPositionArgument: String, ExpressibleByArgument {
    case all
    case bottom
    case inner
    case innerHorizontal = "inner-horizontal"
    case innerVertical = "inner-vertical"
    case left
    case outer
    case right
    case top

    var borderPosition: TableBorderPosition {
        switch self {
        case .all: return .all
        case .bottom: return .bottom
        case .inner: return .inner
        case .innerHorizontal: return .innerHorizontal
        case .innerVertical: return .innerVertical
        case .left: return .left
        case .outer: return .outer
        case .right: return .right
        case .top: return .top
        }
    }
}

/// Rejects an alpha that is present but outside 0...1.
private func validateAlpha(_ alpha: Double?, name: String) throws {
    if let alpha, !(alpha >= 0 && alpha <= 1) {
        throw ValidationError("\(name) must be between 0 and 1.")
    }
}

/// Rejects a value that is present but not greater than zero.
private func validatePositive(_ value: Double?, name: String) throws {
    if let value, !(value > 0) {
        throw ValidationError("\(name) must be greater than zero.")
    }
}

/// Rejects an index or span that is present but below the one-based minimum.
private func validateOneBased(_ value: Int?, name: String) throws {
    if let value, value < 1 {
        throw ValidationError("\(name) must be one-based (1 or greater).")
    }
}
