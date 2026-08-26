import Foundation

/// A Google Docs document, mirroring the Docs v1 `Document` resource. Only the
/// fields graham reads are modeled; the decoder ignores all other fields. Every
/// field is optional except none — a partial or new response shape does not
/// sink the whole decode.
///
/// The maps below are keyed exactly as the API keys them: an id string to the
/// object it names. `headers`, `footers`, and `footnotes` are the named
/// segments a segment-aware write can target; `inlineObjects` and
/// `positionedObjects` carry the images a later `docs images` command reads;
/// `lists` backs bullet rendering; `namedRanges` and `namedStyles` and
/// `documentStyle` round out the read surface.
public struct Document: Codable, Sendable {
    public let documentId: String?
    public let title: String?
    public let body: DocumentBody?
    /// The revision the document is currently at; feeds `WriteControl` for
    /// optimistic concurrency on a follow-up write.
    public let revisionId: String?
    /// Lists in the document, keyed by list id; a paragraph's ``DocBullet``
    /// names its list here.
    public let lists: [String: DocList]?
    /// Inline images and other embedded objects, keyed by object id.
    public let inlineObjects: [String: DocInlineObject]?
    /// Positioned (floating) images and embedded objects, keyed by object id.
    public let positionedObjects: [String: DocPositionedObject]?
    /// The document headers, keyed by header id.
    public let headers: [String: DocHeader]?
    /// The document footers, keyed by footer id.
    public let footers: [String: DocFooter]?
    /// The document footnotes, keyed by footnote id.
    public let footnotes: [String: DocFootnote]?
    /// Named ranges, keyed by name; each entry can hold several ranges.
    public let namedRanges: [String: DocNamedRanges]?
    /// The document's named styles (how `HEADING_1`, `TITLE`, ... render).
    public let namedStyles: DocNamedStyles?
    /// The document-wide style: page size, margins, header/footer flags.
    public let documentStyle: DocDocumentStyle?

    /// The document text, in reading order. Tables render one row per line
    /// with tab-separated cells.
    public var plainText: String {
        (body?.content ?? []).map(\.plainText).joined()
    }
}

public struct DocumentBody: Codable, Sendable {
    public let content: [StructuralElement]?
}

/// One block in a document body (or in a header, footer, footnote, or table
/// cell): a paragraph, a table, a section break, or a table of contents.
///
/// `startIndex` and `endIndex` are the block's zero-based, half-open range in
/// UTF-16 code units, exactly as the API reports them. The API omits
/// `startIndex` when it is 0, so an absent start means index 0 (only the very
/// first body element).
public struct StructuralElement: Codable, Sendable {
    public let startIndex: Int?
    public let endIndex: Int?
    public let paragraph: DocParagraph?
    public let table: DocTable?
    public let sectionBreak: DocSectionBreak?
    public let tableOfContents: DocTableOfContents?

    var plainText: String {
        if let paragraph {
            return paragraph.text
        }
        if let table {
            return table.plainText
        }
        return ""
    }
}

public struct DocParagraph: Codable, Sendable {
    public let elements: [DocParagraphElement]?
    /// The paragraph's style: its named style (`HEADING_1`, `TITLE`, ...),
    /// heading id, alignment, and text direction.
    public let paragraphStyle: DocParagraphStyle?
    /// Present when the paragraph is a list item; names its list and level.
    public let bullet: DocBullet?
    /// The ids of positioned objects anchored to this paragraph.
    public let positionedObjectIds: [String]?

    /// The paragraph's plain text: the content of its text runs, joined. Other
    /// element kinds (inline objects, breaks, footnote references) contribute no
    /// text, matching the previous behaviour of ``StructuralElement/plainText``.
    public var text: String {
        (elements ?? []).compactMap { $0.textRun?.content }.joined()
    }

    /// Every object id this paragraph references: its anchored positioned
    /// objects first, then the inline objects its elements embed, in reading
    /// order. Lets ``DocBlockRow`` and a later `docs images` command correlate a
    /// paragraph with the images in ``Document/inlineObjects`` and
    /// ``Document/positionedObjects``.
    public var referencedObjectIds: [String] {
        var ids = positionedObjectIds ?? []
        ids += (elements ?? []).compactMap { $0.inlineObjectElement?.inlineObjectId }
        return ids
    }
}

/// One inline part of a paragraph. Exactly one variant field is set; ``kind``
/// reports which. A text run carries the visible text; the other variants are
/// inline objects, breaks, rules, references, and smart chips.
public struct DocParagraphElement: Codable, Sendable {
    public let startIndex: Int?
    public let endIndex: Int?
    public let textRun: DocTextRun?
    public let inlineObjectElement: DocInlineObjectElement?
    public let pageBreak: DocPageBreak?
    public let columnBreak: DocColumnBreak?
    public let horizontalRule: DocHorizontalRule?
    public let footnoteReference: DocFootnoteReference?
    public let equation: DocEquation?
    public let autoText: DocAutoText?
    public let person: DocPerson?
    public let richLink: DocRichLink?
    public let dateElement: DocDateElement?

    /// The kind of this element, or ``DocParagraphElementKind/unknown`` when a
    /// new or unmodeled variant is set.
    public var kind: DocParagraphElementKind {
        if textRun != nil { return .textRun }
        if inlineObjectElement != nil { return .inlineObjectElement }
        if pageBreak != nil { return .pageBreak }
        if columnBreak != nil { return .columnBreak }
        if horizontalRule != nil { return .horizontalRule }
        if footnoteReference != nil { return .footnoteReference }
        if equation != nil { return .equation }
        if autoText != nil { return .autoText }
        if person != nil { return .person }
        if richLink != nil { return .richLink }
        if dateElement != nil { return .dateElement }
        return .unknown
    }
}

/// The kind of a ``DocParagraphElement``.
public enum DocParagraphElementKind: String, Codable, Sendable, Equatable {
    case textRun
    case inlineObjectElement
    case pageBreak
    case columnBreak
    case horizontalRule
    case footnoteReference
    case equation
    case autoText
    case person
    case richLink
    case dateElement
    case unknown
}

public struct DocTextRun: Codable, Sendable {
    public let content: String?
    /// The run's style: bold, italic, underline, strikethrough, baseline
    /// offset, hyperlink, font size, and font family.
    public let textStyle: DocTextStyle?
}

public struct DocTable: Codable, Sendable {
    /// The number of rows in the table.
    public let rows: Int?
    /// The number of columns in the table.
    public let columns: Int?
    public let tableRows: [DocTableRow]?

    var plainText: String {
        let rows = (tableRows ?? []).map { row in
            (row.tableCells ?? [])
                .map { cell in
                    (cell.content ?? [])
                        .map(\.plainText)
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .joined(separator: "\t")
        }
        return rows.isEmpty ? "" : rows.joined(separator: "\n") + "\n"
    }
}

public struct DocTableRow: Codable, Sendable {
    /// The row's zero-based start index in UTF-16 code units.
    public let startIndex: Int?
    /// The row's zero-based end index (exclusive) in UTF-16 code units.
    public let endIndex: Int?
    public let tableCells: [DocTableCell]?
}

public struct DocTableCell: Codable, Sendable {
    /// The cell's zero-based start index in UTF-16 code units.
    public let startIndex: Int?
    /// The cell's zero-based end index (exclusive) in UTF-16 code units.
    public let endIndex: Int?
    public let content: [StructuralElement]?
}

// MARK: - Paragraph and text styles

/// A paragraph's style. graham reads the subset the structured facade and a
/// later Markdown renderer need; every field is optional and decoded
/// defensively.
public struct DocParagraphStyle: Codable, Sendable {
    /// The named style, for example `HEADING_1`, `TITLE`, or `NORMAL_TEXT`.
    public let namedStyleType: String?
    /// The id of the heading this paragraph is, if any.
    public let headingId: String?
    /// The paragraph alignment, for example `START`, `CENTER`, or `JUSTIFIED`.
    public let alignment: String?
    /// The text direction, for example `LEFT_TO_RIGHT`.
    public let direction: String?
}

/// The bullet on a list paragraph: which list it belongs to, how deeply it
/// nests, and the style of its glyph.
public struct DocBullet: Codable, Sendable {
    /// The id of the list in ``Document/lists`` this bullet belongs to.
    public let listId: String?
    /// The zero-based nesting level of the bullet.
    public let nestingLevel: Int?
    public let textStyle: DocTextStyle?
}

/// The style of a text run. graham reads the subset needed to render text and,
/// later, Markdown: the toggles, the baseline offset, the hyperlink, the font
/// size, and the font family.
public struct DocTextStyle: Codable, Sendable {
    public let bold: Bool?
    public let italic: Bool?
    public let underline: Bool?
    public let strikethrough: Bool?
    /// The baseline offset, for example `SUPERSCRIPT`, `SUBSCRIPT`, or `NONE`.
    public let baselineOffset: String?
    /// The hyperlink on the run, if any.
    public let link: DocLink?
    public let fontSize: DocDimension?
    public let weightedFontFamily: DocWeightedFontFamily?
}

/// A hyperlink. A web link sets ``url``; the other fields target a heading,
/// bookmark, or tab within the document.
public struct DocLink: Codable, Sendable {
    /// The URL of an external link.
    public let url: String?
    /// The id of a heading this link targets.
    public let headingId: String?
    /// The id of a bookmark this link targets.
    public let bookmarkId: String?
    /// The id of a tab this link targets.
    public let tabId: String?
}

/// A font family plus a numeric weight.
public struct DocWeightedFontFamily: Codable, Sendable {
    public let fontFamily: String?
    /// The weight, a multiple of 100 from 100 to 900.
    public let weight: Int?
}

/// A length: a magnitude and its unit (`PT` or `UNIT_UNSPECIFIED`).
public struct DocDimension: Codable, Sendable {
    public let magnitude: Double?
    public let unit: String?
}

/// The width and height of an object.
public struct DocSize: Codable, Sendable {
    public let width: DocDimension?
    public let height: DocDimension?
}

// MARK: - Paragraph element variants

/// An inline object (usually an image) placed in the text. ``inlineObjectId``
/// keys into ``Document/inlineObjects`` for the object's image data and size.
public struct DocInlineObjectElement: Codable, Sendable {
    public let inlineObjectId: String?
    public let textStyle: DocTextStyle?
}

/// A page break. It renders no text.
public struct DocPageBreak: Codable, Sendable {
    public let textStyle: DocTextStyle?
}

/// A column break. It renders no text.
public struct DocColumnBreak: Codable, Sendable {
    public let textStyle: DocTextStyle?
}

/// A horizontal rule. It renders no text.
public struct DocHorizontalRule: Codable, Sendable {
    public let textStyle: DocTextStyle?
}

/// An equation. graham does not read its content.
public struct DocEquation: Codable, Sendable {}

/// A reference to a footnote. ``footnoteId`` keys into ``Document/footnotes``;
/// ``footnoteNumber`` is the number the reader shows.
public struct DocFootnoteReference: Codable, Sendable {
    public let footnoteId: String?
    public let footnoteNumber: String?
    public let textStyle: DocTextStyle?
}

/// Auto-generated text, for example a page number. ``type`` names the kind.
public struct DocAutoText: Codable, Sendable {
    public let type: String?
    public let textStyle: DocTextStyle?
}

/// A person smart chip. ``personProperties`` carries the display name and email.
public struct DocPerson: Codable, Sendable {
    public let personId: String?
    public let personProperties: DocPersonProperties?
    public let textStyle: DocTextStyle?
}

/// The display name and email of a ``DocPerson``.
public struct DocPersonProperties: Codable, Sendable {
    public let name: String?
    public let email: String?
}

/// A rich-link smart chip (a Drive file, a URL, and so on).
/// ``richLinkProperties`` carries the title and URI a reader shows.
public struct DocRichLink: Codable, Sendable {
    public let richLinkId: String?
    public let richLinkProperties: DocRichLinkProperties?
    public let textStyle: DocTextStyle?
}

/// The title, URI, and MIME type of a ``DocRichLink``.
public struct DocRichLinkProperties: Codable, Sendable {
    public let title: String?
    public let uri: String?
    public let mimeType: String?
}

/// A date smart chip. ``dateElementProperties`` carries the display text and
/// the formatting.
public struct DocDateElement: Codable, Sendable {
    public let dateId: String?
    public let dateElementProperties: DocDateElementProperties?
    public let textStyle: DocTextStyle?
}

/// The display text and formatting of a ``DocDateElement``.
public struct DocDateElementProperties: Codable, Sendable {
    public let displayText: String?
    public let timestamp: String?
    public let locale: String?
    public let timeZoneId: String?
    public let dateFormat: String?
    public let timeFormat: String?
}

// MARK: - Structural element variants

/// A section break. graham reports its presence; a later phase reads its style.
public struct DocSectionBreak: Codable, Sendable {}

/// A table of contents. Its ``content`` holds the generated entries as more
/// structural elements.
public struct DocTableOfContents: Codable, Sendable {
    public let content: [StructuralElement]?
}

// MARK: - Objects and segments

/// An inline object, keyed in ``Document/inlineObjects``. Its embedded object
/// (image) is reached through ``embeddedObject``.
public struct DocInlineObject: Codable, Sendable {
    public let objectId: String?
    public let inlineObjectProperties: DocInlineObjectProperties?

    /// The embedded object (image) this inline object holds.
    public var embeddedObject: DocEmbeddedObject? {
        inlineObjectProperties?.embeddedObject
    }
}

public struct DocInlineObjectProperties: Codable, Sendable {
    public let embeddedObject: DocEmbeddedObject?
}

/// A positioned (floating) object, keyed in ``Document/positionedObjects``.
/// Its embedded object (image) is reached through ``embeddedObject``.
public struct DocPositionedObject: Codable, Sendable {
    public let objectId: String?
    public let positionedObjectProperties: DocPositionedObjectProperties?

    /// The embedded object (image) this positioned object holds.
    public var embeddedObject: DocEmbeddedObject? {
        positionedObjectProperties?.embeddedObject
    }
}

public struct DocPositionedObjectProperties: Codable, Sendable {
    public let embeddedObject: DocEmbeddedObject?
}

/// An embedded object: an image with its size, alt text, and — for an image —
/// its source and content URIs. A later `docs images` command reads
/// ``imageProperties`` and ``size``.
public struct DocEmbeddedObject: Codable, Sendable {
    public let title: String?
    public let description: String?
    public let imageProperties: DocImageProperties?
    public let size: DocSize?
}

/// The image data of an embedded object. ``sourceUri`` is the URI the image was
/// created from; ``contentUri`` is a short-lived, pre-authorized download URL
/// (fetched without an OAuth header, like the Slides content URL).
public struct DocImageProperties: Codable, Sendable {
    public let sourceUri: String?
    public let contentUri: String?
}

/// A list, keyed in ``Document/lists``. Its ``listProperties`` describe each
/// nesting level's glyph, which a Markdown renderer uses to pick ordered
/// versus unordered markers.
public struct DocList: Codable, Sendable {
    public let listProperties: DocListProperties?
}

public struct DocListProperties: Codable, Sendable {
    public let nestingLevels: [DocNestingLevel]?
}

/// One nesting level of a list. ``glyphType`` (for example `DECIMAL`, `ALPHA`,
/// `ROMAN`, or an unset value for a bullet) tells a renderer whether the level
/// is ordered.
public struct DocNestingLevel: Codable, Sendable {
    public let glyphType: String?
    public let glyphFormat: String?
    public let glyphSymbol: String?
    public let startNumber: Int?
    public let textStyle: DocTextStyle?
}

/// A document header segment.
public struct DocHeader: Codable, Sendable {
    public let headerId: String?
    public let content: [StructuralElement]?

    /// The header text, in reading order.
    public var plainText: String {
        (content ?? []).map(\.plainText).joined()
    }
}

/// A document footer segment.
public struct DocFooter: Codable, Sendable {
    public let footerId: String?
    public let content: [StructuralElement]?

    /// The footer text, in reading order.
    public var plainText: String {
        (content ?? []).map(\.plainText).joined()
    }
}

/// A document footnote segment.
public struct DocFootnote: Codable, Sendable {
    public let footnoteId: String?
    public let content: [StructuralElement]?

    /// The footnote text, in reading order.
    public var plainText: String {
        (content ?? []).map(\.plainText).joined()
    }
}

/// The named ranges that share one name, keyed by that name in
/// ``Document/namedRanges``.
public struct DocNamedRanges: Codable, Sendable {
    public let name: String?
    public let namedRanges: [DocNamedRange]?
}

/// One named range: an id, a name, and the ranges it covers.
public struct DocNamedRange: Codable, Sendable {
    public let namedRangeId: String?
    public let name: String?
    public let ranges: [DocRange]?
}

/// A range of content in a segment, half-open in UTF-16 code units.
public struct DocRange: Codable, Sendable, Equatable {
    public let startIndex: Int?
    public let endIndex: Int?
    /// The segment the range lives in; empty or nil is the document body.
    public let segmentId: String?
    /// The tab the range lives in; keeps a named range's tab association when a
    /// document uses tabs.
    public let tabId: String?
}

/// The document's named styles.
public struct DocNamedStyles: Codable, Sendable {
    public let styles: [DocNamedStyle]?
}

/// One named style: how a `namedStyleType` such as `HEADING_1` renders.
public struct DocNamedStyle: Codable, Sendable {
    public let namedStyleType: String?
    public let paragraphStyle: DocParagraphStyle?
    public let textStyle: DocTextStyle?
}

/// The document-wide style. graham reads the subset a later page-setup command
/// and reader need; every field is optional and decoded defensively.
public struct DocDocumentStyle: Codable, Sendable {
    public let pageSize: DocSize?
    public let marginTop: DocDimension?
    public let marginBottom: DocDimension?
    public let marginLeft: DocDimension?
    public let marginRight: DocDimension?
    /// Whether the first page uses its own header and footer.
    public let useFirstPageHeaderFooter: Bool?
    /// Whether even pages use their own header and footer.
    public let useEvenPageHeaderFooter: Bool?
}

// MARK: - Structured read facade (the flattened block view)
//
// The models above mirror the Docs v1 wire schema. The types below are the
// reader's view: one flat row per structural element that a command renders in
// any ``OutputFormat``. Like ``Presentation/elementRows`` flattens a slide's
// element tree (a group before its children), ``Document/blockRows`` flattens
// the body's block tree (a table before the blocks inside its cells). All the
// flattening and extraction lives here in GrahamKit, so the CLI stays thin.

/// The kind of a document block.
public enum DocBlockKind: String, Codable, Sendable, Equatable {
    /// A plain paragraph.
    case paragraph
    /// A paragraph whose named style is `TITLE` or `HEADING_1`..`HEADING_6`.
    case heading
    /// A paragraph carrying a bullet (a list item).
    case listItem
    /// A table (its cell contents follow as nested rows).
    case table
    /// A section break.
    case sectionBreak
    /// A table of contents.
    case tableOfContents
    /// A block whose kind graham does not model.
    case unknown
}

/// One document block, flattened out of the body tree.
///
/// A table appears as its own row (``kind`` is ``DocBlockKind/table``) and each
/// structural element inside its cells appears as its own row too, with
/// ``depth`` increased — the Docs analog of a Slides group and its children. A
/// table row carries no text of its own; the cell blocks carry it, so nothing
/// is double-counted.
///
/// The indices are the API's zero-based UTF-16 offsets, reported as-is because
/// they are exactly the values the range-based write commands consume.
public struct DocBlockRow: Codable, Sendable, Equatable {
    /// The block's zero-based start index in UTF-16 code units. Absent only for
    /// the first body element, whose start the API omits (it is 0).
    public let startIndex: Int?
    /// The block's zero-based end index (exclusive) in UTF-16 code units.
    public let endIndex: Int?
    /// The block kind.
    public let kind: DocBlockKind
    /// The nesting depth: `0` for a body block, `1` for a block inside a table
    /// cell, and so on for a table nested in a cell.
    public let depth: Int
    /// The paragraph's named style, for example `HEADING_2` or `NORMAL_TEXT`;
    /// `nil` for a non-paragraph block or a paragraph with no named style.
    public let namedStyleType: String?
    /// The heading level 1...6 for `HEADING_1`..`HEADING_6`; `nil` otherwise
    /// (including `TITLE`, whose ``kind`` is still ``DocBlockKind/heading``).
    public let headingLevel: Int?
    /// The id of the list a list-item block belongs to; `nil` otherwise.
    public let listId: String?
    /// The zero-based nesting level of a list-item block; `nil` otherwise.
    public let nestingLevel: Int?
    /// Every object id the block references (anchored positioned objects, then
    /// embedded inline objects), to correlate with ``Document/inlineObjects``
    /// and ``Document/positionedObjects``.
    public let objectIds: [String]
    /// A short, single-line text preview of the block. Empty for a table (its
    /// text is on the cell rows), a section break, and a table of contents.
    public let preview: String

    init(element: StructuralElement, depth: Int) {
        startIndex = element.startIndex
        endIndex = element.endIndex
        self.depth = depth

        var kind: DocBlockKind = .unknown
        var namedStyleType: String?
        var headingLevel: Int?
        var listId: String?
        var nestingLevel: Int?
        var objectIds: [String] = []
        var preview = ""

        if let paragraph = element.paragraph {
            namedStyleType = paragraph.paragraphStyle?.namedStyleType
            listId = paragraph.bullet?.listId
            nestingLevel = paragraph.bullet?.nestingLevel
            headingLevel = Self.headingLevel(forNamedStyleType: namedStyleType)
            objectIds = paragraph.referencedObjectIds
            preview = Self.oneLine(
                paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines))
            // A bullet makes the block a list item even when it also carries a
            // heading style; the style is still reported in `namedStyleType`.
            if paragraph.bullet != nil {
                kind = .listItem
            } else if Self.isHeading(namedStyleType) {
                kind = .heading
            } else {
                kind = .paragraph
            }
        } else if element.table != nil {
            kind = .table
        } else if element.sectionBreak != nil {
            kind = .sectionBreak
        } else if element.tableOfContents != nil {
            kind = .tableOfContents
        }

        self.kind = kind
        self.namedStyleType = namedStyleType
        self.headingLevel = headingLevel
        self.listId = listId
        self.nestingLevel = nestingLevel
        self.objectIds = objectIds
        self.preview = preview
    }

    /// The heading level 1...6 for a `HEADING_1`..`HEADING_6` named style, or
    /// `nil` for any other style (including `TITLE`). Only levels 1 through 6
    /// exist, so a name like `HEADING_0` or `HEADING_7` parses to `nil` and is
    /// therefore not treated as a heading.
    static func headingLevel(forNamedStyleType named: String?) -> Int? {
        guard let named, named.hasPrefix("HEADING_") else { return nil }
        guard let level = Int(named.dropFirst("HEADING_".count)), (1...6).contains(level) else {
            return nil
        }
        return level
    }

    /// Whether a named style is a heading: `TITLE` or `HEADING_1`..`HEADING_6`.
    /// These are the styles the Markdown renderer maps to `#`..`######`.
    static func isHeading(_ named: String?) -> Bool {
        guard let named else { return false }
        return named == "TITLE" || headingLevel(forNamedStyleType: named) != nil
    }

    /// Collapses text to a single trimmed line for a table cell, so a tab or a
    /// newline never breaks the row layout. Mirrors the Slides reader's helper.
    static func oneLine(_ text: String, limit: Int = 60) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " / ")
            .replacingOccurrences(of: "\t", with: " ")
        if flat.count <= limit { return flat }
        return String(flat.prefix(limit - 1)) + "\u{2026}"
    }
}

extension Document {
    /// Every block in the document body, flattened depth-first.
    ///
    /// The order is body order; a table is followed immediately by the blocks
    /// inside its cells (row by row, cell by cell), and those recurse for a
    /// table nested in a cell. This order is deterministic, so the output is
    /// stable. Headers, footers, and footnotes are separate segments and are
    /// not included; ``plainText`` and the write commands are body-scoped too.
    public var blockRows: [DocBlockRow] {
        var rows: [DocBlockRow] = []
        for element in body?.content ?? [] {
            Self.flatten(element, depth: 0, into: &rows)
        }
        return rows
    }

    private static func flatten(
        _ element: StructuralElement,
        depth: Int,
        into rows: inout [DocBlockRow]
    ) {
        rows.append(DocBlockRow(element: element, depth: depth))
        // Recurse into a table's cells, the way `elementRows` recurses into a
        // group's children: each cell's content blocks are listed at depth + 1.
        for row in element.table?.tableRows ?? [] {
            for cell in row.tableCells ?? [] {
                for child in cell.content ?? [] {
                    flatten(child, depth: depth + 1, into: &rows)
                }
            }
        }
    }
}

// MARK: - Block row rendering

extension DocBlockRow: GrahamRow {
    public static var tableColumns: [String] {
        ["RANGE", "KIND", "STYLE", "LIST", "NEST", "OBJECTS", "TEXT"]
    }

    public var tableValues: [String] {
        [
            rangeText,
            // Indent by nesting depth so a table cell's blocks read as nested.
            String(repeating: "  ", count: depth) + kind.rawValue,
            namedStyleType ?? "",
            listId ?? "",
            nestingLevel.map(String.init) ?? "",
            objectIds.joined(separator: ","),
            preview,
        ]
    }

    /// `--format id` prints the block's start index, one per line — the
    /// zero-based UTF-16 offset a range-based write consumes.
    public var idValue: String { String(startIndex ?? 0) }

    /// The index range as `start-end`. An absent start reads as 0 (only the
    /// first body block, whose start the API omits).
    var rangeText: String {
        let start = startIndex ?? 0
        let end = endIndex.map(String.init) ?? ""
        return "\(start)-\(end)"
    }
}

// MARK: - Image list facade

/// Whether an image lives inline in the text (``Document/inlineObjects``) or is
/// a positioned, floating object (``Document/positionedObjects``).
public enum DocImageOrigin: String, Codable, Sendable, Equatable {
    /// An image that flows with the text.
    case inline
    /// A floating image anchored to a paragraph.
    case positioned
}

/// One image in a document, flattened out of ``Document/inlineObjects`` and
/// ``Document/positionedObjects``.
///
/// Each row carries the object id, its ``origin``, the image size, and the two
/// URIs Docs exposes for an image: ``sourceUri`` (the URI the image was created
/// from) and ``contentUri`` (a short-lived, pre-authorized download URL on a
/// Google user-content host). A download needs ``contentUri``; it is fetched
/// with a plain GET and no OAuth header, exactly like the Slides content URL —
/// see ``DocsClient/downloadImage(from:)``.
public struct DocImageRow: Codable, Sendable, Equatable {
    /// The object id, keyed in the document's inline or positioned object map.
    public let objectId: String?
    /// Whether the image is inline or positioned.
    public let origin: DocImageOrigin
    /// The image width magnitude, in the unit named by ``widthUnit`` (Docs
    /// reports points); `nil` when the response omits the size.
    public let width: Double?
    /// The image height magnitude, in the unit named by ``heightUnit``.
    public let height: Double?
    /// The unit of ``width`` (for example `PT`), as the API reports it.
    public let widthUnit: String?
    /// The unit of ``height``.
    public let heightUnit: String?
    /// The URI the image was created from, if Google keeps it.
    public let sourceUri: String?
    /// The short-lived, pre-authorized content URL. `nil` when the response
    /// omits it; a download needs it.
    public let contentUri: String?

    init(objectId: String?, origin: DocImageOrigin, embeddedObject: DocEmbeddedObject?) {
        self.objectId = objectId
        self.origin = origin
        width = embeddedObject?.size?.width?.magnitude
        height = embeddedObject?.size?.height?.magnitude
        widthUnit = embeddedObject?.size?.width?.unit
        heightUnit = embeddedObject?.size?.height?.unit
        sourceUri = embeddedObject?.imageProperties?.sourceUri
        contentUri = embeddedObject?.imageProperties?.contentUri
    }
}

extension Document {
    /// Every image in the document: inline images first, then positioned
    /// images.
    ///
    /// The API keys both maps in an unordered dictionary, so within each group
    /// the rows are ordered by object id — this keeps the output deterministic,
    /// the way the rest of graham's output is. Only objects that actually hold
    /// image data are listed: an embedded object can instead be a drawing
    /// (`embeddedDrawingProperties`) or linked content with no
    /// `imageProperties`, and such a non-image object is skipped rather than
    /// emitted as a bogus row. The extraction lives here in GrahamKit; the
    /// command only fetches and renders. See ``DocImageRow``.
    public var imageRows: [DocImageRow] {
        var rows: [DocImageRow] = []
        for key in (inlineObjects ?? [:]).keys.sorted() {
            guard let object = inlineObjects?[key],
                  let embedded = object.embeddedObject,
                  embedded.imageProperties != nil else { continue }
            rows.append(DocImageRow(
                objectId: object.objectId ?? key,
                origin: .inline,
                embeddedObject: embedded
            ))
        }
        for key in (positionedObjects ?? [:]).keys.sorted() {
            guard let object = positionedObjects?[key],
                  let embedded = object.embeddedObject,
                  embedded.imageProperties != nil else { continue }
            rows.append(DocImageRow(
                objectId: object.objectId ?? key,
                origin: .positioned,
                embeddedObject: embedded
            ))
        }
        return rows
    }
}

extension DocImageRow: GrahamRow {
    public static var tableColumns: [String] {
        ["ORIGIN", "OBJECT", "SIZE(pt)", "SOURCE_URI", "CONTENT_URI"]
    }

    public var tableValues: [String] {
        [
            origin.rawValue,
            objectId ?? "",
            sizeText,
            sourceUri ?? "",
            // The content URL is long and last, so it is not padded.
            contentUri ?? "",
        ]
    }

    public var idValue: String { objectId ?? "" }

    /// The size as `WxH` rounded to whole points, or empty when either
    /// dimension is missing. Docs reports image sizes in points (`PT`).
    var sizeText: String {
        guard let width, let height else { return "" }
        return "\(Self.roundedPoints(width))x\(Self.roundedPoints(height))"
    }

    private static func roundedPoints(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

// MARK: - Named-range list facade

/// One named range, flattened out of ``Document/namedRanges``.
///
/// The Docs `namedRanges` map is keyed by name; each entry holds one or more
/// ``DocNamedRange`` objects that share that name, and each of those covers one
/// or more ``DocRange`` spans (a named range can be discontinuous). This row is
/// the flattened, per-``DocNamedRange`` view a `docs range list` command
/// renders: the id `docs range delete`/`fill` take, the name they can also
/// target, and the range's spans. The extraction lives here in GrahamKit; the
/// command only fetches and renders. See ``Document/namedRangeRows``.
public struct DocNamedRangeRow: Codable, Sendable, Equatable {
    /// The named range id — the value `docs range delete --id` and
    /// `docs range fill --id` consume.
    public let namedRangeId: String?
    /// The name shared by every ``DocNamedRange`` with this name; `docs range
    /// delete --name` and `docs range fill --name` target it.
    public let name: String?
    /// The spans this named range covers, in ascending start order. A named
    /// range can be discontinuous, so this can hold several spans.
    public let ranges: [DocRange]

    init(namedRange: DocNamedRange, name: String?) {
        namedRangeId = namedRange.namedRangeId
        // The entry's own name wins; fall back to the map key that grouped it.
        self.name = namedRange.name ?? name
        // Sort the spans by (start, end) so the rendered spans and the JSON are
        // deterministic regardless of the order Google returns them in.
        ranges = (namedRange.ranges ?? []).sorted {
            ($0.startIndex ?? 0, $0.endIndex ?? 0) < ($1.startIndex ?? 0, $1.endIndex ?? 0)
        }
    }
}

extension Document {
    /// Every named range in the document, one row per ``DocNamedRange``.
    ///
    /// ``Document/namedRanges`` keys each group by name and can list several
    /// ranges under one name, so a single name can produce several rows. The
    /// rows are sorted by name, then by named range id, so the output is
    /// deterministic — the map itself is unordered. The flattening lives here in
    /// GrahamKit; the command only fetches and renders. See ``DocNamedRangeRow``.
    public var namedRangeRows: [DocNamedRangeRow] {
        var rows: [DocNamedRangeRow] = []
        for (key, group) in namedRanges ?? [:] {
            let name = group.name ?? key
            for namedRange in group.namedRanges ?? [] {
                rows.append(DocNamedRangeRow(namedRange: namedRange, name: name))
            }
        }
        return rows.sorted {
            let leftName = $0.name ?? ""
            let rightName = $1.name ?? ""
            if leftName != rightName { return leftName < rightName }
            return ($0.namedRangeId ?? "") < ($1.namedRangeId ?? "")
        }
    }
}

extension DocNamedRangeRow: GrahamRow {
    public static var tableColumns: [String] {
        ["ID", "NAME", "RANGES"]
    }

    public var tableValues: [String] {
        // RANGES is last (and can be long for a discontinuous range), so it is
        // not padded.
        [namedRangeId ?? "", name ?? "", rangesText]
    }

    /// `--format id` prints the named range id, one per line — the value the
    /// range write commands take.
    public var idValue: String { namedRangeId ?? "" }

    /// The spans as `start-end`, joined by commas for a discontinuous range
    /// (for example `14-31` or `31-37,37-44`). An absent end reads as empty.
    var rangesText: String {
        ranges
            .map { "\($0.startIndex ?? 0)-\($0.endIndex.map(String.init) ?? "")" }
            .joined(separator: ",")
    }
}

// MARK: - Image download

/// Builds safe, deterministic file names for downloaded document images.
///
/// The name is:
///
///     <seq>-<origin>-<objectId>.<ext>
///
/// where `seq` is a zero-padded position in the download order (so two images
/// can never collide, even with an equal or missing object id), `origin` is
/// `inline` or `positioned`, `objectId` is sanitized to a safe character set,
/// and `ext` is chosen by sniffing the downloaded bytes (never guessed from
/// the URI). This mirrors the Slides ``SlideImageFile`` naming; sanitizing
/// drops every path separator and dot, so a name can never traverse out of the
/// target directory.
public enum DocImageFile {
    /// The characters kept in a sanitized name component. Note that `.` is not
    /// in the set, so a component can never form `..` or a hidden file.
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// Replaces every unsafe character in a name component with `_`.
    public static func sanitize(_ component: String) -> String {
        let mapped = String(component.map { safe.contains($0) ? $0 : "_" })
        return mapped.isEmpty ? "image" : mapped
    }

    /// Builds the file name for the image at `sequence` in the download order.
    public static func filename(
        sequence: Int,
        origin: DocImageOrigin,
        objectId: String?,
        fileExtension: String
    ) -> String {
        let seq = String(format: "%03d", sequence)
        let name = sanitize(objectId ?? "image")
        return "\(seq)-\(origin.rawValue)-\(name).\(fileExtension)"
    }

    /// Chooses a file extension by sniffing the leading "magic" bytes of the
    /// image, never by trusting the URI. Returns `bin` for an unrecognized
    /// format, so an unknown image is still saved with a safe, generic name.
    ///
    /// Docs serves PNG, JPEG, or GIF for pictures; the extra formats are
    /// recognized so a future or unusual response is still labelled correctly.
    /// The detection is byte-for-byte identical to the Slides reader's, kept
    /// here so the Docs download stays self-contained.
    public static func fileExtension(forBytes bytes: Data) -> String {
        func startsWith(_ prefix: [UInt8]) -> Bool {
            guard bytes.count >= prefix.count else { return false }
            for (index, byte) in prefix.enumerated() where bytes[bytes.startIndex + index] != byte {
                return false
            }
            return true
        }
        func matches(_ ascii: String, at offset: Int) -> Bool {
            let prefix = Array(ascii.utf8)
            guard bytes.count >= offset + prefix.count else { return false }
            for (index, byte) in prefix.enumerated()
            where bytes[bytes.startIndex + offset + index] != byte {
                return false
            }
            return true
        }

        if startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if startsWith([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if startsWith([0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if matches("RIFF", at: 0) && matches("WEBP", at: 8) { return "webp" }
        if startsWith([0x42, 0x4D]) { return "bmp" }
        if startsWith([0x49, 0x49, 0x2A, 0x00]) || startsWith([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return "bin"
    }
}

/// What happened to one image in a document download run.
public enum DocImageDownloadOutcome: Sendable, Equatable {
    /// The image was fetched and written. `byteCount` is the size on disk.
    case downloaded(filename: String, byteCount: Int)
    /// The image could not be fetched or written; `reason` explains why.
    case failed(reason: String)
    /// The image had no content URI, so there was nothing to download.
    case skipped(reason: String)
}

/// The result of trying to download one document image.
public struct DocImageDownloadResult: Sendable, Equatable {
    public let objectId: String?
    public let origin: DocImageOrigin
    public let contentUri: String?
    public let outcome: DocImageDownloadOutcome

    public init(
        objectId: String?,
        origin: DocImageOrigin,
        contentUri: String?,
        outcome: DocImageDownloadOutcome
    ) {
        self.objectId = objectId
        self.origin = origin
        self.contentUri = contentUri
        self.outcome = outcome
    }
}
