import ArgumentParser
import Foundation
import GrahamKit

struct Docs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Docs documents.",
        subcommands: [
            Create.self, Cat.self, Structure.self, Insert.self, Delete.self,
            Replace.self, Style.self, Paragraph.self, Heading.self, Bullets.self,
            Unbullet.self, Images.self,
        ]
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

    struct Style: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Style a range of text: bold, colors, font, link, and so on.",
            discussion: """
                Sets the character style of a zero-based UTF-16 range from --from
                up to but not including --to; at least one style flag is required.
                --bold, --italic, --underline, and --strike are toggles: pass the
                flag to turn it on, or its --no- form (for example --no-bold) to
                turn it off. Colors are a hex value like #FF0000. --size is in
                points and --font names a family, with an optional --font-weight
                (a multiple of 100 from 100 to 900). --baseline is super, sub, or
                none. In a named segment (--segment) the content starts at index
                0. Get index ranges from `docs structure`.
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
                || color != nil || background != nil || size != nil || font != nil
                || fontWeight != nil || baseline != nil || link != nil
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
                spacing and indents are in points. In a named segment (--segment)
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

        @Option(help: "Require the document be at this revision id; the write fails otherwise.")
        var requireRevision: String?

        func validate() throws {
            let hasStyle =
                style != nil || align != nil || direction != nil || lineSpacing != nil
                || spaceAbove != nil || spaceBelow != nil || indentStart != nil
                || indentEnd != nil || indentFirstLine != nil
            guard hasStyle else {
                throw ValidationError("Provide at least one style flag.")
            }
            if let lineSpacing, lineSpacing <= 0 {
                throw ValidationError("--line-spacing must be greater than zero.")
            }
        }

        func run() async throws {
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
