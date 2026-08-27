import ArgumentParser
import Foundation
import GrahamKit

struct Docs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Docs documents.",
        subcommands: [
            Cat.self, Structure.self, Insert.self, Delete.self,
            Replace.self, Style.self, Paragraph.self, Heading.self, Bullets.self,
            Unbullet.self, Table.self, Images.self, PageBreak.self, Image.self,
            SectionBreak.self, Header.self, Footer.self, Footnote.self,
            NamedRange.self, PageSetup.self, SectionStyle.self, NamedStyle.self,
            Test.self,
        ]
    )

    struct Test: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the live end-to-end Docs smoke test.",
            discussion: """
                Creates a document inside a folder in My Drive, exercises \
                graham's Docs API surface (text, styling, lists, tables, images, \
                headers/footers/footnotes, named ranges, and page setup), and \
                trashes the document afterward. The folder remains. Use --keep to \
                retain the document for inspection. The command exits nonzero \
                when any step fails.
                """
        )

        @Flag(help: "Keep the document after the run.")
        var keep = false

        @Option(help: "The root-level My Drive folder to find or create.")
        var folder = "graham test"

        @Option(name: .customLong("image-url"), help: "The public image URL used by image-insert.")
        var imageURL = DocsLiveTest.defaultImageURL

        func run() async throws {
            let api = try CLI.makeAPI()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let label = formatter.string(from: Date())
            let runner = DocsLiveTest(
                drive: DriveClient(api: api),
                docs: DocsClient(api: api),
                folderName: folder,
                imageURL: imageURL,
                keep: keep,
                label: label,
                onStep: { step in
                    let ids = step.createdIDs.isEmpty
                        ? ""
                        : " [\(step.createdIDs.joined(separator: ", "))]"
                    switch step.outcome {
                    case .pass:
                        print("\(StatusColor.green.wrap("PASS")) \(step.name)\(ids)")
                    case .fail(let reason):
                        print("\(StatusColor.red.wrap("FAIL")) \(step.name): \(reason)\(ids)")
                    case .skip(let reason):
                        print("\(StatusColor.yellow.wrap("SKIP")) \(step.name): \(reason)\(ids)")
                    }
                }
            )
            let summary = await runner.run()
            print(
                "Summary: \(summary.passed) passed, \(summary.failed) failed, "
                    + "\(summary.skipped) skipped"
            )
            if summary.failed > 0 {
                throw ExitCode.failure
            }
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

    struct Style: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Style a range of text: bold, colors, font, link, and so on.",
            discussion: """
                Sets the character style of a zero-based UTF-16 range from --from
                up to but not including --to; at least one style flag is required.
                --bold, --italic, --underline, --strike, and --small-caps are
                toggles: pass the flag to turn it on, or its --no- form (for
                example --no-bold) to turn it off. Colors are a hex value like
                #FF0000. --size is in points and --font names a family, with an
                optional --font-weight (a multiple of 100 from 100 to 900).
                --baseline is super, sub, or none. In a named segment (--segment)
                the content starts at index 0. Get index ranges from `docs
                structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 start index (inclusive).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
        var segment: String?

        @Flag(inversion: .prefixedNo, help: "Bold the text (--no-bold turns it off).")
        var bold: Bool?

        @Flag(inversion: .prefixedNo, help: "Italicize the text (--no-italic turns it off).")
        var italic: Bool?

        @Flag(inversion: .prefixedNo, help: "Underline the text (--no-underline turns it off).")
        var underline: Bool?

        @Flag(inversion: .prefixedNo, help: "Strike through the text (--no-strike turns it off).")
        var strike: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: "Render the text in small caps (--no-small-caps turns it off)."
        )
        var smallCaps: Bool?

        @Option(help: "The text color as a hex value like #FF0000.")
        var color: String?

        @Option(help: "The background color as a hex value like #FF0000.")
        var background: String?

        @Option(
            parsing: .unconditional,
            help: "The font size in points; must be greater than zero."
        )
        var size: Double?

        @Option(help: "The font family name, such as Arial.")
        var font: String?

        @Option(
            parsing: .unconditional,
            help: "The font weight, a multiple of 100 from 100 to 900; requires --font."
        )
        var fontWeight: Int?

        @Option(help: "The baseline offset: super, sub, or none.")
        var baseline: DocsBaselineArgument?

        @Option(help: "Set a link to this URL.")
        var link: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            let hasStyle =
                bold != nil || italic != nil || underline != nil || strike != nil
                || smallCaps != nil || color != nil || background != nil || size != nil
                || font != nil || fontWeight != nil || baseline != nil || link != nil
            guard hasStyle else {
                throw ValidationError("Provide at least one style flag.")
            }
            if let fontWeight {
                guard font != nil else {
                    throw ValidationError("--font-weight requires --font.")
                }
                guard (100...900).contains(fontWeight), fontWeight % 100 == 0 else {
                    throw ValidationError(
                        "--font-weight must be a multiple of 100 from 100 to 900.")
                }
            }
            if let size, size <= 0 {
                throw ValidationError("--size must be greater than zero.")
            }
        }

        func run() async throws {
            let foreground = try color.map { try DocsOptionalColor.parse($0) }
            let backgroundColor = try background.map { try DocsOptionalColor.parse($0) }
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.styleText(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                segmentId: segment,
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strike,
                foregroundColor: foreground,
                backgroundColor: backgroundColor,
                fontSize: size,
                fontFamily: font,
                fontWeight: fontWeight,
                baselineOffset: baseline?.baselineOffset,
                linkURL: link,
                smallCaps: smallCaps,
                requiredRevisionId: requireRevision
            )
            print("Styled text in [\(from), \(to)).")
        }
    }

    struct Paragraph: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Style whole paragraphs: named style, alignment, spacing, and indents.",
            discussion: """
                Sets paragraph-level style across every paragraph the zero-based
                UTF-16 range from --from up to but not including --to touches; at
                least one style flag is required. --style is a named style:
                normal-text, title, subtitle, or heading-1 through heading-6.
                --align is start, center, end, or justified; --direction is ltr or
                rtl. --line-spacing is a percent of normal, where 100 is single;
                spacing and indents are in points. --keep-lines-together,
                --keep-with-next, --avoid-widows, and --page-break-before are
                pagination toggles (use the --no- form to turn one off). --shading
                is a hex background color; --spacing-mode is never-collapse or
                collapse-lists. --border sets the four outer paragraph borders
                (top, bottom, left, right) and --border-between sets the
                between-paragraph border; both take a hex color. --border-width
                (points, default 1; 0 hides a border), --border-dash (solid, dot,
                or dash; default solid), and --border-padding (points, default 0)
                are shared by both borders and require a border color. In a named
                segment (--segment) the content starts at index 0. Get index
                ranges from `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 start index (inclusive).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
        var segment: String?

        @Option(help: "The named style: normal-text, title, subtitle, or heading-1..heading-6.")
        var style: DocsNamedStyleArgument?

        @Option(help: "The alignment: start, center, end, or justified.")
        var align: DocsAlignmentArgument?

        @Option(help: "The text direction: ltr or rtl.")
        var direction: DocsDirectionArgument?

        @Option(
            parsing: .unconditional,
            help: "The line spacing as a percent of normal; 100 is single."
        )
        var lineSpacing: Double?

        @Option(parsing: .unconditional, help: "The space above each paragraph in points.")
        var spaceAbove: Double?

        @Option(parsing: .unconditional, help: "The space below each paragraph in points.")
        var spaceBelow: Double?

        @Option(parsing: .unconditional, help: "The start-edge indent in points.")
        var indentStart: Double?

        @Option(parsing: .unconditional, help: "The end-edge indent in points.")
        var indentEnd: Double?

        @Option(parsing: .unconditional, help: "The first-line indent in points.")
        var indentFirstLine: Double?

        @Flag(
            inversion: .prefixedNo,
            help: "Keep every line of the paragraph on one page (--no- turns it off)."
        )
        var keepLinesTogether: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: "Keep the paragraph on the same page as the next one (--no- turns it off)."
        )
        var keepWithNext: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: "Avoid a single line stranded across a page break (--no- turns it off)."
        )
        var avoidWidows: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: """
                Start the paragraph on a new page (--no- turns it off). The server \
                rejects this inside tables, headers, footers, and footnotes.
                """
        )
        var pageBreakBefore: Bool?

        @Option(help: "The paragraph background (shading) color as a hex value like #FFFF00.")
        var shading: String?

        @Option(help: "The spacing mode: never-collapse or collapse-lists.")
        var spacingMode: DocsSpacingModeArgument?

        @Option(help: "Set the four outer paragraph borders to this hex color, like #000000.")
        var border: String?

        @Option(help: "Set the between-paragraph border to this hex color, like #000000.")
        var borderBetween: String?

        @Option(
            parsing: .unconditional,
            help: "The border width in points; requires a border color (defaults to 1)."
        )
        var borderWidth: Double?

        @Option(help: "The border dash style: solid, dot, or dash; requires a border color.")
        var borderDash: DocsDashStyleArgument?

        @Option(
            parsing: .unconditional,
            help: "The border padding in points; requires a border color (defaults to 0)."
        )
        var borderPadding: Double?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            // A border's width, dash, and padding attach to a border color; a
            // width/dash/padding with neither --border nor --border-between has
            // nothing to attach to. This is checked before the at-least-one gate
            // so a lone --border-width earns its specific message.
            if borderWidth != nil || borderDash != nil || borderPadding != nil,
                border == nil, borderBetween == nil {
                throw ValidationError(
                    "--border-width, --border-dash, and --border-padding require "
                    + "--border or --border-between.")
            }
            let hasStyle =
                style != nil || align != nil || direction != nil || lineSpacing != nil
                || spaceAbove != nil || spaceBelow != nil || indentStart != nil
                || indentEnd != nil || indentFirstLine != nil || keepLinesTogether != nil
                || keepWithNext != nil || avoidWidows != nil || pageBreakBefore != nil
                || shading != nil || spacingMode != nil || border != nil || borderBetween != nil
            guard hasStyle else {
                throw ValidationError("Provide at least one style flag.")
            }
            if let lineSpacing, lineSpacing <= 0 {
                throw ValidationError("--line-spacing must be greater than zero.")
            }
            if let borderWidth, borderWidth < 0 {
                throw ValidationError("--border-width must not be negative (0 hides the border).")
            }
            if let borderPadding, borderPadding < 0 {
                throw ValidationError("--border-padding must not be negative (0 means no padding).")
            }
        }

        func run() async throws {
            let shadingColor = try shading.map { try DocsOptionalColor.parse($0) }
            let outerBorderColor = try border.map { try DocsOptionalColor.parse($0) }
            let betweenBorderColor = try borderBetween.map { try DocsOptionalColor.parse($0) }
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.styleParagraphs(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                segmentId: segment,
                namedStyleType: style?.namedStyleType,
                alignment: align?.alignment,
                direction: direction?.direction,
                lineSpacing: lineSpacing,
                spaceAbove: spaceAbove,
                spaceBelow: spaceBelow,
                indentStart: indentStart,
                indentEnd: indentEnd,
                indentFirstLine: indentFirstLine,
                keepLinesTogether: keepLinesTogether,
                keepWithNext: keepWithNext,
                avoidWidowAndOrphan: avoidWidows,
                pageBreakBefore: pageBreakBefore,
                shadingBackgroundColor: shadingColor,
                spacingMode: spacingMode?.spacingMode,
                outerBorderColor: outerBorderColor,
                betweenBorderColor: betweenBorderColor,
                borderWidth: borderWidth,
                borderDash: borderDash?.dashStyle,
                borderPadding: borderPadding,
                requiredRevisionId: requireRevision
            )
            print("Styled paragraphs in [\(from), \(to)).")
        }
    }

    struct Heading: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the named paragraph style (heading, title, or body) over a range.",
            discussion: """
                A thin shortcut for `docs paragraph --style`: it sets only the
                named style of every paragraph the zero-based UTF-16 range from
                --from up to but not including --to touches. <level> is 1 through 6
                for a heading, or title, subtitle, or normal for the body styles.
                Get index ranges from `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Argument(help: "The heading level 1-6, or title, subtitle, or normal.")
        var level: DocsHeadingLevelArgument

        @Option(help: "The zero-based UTF-16 start index (inclusive).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
        var segment: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.styleParagraphs(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                segmentId: segment,
                namedStyleType: level.namedStyleType,
                requiredRevisionId: requireRevision
            )
            print("Set \(level.namedStyleType) in [\(from), \(to)).")
        }
    }

    struct Bullets: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Turn the paragraphs in a range into a bulleted or numbered list.",
            discussion: """
                Applies a bullet --preset to every paragraph the zero-based UTF-16
                range from --from up to but not including --to touches. The preset
                names a family of glyphs (for example disc-circle-square or
                checkbox) or numbering (for example decimal-alpha-roman); run
                `docs bullets --help` to see every preset. Nesting comes from the
                leading tab characters already in each paragraph, which the write
                removes — this can shift later indices. In a named segment
                (--segment) the content starts at index 0. Get index ranges from
                `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 start index (inclusive).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        @Option(help: "The bullet preset (glyphs or numbering) to apply.")
        var preset: DocsBulletPresetArgument

        @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
        var segment: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.createParagraphBullets(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                preset: preset.bulletPreset,
                segmentId: segment,
                requiredRevisionId: requireRevision
            )
            print("Added \(preset.rawValue) bullets in [\(from), \(to)).")
        }
    }

    struct Unbullet: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove bullets from the paragraphs in a range.",
            discussion: """
                Removes the list bullets from every paragraph the zero-based
                UTF-16 range from --from up to but not including --to touches,
                preserving the visual nesting through indents. In a named segment
                (--segment) the content starts at index 0. Get index ranges from
                `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 start index (inclusive).")
        var from: Int

        @Option(help: "The zero-based UTF-16 end index (exclusive).")
        var to: Int

        @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
        var segment: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.deleteParagraphBullets(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                segmentId: segment,
                requiredRevisionId: requireRevision
            )
            print("Removed bullets in [\(from), \(to)).")
        }
    }

    struct Table: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "table",
            abstract: "Insert, delete, merge, pin, and style the rows and columns of a table.",
            discussion: """
                Every command locates the table by its zero-based UTF-16 start \
                index (--table for the edits, or --at for `create`), which you \
                read from `docs structure`. Cell --row and --column are \
                one-based. In a named segment (--segment) the table's indices \
                are measured within that segment.
                """,
            subcommands: [
                Create.self, AddRow.self, AddColumn.self, DeleteRow.self,
                DeleteColumn.self, Merge.self, Unmerge.self, PinHeaders.self,
                Style.self, RowStyle.self, ColumnWidth.self,
            ]
        )

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Insert an empty table and print its start index.",
                discussion: """
                    Inserts an empty --rows by --columns table at a zero-based \
                    UTF-16 index (--at) or at the end of the body or a segment \
                    (--end). Index 1 is the start of the body text; in a named \
                    segment (--segment) the content starts at index 0. The API \
                    inserts a newline before the table, so with --at the table \
                    starts at index + 1; that start index is printed so you can \
                    address the table with the other `docs table` commands. The \
                    table goes in the body, a header, or a footer (a footnote \
                    cannot hold a table), and --at cannot point at an existing \
                    table's start index (the server rejects that). Get index \
                    ranges from `docs structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The number of rows (1 or greater).")
            var rows: Int

            @Option(help: "The number of columns (1 or greater).")
            var columns: Int

            @Option(help: "The zero-based UTF-16 index to insert at (body minimum 1; segment minimum 0). Not needed with --end.")
            var at: Int?

            @Flag(help: "Append the table to the end of the body or segment; --at is ignored.")
            var end = false

            @Option(help: "A header or footer segment id to insert into. Omit for the body. A footnote cannot hold a table.")
            var segment: String?

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
                guard rows >= 1 else { throw ValidationError("--rows must be 1 or greater.") }
                guard columns >= 1 else { throw ValidationError("--columns must be 1 or greater.") }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                let result = try await client.insertTable(
                    documentId: documentID, rows: rows, columns: columns,
                    index: at, endOfSegment: end, segmentId: segment,
                    requiredRevisionId: requireRevision)
                if let start = result.tableStartIndex {
                    print("Created a \(rows)x\(columns) table; it starts at index \(start).")
                } else {
                    // An empty --segment normalizes to the body, exactly as the
                    // client does, so a blank id never reaches the message.
                    let namedSegment = segment.flatMap { $0.isEmpty ? nil : $0 }
                    let destination = namedSegment.map { "the end of segment \($0)" }
                        ?? "the end of the body"
                    print("Created a \(rows)x\(columns) table at \(destination).")
                }
            }
        }

        struct AddRow: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add-row",
                abstract: "Insert an empty row above or below a reference cell.",
                discussion: """
                    Give exactly one of --below or --above. --table is the \
                    table's zero-based start index from `docs structure`; --row \
                    and --column are one-based.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based reference row.")
            var row: Int

            @Option(help: "The one-based reference column.")
            var column: Int

            @Flag(help: "Insert below the reference row.")
            var below = false

            @Flag(help: "Insert above the reference row.")
            var above = false

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard below != above else {
                    throw ValidationError("Provide exactly one of --below or --above.")
                }
                guard row >= 1 else { throw ValidationError("--row must be one-based (1 or greater).") }
                guard column >= 1 else {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.insertTableRow(
                    documentId: documentID, tableStartIndex: table, row: row, column: column,
                    below: below, segmentId: segment, requiredRevisionId: requireRevision)
                print("Inserted a row \(below ? "below" : "above") cell (\(row), \(column)).")
            }
        }

        struct AddColumn: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add-column",
                abstract: "Insert an empty column left or right of a reference cell.",
                discussion: """
                    Give exactly one of --right or --left. --table is the \
                    table's zero-based start index from `docs structure`; --row \
                    and --column are one-based.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based reference row.")
            var row: Int

            @Option(help: "The one-based reference column.")
            var column: Int

            @Flag(help: "Insert to the right of the reference column.")
            var right = false

            @Flag(help: "Insert to the left of the reference column.")
            var left = false

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard right != left else {
                    throw ValidationError("Provide exactly one of --right or --left.")
                }
                guard row >= 1 else { throw ValidationError("--row must be one-based (1 or greater).") }
                guard column >= 1 else {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.insertTableColumn(
                    documentId: documentID, tableStartIndex: table, row: row, column: column,
                    right: right, segmentId: segment, requiredRevisionId: requireRevision)
                print("Inserted a column to the \(right ? "right" : "left") of cell (\(row), \(column)).")
            }
        }

        struct DeleteRow: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete-row",
                abstract: "Delete the row of a reference cell.",
                discussion: """
                    A merged reference cell deletes every row it spans. --table \
                    is the table's zero-based start index from `docs structure`; \
                    --row and --column are one-based.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based reference row.")
            var row: Int

            @Option(help: "The one-based reference column.")
            var column: Int

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard row >= 1 else { throw ValidationError("--row must be one-based (1 or greater).") }
                guard column >= 1 else {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.deleteTableRow(
                    documentId: documentID, tableStartIndex: table, row: row, column: column,
                    segmentId: segment, requiredRevisionId: requireRevision)
                print("Deleted the row of cell (\(row), \(column)).")
            }
        }

        struct DeleteColumn: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete-column",
                abstract: "Delete the column of a reference cell.",
                discussion: """
                    A merged reference cell deletes every column it spans. \
                    --table is the table's zero-based start index from `docs \
                    structure`; --row and --column are one-based.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based reference row.")
            var row: Int

            @Option(help: "The one-based reference column.")
            var column: Int

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard row >= 1 else { throw ValidationError("--row must be one-based (1 or greater).") }
                guard column >= 1 else {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.deleteTableColumn(
                    documentId: documentID, tableStartIndex: table, row: row, column: column,
                    segmentId: segment, requiredRevisionId: requireRevision)
                print("Deleted the column of cell (\(row), \(column)).")
            }
        }

        struct Merge: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "merge",
                abstract: "Merge a rectangular range of table cells.",
                discussion: """
                    Text from every merged cell is concatenated into the \
                    range's head cell. --table is the table's zero-based start \
                    index from `docs structure`; --row and --column are the \
                    one-based head cell, and --row-span and --column-span are \
                    cell counts (1 or greater).
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based head row of the range.")
            var row: Int

            @Option(help: "The one-based head column of the range.")
            var column: Int

            @Option(help: "The number of rows to span (1 or greater).")
            var rowSpan: Int

            @Option(help: "The number of columns to span (1 or greater).")
            var columnSpan: Int

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard row >= 1 else { throw ValidationError("--row must be one-based (1 or greater).") }
                guard column >= 1 else {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
                guard rowSpan >= 1 else {
                    throw ValidationError("--row-span must be 1 or greater.")
                }
                guard columnSpan >= 1 else {
                    throw ValidationError("--column-span must be 1 or greater.")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.mergeTableCells(
                    documentId: documentID, tableStartIndex: table, row: row, column: column,
                    rowSpan: rowSpan, columnSpan: columnSpan,
                    segmentId: segment, requiredRevisionId: requireRevision)
                print("Merged a \(rowSpan)x\(columnSpan) range at cell (\(row), \(column)).")
            }
        }

        struct Unmerge: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "unmerge",
                abstract: "Unmerge every merged cell in a rectangular range.",
                discussion: """
                    --table is the table's zero-based start index from `docs \
                    structure`; --row and --column are the one-based head cell, \
                    and --row-span and --column-span are cell counts (1 or \
                    greater).
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based head row of the range.")
            var row: Int

            @Option(help: "The one-based head column of the range.")
            var column: Int

            @Option(help: "The number of rows to span (1 or greater).")
            var rowSpan: Int

            @Option(help: "The number of columns to span (1 or greater).")
            var columnSpan: Int

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard row >= 1 else { throw ValidationError("--row must be one-based (1 or greater).") }
                guard column >= 1 else {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
                guard rowSpan >= 1 else {
                    throw ValidationError("--row-span must be 1 or greater.")
                }
                guard columnSpan >= 1 else {
                    throw ValidationError("--column-span must be 1 or greater.")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.unmergeTableCells(
                    documentId: documentID, tableStartIndex: table, row: row, column: column,
                    rowSpan: rowSpan, columnSpan: columnSpan,
                    segmentId: segment, requiredRevisionId: requireRevision)
                print("Unmerged a \(rowSpan)x\(columnSpan) range at cell (\(row), \(column)).")
            }
        }

        struct PinHeaders: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "pin-headers",
                abstract: "Pin the first N rows of a table as headers (0 unpins).",
                discussion: """
                    --table is the table's zero-based start index from `docs \
                    structure`; --count is the number of leading rows to pin, \
                    and 0 unpins.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(
                parsing: .unconditional,
                help: "The number of leading rows to pin as headers; 0 unpins."
            )
            var count: Int

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard count >= 0 else { throw ValidationError("--count must be 0 or greater.") }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.pinTableHeaderRows(
                    documentId: documentID, tableStartIndex: table,
                    pinnedHeaderRowsCount: count,
                    segmentId: segment, requiredRevisionId: requireRevision)
                if count == 0 {
                    print("Unpinned the header rows.")
                } else {
                    print("Pinned \(count) header row(s).")
                }
            }
        }

        struct Style: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "style",
                abstract: "Style a range of table cells, or a whole table.",
                discussion: """
                    Sets cell background, borders, padding, and vertical \
                    alignment. --table is the table's zero-based start index \
                    from `docs structure`. Give --row and --column (one-based, \
                    with optional --row-span and --column-span) to style a range \
                    of cells; omit them to style the whole table. --border sets \
                    all four cell borders and requires a color; its width \
                    defaults to 1pt and its dash to solid unless --border-width \
                    or --border-dash override them. --padding sets all four cell \
                    paddings. Colors are a hex value like #FF0000. At least one \
                    of --background, --border, --padding, or --align is required.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(help: "The one-based head row of the cell range. Omit to style the whole table.")
            var row: Int?

            @Option(help: "The one-based head column of the cell range. Omit to style the whole table.")
            var column: Int?

            @Option(help: "The number of rows to span (1 or greater; defaults to 1).")
            var rowSpan: Int?

            @Option(help: "The number of columns to span (1 or greater; defaults to 1).")
            var columnSpan: Int?

            @Option(help: "The cell background color as a hex value like #FF0000.")
            var background: String?

            @Option(help: "Set all four cell borders to this hex color, like #000000.")
            var border: String?

            @Option(
                parsing: .unconditional,
                help: "The border width in points; requires --border (defaults to 1)."
            )
            var borderWidth: Double?

            @Option(help: "The border dash style: solid, dot, or dash; requires --border.")
            var borderDash: DocsDashStyleArgument?

            @Option(parsing: .unconditional, help: "Set all four cell paddings to this many points.")
            var padding: Double?

            @Option(help: "The vertical content alignment: top, middle, or bottom.")
            var align: DocsContentAlignmentArgument?

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                let hasStyle =
                    background != nil || border != nil || padding != nil || align != nil
                guard hasStyle else {
                    throw ValidationError(
                        "Provide at least one of --background, --border, --padding, or --align.")
                }
                if (borderWidth != nil || borderDash != nil), border == nil {
                    throw ValidationError("--border-width and --border-dash require --border.")
                }
                // A cell range needs both a row and a column; the spans require
                // them too. Omitting all four styles the whole table.
                if (rowSpan != nil || columnSpan != nil), row == nil || column == nil {
                    throw ValidationError(
                        "--row-span and --column-span require --row and --column.")
                }
                if (row == nil) != (column == nil) {
                    throw ValidationError(
                        "Provide both --row and --column to style a cell range, or neither "
                        + "to style the whole table.")
                }
                if let row, row < 1 { throw ValidationError("--row must be one-based (1 or greater).") }
                if let column, column < 1 {
                    throw ValidationError("--column must be one-based (1 or greater).")
                }
                if let rowSpan, rowSpan < 1 {
                    throw ValidationError("--row-span must be 1 or greater.")
                }
                if let columnSpan, columnSpan < 1 {
                    throw ValidationError("--column-span must be 1 or greater.")
                }
                if let borderWidth, borderWidth < 0 {
                    throw ValidationError("--border-width must not be negative (0 hides the border).")
                }
                if let padding, padding < 0 {
                    throw ValidationError("--padding must not be negative (0 means no padding).")
                }
            }

            func run() async throws {
                let backgroundColor = try background.map { try DocsOptionalColor.parse($0) }
                let borderColor = try border.map { try DocsOptionalColor.parse($0) }
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.styleTableCells(
                    documentId: documentID,
                    tableStartIndex: table,
                    row: row,
                    column: column,
                    rowSpan: rowSpan,
                    columnSpan: columnSpan,
                    segmentId: segment,
                    backgroundColor: backgroundColor,
                    borderColor: borderColor,
                    borderWidth: borderWidth,
                    borderDash: borderDash?.dashStyle,
                    padding: padding,
                    contentAlignment: align?.contentAlignment,
                    requiredRevisionId: requireRevision)
                if row != nil, column != nil {
                    print("Styled table cells at cell (\(row ?? 0), \(column ?? 0)).")
                } else {
                    print("Styled the whole table at index \(table).")
                }
            }
        }

        struct RowStyle: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "row-style",
                abstract: "Set the height and overflow of table rows.",
                discussion: """
                    --table is the table's zero-based start index from `docs \
                    structure`. --rows is a list of one-based row numbers to \
                    style; omit it to style every row. --min-height is in points. \
                    --prevent-overflow keeps a row's content from splitting \
                    across a page (--no-prevent-overflow clears it). At least one \
                    style option is required. To mark rows as repeated headers, \
                    use `docs table pin-headers`; the Docs API cannot change a \
                    row's header designation through row style.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(
                parsing: .upToNextOption,
                help: "The one-based rows to style. Omit to style every row."
            )
            var rows: [Int] = []

            @Option(parsing: .unconditional, help: "The minimum row height in points.")
            var minHeight: Double?

            @Flag(
                inversion: .prefixedNo,
                help: "Keep each row's content from splitting across a page."
            )
            var preventOverflow: Bool?

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                let hasStyle = minHeight != nil || preventOverflow != nil
                guard hasStyle else {
                    throw ValidationError(
                        "Provide at least one of --min-height or --prevent-overflow.")
                }
                if let minHeight, minHeight <= 0 {
                    throw ValidationError("--min-height must be greater than zero.")
                }
                for row in rows where row < 1 {
                    throw ValidationError("--rows must be one-based (1 or greater).")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.styleTableRow(
                    documentId: documentID,
                    tableStartIndex: table,
                    rows: rows,
                    minRowHeight: minHeight,
                    preventOverflow: preventOverflow,
                    segmentId: segment,
                    requiredRevisionId: requireRevision)
                if rows.isEmpty {
                    print("Styled every row of the table at index \(table).")
                } else {
                    print("Styled \(rows.count) row(s) of the table at index \(table).")
                }
            }
        }

        struct ColumnWidth: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "column-width",
                abstract: "Set the width of table columns (fixed or evenly distributed).",
                discussion: """
                    --table is the table's zero-based start index from `docs \
                    structure`. --columns is a list of one-based column numbers \
                    to size; omit it to size every column. Give exactly one of \
                    --width <points> (a fixed width, at least 5) or --evenly \
                    (distribute the table width evenly across the columns).
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The table's zero-based UTF-16 start index (from `docs structure`).")
            var table: Int

            @Option(
                parsing: .upToNextOption,
                help: "The one-based columns to size. Omit to size every column."
            )
            var columns: [Int] = []

            @Option(help: "The fixed column width in points (at least 5). Conflicts with --evenly.")
            var width: Double?

            @Flag(help: "Distribute the table width evenly across the columns. Conflicts with --width.")
            var evenly = false

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard (width != nil) != evenly else {
                    throw ValidationError("Provide exactly one of --width or --evenly.")
                }
                if let width, width < 5 {
                    throw ValidationError("--width must be at least 5 points.")
                }
                for column in columns where column < 1 {
                    throw ValidationError("--columns must be one-based (1 or greater).")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.styleTableColumnWidth(
                    documentId: documentID,
                    tableStartIndex: table,
                    columns: columns,
                    width: width,
                    evenlyDistributed: evenly,
                    segmentId: segment,
                    requiredRevisionId: requireRevision)
                let sizing = width.map { "a fixed width of \($0) points" } ?? "evenly distributed"
                if columns.isEmpty {
                    print("Set every column of the table at index \(table) to \(sizing).")
                } else {
                    print("Set \(columns.count) column(s) of the table at index \(table) to \(sizing).")
                }
            }
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

    struct PageBreak: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "page-break",
            abstract: "Insert a page break plus a newline in the document body.",
            discussion: """
                Inserts a page break at a zero-based UTF-16 body index (--at) or \
                at the end of the body (--end). Index 1 is the start of the body \
                text. Page breaks are body-only, so there is no segment option. \
                Get index ranges from `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 body index to insert at (minimum 1). Not needed with --end.")
        var at: Int?

        @Flag(help: "Append the page break to the end of the body. Mutually exclusive with --at; give exactly one.")
        var end = false

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            if end && at != nil {
                throw ValidationError(
                    "Pass either --at <index> or --end, not both: --end appends to the "
                    + "end of the body and takes no index.")
            }
            guard end || at != nil else {
                throw ValidationError(
                    "Provide --at <index>, or pass --end to append to the end of the body.")
            }
        }

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.insertPageBreak(
                documentId: documentID, index: at, endOfSegment: end,
                requiredRevisionId: requireRevision)
            if end {
                print("Inserted a page break at the end of the body.")
            } else {
                print("Inserted a page break at index \(at ?? 0).")
            }
        }
    }

    struct Image: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "Insert an inline image, or replace an existing image.",
            discussion: """
                Insert an image from a public URI, or replace an existing image \
                in place. In both cases Google fetches the URI once at insertion \
                time and stores a copy, so the URI must be publicly fetchable by \
                Google, under 50MB, at most 25 megapixels, and in PNG, JPEG, or \
                GIF format.
                """,
            subcommands: [Insert.self, Replace.self]
        )

        struct Insert: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "insert",
                abstract: "Insert an inline image from a URI and print its object id.",
                discussion: """
                    Inserts the image at a zero-based UTF-16 index (--at) or at \
                    the end of the body or a segment (--end). Index 1 is the \
                    start of the body text; in a named segment (--segment) the \
                    content starts at index 0. The image goes in the body, a \
                    header, or a footer (an inline image cannot go in a \
                    footnote). --width and --height are optional display sizes in \
                    points; give one and the other is computed to preserve the \
                    aspect ratio. The --uri must be publicly fetchable by Google \
                    at insertion time (under 50MB, at most 25 megapixels, \
                    PNG/JPEG/GIF). The new image's object id is printed. Get \
                    index ranges from `docs structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The public image URI (PNG, JPEG, or GIF; under 50MB and 25 megapixels).")
            var uri: String

            @Option(help: "The zero-based UTF-16 index to insert at (body minimum 1; segment minimum 0). Not needed with --end.")
            var at: Int?

            @Flag(help: "Append the image to the end of the body or segment. Mutually exclusive with --at; give exactly one.")
            var end = false

            @Option(parsing: .unconditional, help: "The display width in points (greater than zero).")
            var width: Double?

            @Option(parsing: .unconditional, help: "The display height in points (greater than zero).")
            var height: Double?

            @Option(help: "A header or footer segment id to insert into. Omit for the body. A footnote cannot hold an image.")
            var segment: String?

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
                if uri.isEmpty { throw ValidationError("--uri must not be empty.") }
                if let width, width <= 0 {
                    throw ValidationError("--width must be greater than zero.")
                }
                if let height, height <= 0 {
                    throw ValidationError("--height must be greater than zero.")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                let result = try await client.insertInlineImage(
                    documentId: documentID, uri: uri, index: at, endOfSegment: end,
                    segmentId: segment, width: width, height: height,
                    requiredRevisionId: requireRevision)
                print(result.objectId ?? "")
            }
        }

        struct Replace: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "replace",
                abstract: "Replace an existing image in place with a new image from a URI.",
                discussion: """
                    Replaces the image with object id <image-object-id> using the \
                    new --uri. The only replace method is center-crop: the new \
                    image is scaled and centered to fill the original image's \
                    bounds, cropping as needed. The --uri must be publicly \
                    fetchable by Google at insertion time (under 50MB, at most 25 \
                    megapixels, PNG/JPEG/GIF). Get image object ids from `docs \
                    images`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Argument(help: "The object id of the existing image to replace (from `docs images`).")
            var imageObjectID: String

            @Option(help: "The public replacement image URI (PNG, JPEG, or GIF; under 50MB and 25 megapixels).")
            var uri: String

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                if imageObjectID.isEmpty {
                    throw ValidationError("The image object id must not be empty.")
                }
                if uri.isEmpty { throw ValidationError("--uri must not be empty.") }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.replaceImage(
                    documentId: documentID, imageObjectId: imageObjectID, uri: uri,
                    requiredRevisionId: requireRevision)
                print("Replaced image \(imageObjectID).")
            }
        }
    }

    struct SectionBreak: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "section-break",
            abstract: "Insert a continuous or next-page section break in the body.",
            discussion: """
                Inserts a section break (preceded by a newline) at a zero-based \
                UTF-16 body index (--at) or at the end of the body (--end). \
                --type is continuous (start right after the previous section) or \
                next-page (start on the next page). Index 1 is the start of the \
                body text. Section breaks are body-only, so there is no segment \
                option. Get index ranges from `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The section type: continuous or next-page.")
        var type: DocsSectionTypeArgument

        @Option(help: "The zero-based UTF-16 body index to insert at (minimum 1). Not needed with --end.")
        var at: Int?

        @Flag(help: "Append the section break to the end of the body. Mutually exclusive with --at; give exactly one.")
        var end = false

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            if end && at != nil {
                throw ValidationError(
                    "Pass either --at <index> or --end, not both: --end appends to the "
                    + "end of the body and takes no index.")
            }
            guard end || at != nil else {
                throw ValidationError(
                    "Provide --at <index>, or pass --end to append to the end of the body.")
            }
        }

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.insertSectionBreak(
                documentId: documentID, sectionType: type.sectionType,
                index: at, endOfSegment: end, requiredRevisionId: requireRevision)
            let destination = end ? "the end of the body" : "index \(at ?? 0)"
            print("Inserted a \(type.rawValue) section break at \(destination).")
        }
    }

    struct Header: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "header",
            abstract: "Create or delete a document header.",
            discussion: """
                A create returns the new header's segment id; pass it to \
                `docs insert --segment <id>` (or the other segment-aware \
                writes) to fill the header. A create can optionally scope the \
                header to a section with --at, a zero-based UTF-16 body index \
                at a section break. Only the DEFAULT header type is created; \
                first-page and even-page headers are document-style flags, not \
                a create option.
                """,
            subcommands: [Create.self, Delete.self]
        )

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Create a header and print its segment id.",
                discussion: """
                    Creates a DEFAULT header and prints the new header segment \
                    id. Pass --at, a zero-based UTF-16 body index at a section \
                    break (minimum 1), to scope the header to that section; \
                    omit it to apply the header to the whole document. Get \
                    index ranges from `docs structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "A zero-based UTF-16 body index at a section break to scope the header to (minimum 1). Omit for the whole document.")
            var at: Int?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                let result = try await client.createHeader(
                    documentId: documentID, sectionBreakIndex: at,
                    requiredRevisionId: requireRevision)
                print(result.headerId ?? "")
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete a header by its segment id.",
                discussion: """
                    Deletes the header with segment id <header-id>. Get header \
                    ids from a `docs header create` reply or `docs structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Argument(help: "The header's segment id (from `docs header create` or `docs structure`).")
            var headerID: String

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                if headerID.isEmpty {
                    throw ValidationError("The header id must not be empty.")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.deleteHeader(
                    documentId: documentID, headerId: headerID,
                    requiredRevisionId: requireRevision)
                print("Deleted header \(headerID).")
            }
        }
    }

    struct Footer: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "footer",
            abstract: "Create or delete a document footer.",
            discussion: """
                A create returns the new footer's segment id; pass it to \
                `docs insert --segment <id>` (or the other segment-aware \
                writes) to fill the footer. A create can optionally scope the \
                footer to a section with --at, a zero-based UTF-16 body index \
                at a section break. Only the DEFAULT footer type is created; \
                first-page and even-page footers are document-style flags, not \
                a create option.
                """,
            subcommands: [Create.self, Delete.self]
        )

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Create a footer and print its segment id.",
                discussion: """
                    Creates a DEFAULT footer and prints the new footer segment \
                    id. Pass --at, a zero-based UTF-16 body index at a section \
                    break (minimum 1), to scope the footer to that section; \
                    omit it to apply the footer to the whole document. Get \
                    index ranges from `docs structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "A zero-based UTF-16 body index at a section break to scope the footer to (minimum 1). Omit for the whole document.")
            var at: Int?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                let result = try await client.createFooter(
                    documentId: documentID, sectionBreakIndex: at,
                    requiredRevisionId: requireRevision)
                print(result.footerId ?? "")
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete a footer by its segment id.",
                discussion: """
                    Deletes the footer with segment id <footer-id>. Get footer \
                    ids from a `docs footer create` reply or `docs structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Argument(help: "The footer's segment id (from `docs footer create` or `docs structure`).")
            var footerID: String

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                if footerID.isEmpty {
                    throw ValidationError("The footer id must not be empty.")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.deleteFooter(
                    documentId: documentID, footerId: footerID,
                    requiredRevisionId: requireRevision)
                print("Deleted footer \(footerID).")
            }
        }
    }

    struct Footnote: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "footnote",
            abstract: "Create a footnote and print its segment id.",
            discussion: """
                Inserts a footnote reference in the document body at a \
                zero-based UTF-16 index (--at) or at the end of the body \
                (--end), and prints the new footnote segment id. Index 1 is \
                the start of the body text. Footnote references are body-only, \
                so there is no segment option. With --text, the text is \
                inserted into the new footnote segment: because the footnote id \
                is only known after the reference is created, this is a second \
                write, and the footnote segment starts with an auto-inserted \
                space and newline, so the text lands at index 1. Get index \
                ranges from `docs structure`.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 body index to insert the reference at (minimum 1). Not needed with --end.")
        var at: Int?

        @Flag(help: "Insert the reference at the end of the body. Mutually exclusive with --at; give exactly one.")
        var end = false

        @Option(help: "Footnote text to insert into the new footnote segment (a second write).")
        var text: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            if end && at != nil {
                throw ValidationError(
                    "Pass either --at <index> or --end, not both: --end inserts the "
                    + "reference at the end of the body and takes no index.")
            }
            guard end || at != nil else {
                throw ValidationError(
                    "Provide --at <index>, or pass --end to insert at the end of the body.")
            }
            if let text, text.isEmpty {
                throw ValidationError("--text must not be empty.")
            }
        }

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            let result = try await client.createFootnote(
                documentId: documentID, index: at, endOfBody: end, text: text,
                requiredRevisionId: requireRevision)
            print(result.footnoteId ?? "")
        }
    }

    struct NamedRange: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "range",
            abstract: "Create, list, delete, or fill a named range (template filling).",
            discussion: """
                A named range labels a zero-based UTF-16 span so a later `fill` \
                can replace its content — the template-filling primitive. `create` \
                names a range and prints its id; `list` shows the document's \
                existing named ranges (id, name, spans); `delete` removes a range \
                by id or every range sharing a name; `fill` replaces a range's \
                content with text (by id or name). Names need not be unique. Get \
                the text spans to name from `docs structure`, and existing named \
                range ids and names from `docs range list`.
                """,
            subcommands: [Create.self, List.self, Delete.self, Fill.self]
        )

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Create a named range over a text range and print its id.",
                discussion: """
                    Names the zero-based UTF-16 range from --from up to but not \
                    including --to. --name is 1 to 256 UTF-16 code units and need \
                    not be unique. Index 1 is the start of the body text; in a \
                    named segment (--segment) the content starts at index 0. The \
                    new named range id is printed. Get index ranges from `docs \
                    structure`.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The named range name (1 to 256 UTF-16 code units; need not be unique).")
            var name: String

            @Option(help: "The zero-based UTF-16 start index (inclusive; body minimum 1; segment minimum 0).")
            var from: Int

            @Option(help: "The zero-based UTF-16 end index (exclusive).")
            var to: Int

            @Option(help: "A header, footer, or footnote segment id. Omit for the body.")
            var segment: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                // The API measures the name in UTF-16 code units, so count those
                // (matching GrahamKit) rather than Characters.
                let length = name.utf16.count
                guard (1...256).contains(length) else {
                    throw ValidationError("--name must be 1 to 256 UTF-16 code units.")
                }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                let result = try await client.createNamedRange(
                    documentId: documentID, name: name, startIndex: from, endIndex: to,
                    segmentId: segment, requiredRevisionId: requireRevision)
                print(result.namedRangeId ?? "")
            }
        }

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List the document's named ranges (id, name, spans).",
                discussion: """
                    Each row is one named range: its id, its name, and its \
                    zero-based UTF-16 index spans (a discontinuous range shows \
                    several start-end spans joined by commas). A name can label \
                    several ranges, so it can appear on more than one row. Take an \
                    id for `docs range delete --id` / `fill --id`, or a name for \
                    `--name`, to target a pre-existing range. Use --format json \
                    for the full detail (segment and tab ids).
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The output format: table, json, jsonl, or id.")
            var format: OutputFormat = .table

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                let document = try await client.document(id: documentID)
                print(try OutputFormatter.render(document.namedRangeRows, format: format))
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete a named range by id, or every range with a name.",
                discussion: """
                    Give exactly one of --id (delete that one range) or --name \
                    (delete every named range sharing the name). Deleting by a \
                    name that matches nothing is a no-op. Get named range ids and \
                    names from `docs range list` or a `docs range create` reply.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The named range id to delete. Mutually exclusive with --name.")
            var id: String?

            @Option(help: "Delete every named range with this name. Mutually exclusive with --id.")
            var name: String?

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard (id == nil) != (name == nil) else {
                    throw ValidationError("Provide exactly one of --id or --name.")
                }
                if let id, id.isEmpty { throw ValidationError("--id must not be empty.") }
                if let name, name.isEmpty { throw ValidationError("--name must not be empty.") }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.deleteNamedRange(
                    documentId: documentID, namedRangeId: id, name: name,
                    requiredRevisionId: requireRevision)
                if let id {
                    print("Deleted named range \(id).")
                } else {
                    print("Deleted named range(s) named \(name ?? "").")
                }
            }
        }

        struct Fill: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "fill",
                abstract: "Replace the content of a named range with text.",
                discussion: """
                    Give exactly one of --id (fill that one range) or --name (fill \
                    every named range sharing the name). --text is the replacement \
                    and may be empty to clear the range. A discontinuous named \
                    range replaces only its first subrange. Get named range ids \
                    and names from `docs range list` or a `docs range create` reply.
                    """
            )

            @Argument(help: "The document ID.")
            var documentID: String

            @Option(help: "The named range id to fill. Mutually exclusive with --name.")
            var id: String?

            @Option(help: "Fill every named range with this name. Mutually exclusive with --id.")
            var name: String?

            @Option(help: "The replacement text; may be empty to clear the range.")
            var text: String

            @Option(help: "Require the document be at this revision id; the write fails otherwise.")
            var requireRevision: String?

            func validate() throws {
                guard (id == nil) != (name == nil) else {
                    throw ValidationError("Provide exactly one of --id or --name.")
                }
                if let id, id.isEmpty { throw ValidationError("--id must not be empty.") }
                if let name, name.isEmpty { throw ValidationError("--name must not be empty.") }
            }

            func run() async throws {
                let client = DocsClient(api: try CLI.makeAPI())
                _ = try await client.replaceNamedRangeContent(
                    documentId: documentID, text: text, namedRangeId: id, name: name,
                    requiredRevisionId: requireRevision)
                if let id {
                    print("Filled named range \(id).")
                } else {
                    print("Filled named range(s) named \(name ?? "").")
                }
            }
        }
    }

    struct PageSetup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "page-setup",
            abstract: "Set page size, margins, header/footer flags, background, and mode.",
            discussion: """
                Sets document-wide style. --page-width and --page-height are a \
                pair (in points): give both or neither, since setting only one \
                would zero the other. Margins are in points. \
                --first-page-header-footer / --even-page-header-footer toggle the \
                first-page and even-page header/footer (use the --no- forms to \
                clear them). --background is a hex color like #FFFFFF. --mode is \
                pages or pageless. --page-number-start sets the first page number \
                (1 or greater). --margin-header / --margin-footer set the header \
                and footer margins in points (each turns on custom header/footer \
                margins). --flip-orientation swaps the page width and height. \
                Every dimension must be a finite value greater than zero, and at \
                least one option is required.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(parsing: .unconditional, help: "The page width in points (requires --page-height).")
        var pageWidth: Double?

        @Option(parsing: .unconditional, help: "The page height in points (requires --page-width).")
        var pageHeight: Double?

        @Option(parsing: .unconditional, help: "The top page margin in points.")
        var marginTop: Double?

        @Option(parsing: .unconditional, help: "The bottom page margin in points.")
        var marginBottom: Double?

        @Option(parsing: .unconditional, help: "The left page margin in points.")
        var marginLeft: Double?

        @Option(parsing: .unconditional, help: "The right page margin in points.")
        var marginRight: Double?

        @Flag(
            inversion: .prefixedNo,
            help: "Use the first-page header/footer for the first page."
        )
        var firstPageHeaderFooter: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: "Use the even-page header/footer for even pages."
        )
        var evenPageHeaderFooter: Bool?

        @Option(help: "The document background color as a hex value like #FFFFFF.")
        var background: String?

        @Option(help: "The document mode: pages or pageless.")
        var mode: DocsDocumentModeArgument?

        @Option(
            parsing: .unconditional,
            help: "The first visible page number (1 or greater)."
        )
        var pageNumberStart: Int?

        @Option(
            parsing: .unconditional,
            help: "The header margin in points (turns on custom header/footer margins)."
        )
        var marginHeader: Double?

        @Option(
            parsing: .unconditional,
            help: "The footer margin in points (turns on custom header/footer margins)."
        )
        var marginFooter: Double?

        @Flag(
            inversion: .prefixedNo,
            help: "Flip the page orientation, swapping width and height (--no- turns it off)."
        )
        var flipOrientation: Bool?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            let hasOption =
                pageWidth != nil || pageHeight != nil || marginTop != nil
                || marginBottom != nil || marginLeft != nil || marginRight != nil
                || firstPageHeaderFooter != nil || evenPageHeaderFooter != nil
                || background != nil || mode != nil || pageNumberStart != nil
                || marginHeader != nil || marginFooter != nil || flipOrientation != nil
            guard hasOption else {
                throw ValidationError("Provide at least one page-setup option.")
            }
            if (pageWidth == nil) != (pageHeight == nil) {
                throw ValidationError(
                    "Provide both --page-width and --page-height, or neither.")
            }
            // A finite value greater than zero: this also rejects NaN and
            // infinity, which Double parsing would otherwise accept.
            func requirePositive(_ value: Double?, _ label: String) throws {
                if let value, !(value.isFinite && value > 0) {
                    throw ValidationError("\(label) must be a finite value greater than zero.")
                }
            }
            try requirePositive(pageWidth, "--page-width")
            try requirePositive(pageHeight, "--page-height")
            try requirePositive(marginTop, "--margin-top")
            try requirePositive(marginBottom, "--margin-bottom")
            try requirePositive(marginLeft, "--margin-left")
            try requirePositive(marginRight, "--margin-right")
            try requirePositive(marginHeader, "--margin-header")
            try requirePositive(marginFooter, "--margin-footer")
            if let pageNumberStart, pageNumberStart < 1 {
                throw ValidationError("--page-number-start must be 1 or greater.")
            }
        }

        func run() async throws {
            let backgroundColor = try background.map { try DocsOptionalColor.parse($0) }
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.updateDocumentStyle(
                documentId: documentID,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                marginTop: marginTop,
                marginBottom: marginBottom,
                marginLeft: marginLeft,
                marginRight: marginRight,
                useFirstPageHeaderFooter: firstPageHeaderFooter,
                useEvenPageHeaderFooter: evenPageHeaderFooter,
                background: backgroundColor,
                documentMode: mode?.documentMode,
                pageNumberStart: pageNumberStart,
                marginHeader: marginHeader,
                marginFooter: marginFooter,
                flipPageOrientation: flipOrientation,
                requiredRevisionId: requireRevision)
            print("Updated the document style.")
        }
    }

    struct SectionStyle: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "section-style",
            abstract: "Set margins, page numbering, direction, and separators for the sections a range overlaps.",
            discussion: """
                Restyles every section the zero-based UTF-16 range --from..<--to \
                overlaps (section style is a body concept, so the range is \
                body-only). Margins are in points. --page-number-start sets the \
                section's first page number (1 or greater). --direction is ltr or \
                rtl. --column-separator is none or between. \
                --first-page-header-footer toggles the section's first-page \
                header/footer (--no- clears it). --flip-orientation swaps the \
                section's page width and height. Every dimension must be a finite \
                value greater than zero, and at least one option is required. The \
                section's header/footer ids and type are read-only, and multi-column \
                layout is not set here.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The zero-based UTF-16 range start (inclusive).")
        var from: Int

        @Option(help: "The zero-based UTF-16 range end (exclusive).")
        var to: Int

        @Option(parsing: .unconditional, help: "The top margin in points.")
        var marginTop: Double?

        @Option(parsing: .unconditional, help: "The bottom margin in points.")
        var marginBottom: Double?

        @Option(parsing: .unconditional, help: "The left margin in points.")
        var marginLeft: Double?

        @Option(parsing: .unconditional, help: "The right margin in points.")
        var marginRight: Double?

        @Option(parsing: .unconditional, help: "The header margin in points.")
        var marginHeader: Double?

        @Option(parsing: .unconditional, help: "The footer margin in points.")
        var marginFooter: Double?

        @Option(help: "The text direction: ltr or rtl.")
        var direction: DocsDirectionArgument?

        @Option(help: "The column separator style: none or between.")
        var columnSeparator: DocsColumnSeparatorArgument?

        @Option(parsing: .unconditional, help: "The section's first page number (1 or greater).")
        var pageNumberStart: Int?

        @Flag(
            inversion: .prefixedNo,
            help: "Use the first-page header/footer for the section (--no- turns it off)."
        )
        var firstPageHeaderFooter: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: "Flip the section orientation, swapping width and height (--no- turns it off)."
        )
        var flipOrientation: Bool?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            let hasOption =
                marginTop != nil || marginBottom != nil || marginLeft != nil
                || marginRight != nil || marginHeader != nil || marginFooter != nil
                || direction != nil || columnSeparator != nil || pageNumberStart != nil
                || firstPageHeaderFooter != nil || flipOrientation != nil
            guard hasOption else {
                throw ValidationError("Provide at least one section-style option.")
            }
            guard from >= 0 else {
                throw ValidationError("--from must be zero or greater.")
            }
            guard to > from else {
                throw ValidationError("--to must be greater than --from.")
            }
            func requirePositive(_ value: Double?, _ label: String) throws {
                if let value, !(value.isFinite && value > 0) {
                    throw ValidationError("\(label) must be a finite value greater than zero.")
                }
            }
            try requirePositive(marginTop, "--margin-top")
            try requirePositive(marginBottom, "--margin-bottom")
            try requirePositive(marginLeft, "--margin-left")
            try requirePositive(marginRight, "--margin-right")
            try requirePositive(marginHeader, "--margin-header")
            try requirePositive(marginFooter, "--margin-footer")
            if let pageNumberStart, pageNumberStart < 1 {
                throw ValidationError("--page-number-start must be 1 or greater.")
            }
        }

        func run() async throws {
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.updateSectionStyle(
                documentId: documentID,
                startIndex: from,
                endIndex: to,
                marginTop: marginTop,
                marginBottom: marginBottom,
                marginLeft: marginLeft,
                marginRight: marginRight,
                marginHeader: marginHeader,
                marginFooter: marginFooter,
                columnSeparatorStyle: columnSeparator?.separatorStyle,
                contentDirection: direction?.direction,
                pageNumberStart: pageNumberStart,
                useFirstPageHeaderFooter: firstPageHeaderFooter,
                flipPageOrientation: flipOrientation,
                requiredRevisionId: requireRevision)
            print("Updated the section style.")
        }
    }

    struct NamedStyle: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "named-style",
            abstract: "Redefine a named style (e.g. what HEADING_2 looks like) document-wide.",
            discussion: """
                Redefines the look of --style (normal-text, title, subtitle, or \
                heading-1 through heading-6) everywhere it is used. The text flags \
                mirror `docs style` (--bold/--italic/--underline/--strike/\
                --small-caps toggles, --color, --background, --size, --font, \
                --font-weight) and the paragraph flags mirror `docs paragraph` \
                (--align, --direction, --line-spacing, --space-above, \
                --space-below, --indent-start, --indent-end, --indent-first-line). \
                At least one text or paragraph flag is required. --tab-id scopes \
                the change to one tab. The baseline offset, link, pagination \
                toggles, shading, and borders are not set here.
                """
        )

        @Argument(help: "The document ID.")
        var documentID: String

        @Option(help: "The named style to redefine: normal-text, title, subtitle, or heading-1..heading-6.")
        var style: DocsNamedStyleArgument

        @Flag(inversion: .prefixedNo, help: "Bold the text (--no-bold turns it off).")
        var bold: Bool?

        @Flag(inversion: .prefixedNo, help: "Italicize the text (--no-italic turns it off).")
        var italic: Bool?

        @Flag(inversion: .prefixedNo, help: "Underline the text (--no-underline turns it off).")
        var underline: Bool?

        @Flag(inversion: .prefixedNo, help: "Strike through the text (--no-strike turns it off).")
        var strike: Bool?

        @Flag(
            inversion: .prefixedNo,
            help: "Render the text in small caps (--no-small-caps turns it off)."
        )
        var smallCaps: Bool?

        @Option(help: "The text color as a hex value like #FF0000.")
        var color: String?

        @Option(help: "The background color as a hex value like #FF0000.")
        var background: String?

        @Option(
            parsing: .unconditional,
            help: "The font size in points; must be greater than zero."
        )
        var size: Double?

        @Option(help: "The font family name, such as Arial.")
        var font: String?

        @Option(
            parsing: .unconditional,
            help: "The font weight, a multiple of 100 from 100 to 900; requires --font."
        )
        var fontWeight: Int?

        @Option(help: "The alignment: start, center, end, or justified.")
        var align: DocsAlignmentArgument?

        @Option(help: "The text direction: ltr or rtl.")
        var direction: DocsDirectionArgument?

        @Option(
            parsing: .unconditional,
            help: "The line spacing as a percent of normal; 100 is single."
        )
        var lineSpacing: Double?

        @Option(parsing: .unconditional, help: "The space above each paragraph in points.")
        var spaceAbove: Double?

        @Option(parsing: .unconditional, help: "The space below each paragraph in points.")
        var spaceBelow: Double?

        @Option(parsing: .unconditional, help: "The start-edge indent in points.")
        var indentStart: Double?

        @Option(parsing: .unconditional, help: "The end-edge indent in points.")
        var indentEnd: Double?

        @Option(parsing: .unconditional, help: "The first-line indent in points.")
        var indentFirstLine: Double?

        @Option(help: "Scope the change to one tab by its id. Omit for a document with no explicit tabs.")
        var tabId: String?

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            let hasStyle =
                bold != nil || italic != nil || underline != nil || strike != nil
                || smallCaps != nil || color != nil || background != nil || size != nil
                || font != nil || fontWeight != nil || align != nil || direction != nil
                || lineSpacing != nil || spaceAbove != nil || spaceBelow != nil
                || indentStart != nil || indentEnd != nil || indentFirstLine != nil
            guard hasStyle else {
                throw ValidationError("Provide at least one text or paragraph style flag.")
            }
            if let fontWeight {
                guard font != nil else {
                    throw ValidationError("--font-weight requires --font.")
                }
                guard (100...900).contains(fontWeight), fontWeight % 100 == 0 else {
                    throw ValidationError(
                        "--font-weight must be a multiple of 100 from 100 to 900.")
                }
            }
            if let size, size <= 0 {
                throw ValidationError("--size must be greater than zero.")
            }
            if let lineSpacing, lineSpacing <= 0 {
                throw ValidationError("--line-spacing must be greater than zero.")
            }
        }

        func run() async throws {
            let foreground = try color.map { try DocsOptionalColor.parse($0) }
            let backgroundColor = try background.map { try DocsOptionalColor.parse($0) }
            let client = DocsClient(api: try CLI.makeAPI())
            _ = try await client.updateNamedStyle(
                documentId: documentID,
                namedStyleType: style.namedStyleType,
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strike,
                foregroundColor: foreground,
                backgroundColor: backgroundColor,
                fontSize: size,
                fontFamily: font,
                fontWeight: fontWeight,
                smallCaps: smallCaps,
                alignment: align?.alignment,
                direction: direction?.direction,
                lineSpacing: lineSpacing,
                spaceAbove: spaceAbove,
                spaceBelow: spaceBelow,
                indentStart: indentStart,
                indentEnd: indentEnd,
                indentFirstLine: indentFirstLine,
                tabId: tabId,
                requiredRevisionId: requireRevision)
            print("Redefined the \(style.namedStyleType) named style.")
        }
    }
}

// MARK: - Docs styling argument enums
//
// These CLI-facing enums map friendly, lower-kebab option values onto the Docs
// v1 wire spellings. The named-style argument maps to the API's SCREAMING_SNAKE
// string that ``DocsClient/styleParagraphs`` validates; the others map to the
// typed ``GrahamKit`` styling enums.

/// CLI-facing baseline-offset names mapping to the API ``DocsBaselineOffset``.
/// `none` maps to the API's `NONE`, so a user resets the baseline with a word
/// that reads naturally.
enum DocsBaselineArgument: String, ExpressibleByArgument {
    case superscript = "super"
    case `subscript` = "sub"
    case normal = "none"

    /// The Docs API baseline offset this argument maps to.
    var baselineOffset: DocsBaselineOffset {
        switch self {
        case .superscript: return .superscript
        case .`subscript`: return .`subscript`
        case .normal: return .none
        }
    }
}

/// CLI-facing named-style names, lower-kebab, mapping to the Docs v1
/// `namedStyleType` wire values. The client validates the returned string, so
/// this stays a thin spelling map.
enum DocsNamedStyleArgument: String, ExpressibleByArgument {
    case normalText = "normal-text"
    case title
    case subtitle
    case heading1 = "heading-1"
    case heading2 = "heading-2"
    case heading3 = "heading-3"
    case heading4 = "heading-4"
    case heading5 = "heading-5"
    case heading6 = "heading-6"

    /// The Docs API `namedStyleType` this argument maps to.
    var namedStyleType: String {
        switch self {
        case .normalText: return "NORMAL_TEXT"
        case .title: return "TITLE"
        case .subtitle: return "SUBTITLE"
        case .heading1: return "HEADING_1"
        case .heading2: return "HEADING_2"
        case .heading3: return "HEADING_3"
        case .heading4: return "HEADING_4"
        case .heading5: return "HEADING_5"
        case .heading6: return "HEADING_6"
        }
    }
}

/// CLI-facing heading-level names for the `docs heading` shortcut: a bare level
/// 1-6, or the body-style words title, subtitle, and normal.
enum DocsHeadingLevelArgument: String, ExpressibleByArgument {
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case title
    case subtitle
    case normal

    /// The Docs API `namedStyleType` this level maps to.
    var namedStyleType: String {
        switch self {
        case .one: return "HEADING_1"
        case .two: return "HEADING_2"
        case .three: return "HEADING_3"
        case .four: return "HEADING_4"
        case .five: return "HEADING_5"
        case .six: return "HEADING_6"
        case .title: return "TITLE"
        case .subtitle: return "SUBTITLE"
        case .normal: return "NORMAL_TEXT"
        }
    }
}

/// CLI-facing paragraph-alignment names mapping to the API
/// ``DocsParagraphAlignment``.
enum DocsAlignmentArgument: String, ExpressibleByArgument {
    case start
    case center
    case end
    case justified

    /// The Docs API paragraph alignment this argument maps to.
    var alignment: DocsParagraphAlignment {
        switch self {
        case .start: return .start
        case .center: return .center
        case .end: return .end
        case .justified: return .justified
        }
    }
}

/// CLI-facing text-direction names mapping to the API ``DocsContentDirection``.
/// The user types the familiar `ltr`/`rtl` abbreviations.
enum DocsDirectionArgument: String, ExpressibleByArgument {
    case ltr
    case rtl

    /// The Docs API content direction this argument maps to.
    var direction: DocsContentDirection {
        switch self {
        case .ltr: return .leftToRight
        case .rtl: return .rightToLeft
        }
    }
}

/// CLI-facing section column-separator names mapping to the API
/// ``DocsColumnSeparatorStyle``. The user types the natural none/between words.
enum DocsColumnSeparatorArgument: String, ExpressibleByArgument {
    case none
    case between

    /// The Docs API column separator style this argument maps to.
    var separatorStyle: DocsColumnSeparatorStyle {
        switch self {
        case .none: return .none
        case .between: return .betweenEachColumn
        }
    }
}

/// CLI-facing table-cell content-alignment names mapping to the API
/// ``DocsContentAlignment``. The user types the natural top/middle/bottom words.
enum DocsContentAlignmentArgument: String, ExpressibleByArgument {
    case top
    case middle
    case bottom

    /// The Docs API content alignment this argument maps to.
    var contentAlignment: DocsContentAlignment {
        switch self {
        case .top: return .top
        case .middle: return .middle
        case .bottom: return .bottom
        }
    }
}

/// CLI-facing table-cell border dash-style names mapping to the API
/// ``DocsDashStyle`` — solid, dot, and dash, the complete writable Docs set.
enum DocsDashStyleArgument: String, ExpressibleByArgument {
    case solid
    case dot
    case dash

    /// The Docs API dash style this argument maps to.
    var dashStyle: DocsDashStyle {
        switch self {
        case .solid: return .solid
        case .dot: return .dot
        case .dash: return .dash
        }
    }
}

/// CLI-facing bullet-preset names, lower-kebab, mapping to the Docs v1
/// `BulletGlyphPreset` wire values. Each case maps to a ``DocsBulletPreset``
/// case, so the exact API spelling has a single source of truth (the GrahamKit
/// enum's raw value) and never drifts from it. The client validates the string
/// this produces.
enum DocsBulletPresetArgument: String, ExpressibleByArgument, CaseIterable {
    case discCircleSquare = "disc-circle-square"
    case diamondxArrow3dSquare = "diamondx-arrow3d-square"
    case checkbox
    case arrowDiamondDisc = "arrow-diamond-disc"
    case starCircleSquare = "star-circle-square"
    case arrow3dCircleSquare = "arrow3d-circle-square"
    case lefttriangleDiamondDisc = "lefttriangle-diamond-disc"
    case diamondxHollowdiamondSquare = "diamondx-hollowdiamond-square"
    case diamondCircleSquare = "diamond-circle-square"
    case decimalAlphaRoman = "decimal-alpha-roman"
    case decimalAlphaRomanParens = "decimal-alpha-roman-parens"
    case decimalNested = "decimal-nested"
    case upperalphaAlphaRoman = "upperalpha-alpha-roman"
    case upperromanUpperalphaDecimal = "upperroman-upperalpha-decimal"
    case zerodecimalAlphaRoman = "zerodecimal-alpha-roman"

    /// The typed Docs API preset this argument maps to.
    var preset: DocsBulletPreset {
        switch self {
        case .discCircleSquare: return .bulletDiscCircleSquare
        case .diamondxArrow3dSquare: return .bulletDiamondxArrow3dSquare
        case .checkbox: return .bulletCheckbox
        case .arrowDiamondDisc: return .bulletArrowDiamondDisc
        case .starCircleSquare: return .bulletStarCircleSquare
        case .arrow3dCircleSquare: return .bulletArrow3dCircleSquare
        case .lefttriangleDiamondDisc: return .bulletLefttriangleDiamondDisc
        case .diamondxHollowdiamondSquare: return .bulletDiamondxHollowdiamondSquare
        case .diamondCircleSquare: return .bulletDiamondCircleSquare
        case .decimalAlphaRoman: return .numberedDecimalAlphaRoman
        case .decimalAlphaRomanParens: return .numberedDecimalAlphaRomanParens
        case .decimalNested: return .numberedDecimalNested
        case .upperalphaAlphaRoman: return .numberedUpperalphaAlphaRoman
        case .upperromanUpperalphaDecimal: return .numberedUpperromanUpperalphaDecimal
        case .zerodecimalAlphaRoman: return .numberedZerodecimalAlphaRoman
        }
    }

    /// The Docs API `bulletPreset` wire value this argument maps to.
    var bulletPreset: String { preset.rawValue }
}

/// CLI-facing section-type names, lower-kebab, mapping to the Docs v1
/// `SectionType` wire values. The client validates the returned string, so this
/// stays a thin spelling map — `next-page` becomes the wire spelling `NEXT_PAGE`
/// (a bare uppercasing of the kebab value would wrongly yield `NEXT-PAGE`).
enum DocsSectionTypeArgument: String, ExpressibleByArgument {
    case continuous
    case nextPage = "next-page"

    /// The Docs API `sectionType` this argument maps to.
    var sectionType: String {
        switch self {
        case .continuous: return "CONTINUOUS"
        case .nextPage: return "NEXT_PAGE"
        }
    }
}

/// CLI-facing document-mode names mapping to the API ``DocsDocumentMode`` — pages
/// or pageless, the writable `DocumentFormat.documentMode` values.
enum DocsDocumentModeArgument: String, ExpressibleByArgument {
    case pages
    case pageless

    /// The Docs API document mode this argument maps to.
    var documentMode: DocsDocumentMode {
        switch self {
        case .pages: return .pages
        case .pageless: return .pageless
        }
    }
}

/// CLI-facing paragraph spacing-mode names, lower-kebab, mapping to the API
/// ``DocsSpacingMode`` — never-collapse or collapse-lists, the writable
/// `ParagraphStyle.spacingMode` values.
enum DocsSpacingModeArgument: String, ExpressibleByArgument {
    case neverCollapse = "never-collapse"
    case collapseLists = "collapse-lists"

    /// The Docs API spacing mode this argument maps to.
    var spacingMode: DocsSpacingMode {
        switch self {
        case .neverCollapse: return .neverCollapse
        case .collapseLists: return .collapseLists
        }
    }
}
