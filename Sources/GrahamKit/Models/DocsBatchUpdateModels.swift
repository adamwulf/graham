import Foundation

// The models in this file follow the Google Docs v1 `documents.batchUpdate`
// schema. Request fields are required when the API operation requires them, so
// an invalid request fails to compile instead of failing at the server.
// Response fields stay optional and decode defensively.
//
// Every type is prefixed `Docs` because `GrahamKit` is one module: `InsertText`
// and other bare names already belong to the Slides write models. The prefix
// keeps the two services' unions from colliding.

// MARK: - Request union

/// One operation in a `documents.batchUpdate` call.
///
/// The API takes a list of request objects, and each object sets exactly one
/// operation field: `{"insertText": {...}}`, `{"deleteContentRange": {...}}`,
/// and so on. This enum mirrors that union: one case per operation, encoded
/// under the operation's JSON key. Later Docs writes join this union as new
/// cases, so every write shares one batch-update path.
public enum DocsBatchUpdateRequest: Encodable, Sendable, Equatable {
    /// Inserts text at a document location.
    case insertText(DocsInsertTextRequest)
    /// Deletes a range of content.
    case deleteContentRange(DocsDeleteContentRangeRequest)
    /// Replaces every match of a string with another string.
    case replaceAllText(DocsReplaceAllTextRequest)
    /// Styles a range of text (bold, colors, font, link, and so on).
    case updateTextStyle(DocsUpdateTextStyleRequest)
    /// Styles the paragraphs a range touches (named style, alignment, spacing,
    /// indents, and so on).
    case updateParagraphStyle(DocsUpdateParagraphStyleRequest)
    /// Turns the paragraphs overlapping a range into a list, using a bullet
    /// preset (its glyphs or numbering).
    case createParagraphBullets(DocsCreateParagraphBulletsRequest)
    /// Removes bullets from the paragraphs overlapping a range, preserving
    /// visual nesting through indents.
    case deleteParagraphBullets(DocsDeleteParagraphBulletsRequest)
    /// Inserts an empty rows x columns table at a location or the end of a
    /// segment.
    case insertTable(DocsInsertTableRequest)
    /// Inserts an empty row above or below a reference cell.
    case insertTableRow(DocsInsertTableRowRequest)
    /// Inserts an empty column left or right of a reference cell.
    case insertTableColumn(DocsInsertTableColumnRequest)
    /// Deletes the row of a reference cell (a merged cell deletes every row it
    /// spans).
    case deleteTableRow(DocsDeleteTableRowRequest)
    /// Deletes the column of a reference cell (a merged cell deletes every
    /// column it spans).
    case deleteTableColumn(DocsDeleteTableColumnRequest)
    /// Merges the cells of a table range into the range's head cell.
    case mergeTableCells(DocsMergeTableCellsRequest)
    /// Unmerges every merged cell in a table range.
    case unmergeTableCells(DocsUnmergeTableCellsRequest)
    /// Pins the first N rows of a table as headers; 0 unpins.
    case pinTableHeaderRows(DocsPinTableHeaderRowsRequest)
    /// Styles a range of table cells, or a whole table (background, borders,
    /// padding, alignment).
    case updateTableCellStyle(DocsUpdateTableCellStyleRequest)
    /// Sets the row style (height, header, overflow) of listed rows, or every
    /// row.
    case updateTableRowStyle(DocsUpdateTableRowStyleRequest)
    /// Sets the column width (fixed or evenly distributed) of listed columns, or
    /// every column.
    case updateTableColumnProperties(DocsUpdateTableColumnPropertiesRequest)
    /// Inserts a page break plus a newline at a body location or the end of the
    /// body.
    case insertPageBreak(DocsInsertPageBreakRequest)
    /// Inserts an inline image from a URI at a location or the end of a segment;
    /// the reply carries the new object id.
    case insertInlineImage(DocsInsertInlineImageRequest)
    /// Replaces an existing image, in place, with a new image from a URI.
    case replaceImage(DocsReplaceImageRequest)
    /// Inserts a continuous or next-page section break at a body location or the
    /// end of the body.
    case insertSectionBreak(DocsInsertSectionBreakRequest)
    /// Creates a header (optionally scoped to a section); the reply carries the
    /// new header segment id.
    case createHeader(DocsCreateHeaderRequest)
    /// Creates a footer (optionally scoped to a section); the reply carries the
    /// new footer segment id.
    case createFooter(DocsCreateFooterRequest)
    /// Deletes a header by its segment id.
    case deleteHeader(DocsDeleteHeaderRequest)
    /// Deletes a footer by its segment id.
    case deleteFooter(DocsDeleteFooterRequest)
    /// Creates a footnote and inserts its reference at a body location; the reply
    /// carries the new footnote segment id.
    case createFootnote(DocsCreateFootnoteRequest)
    /// Names a range; the reply carries the new named-range id.
    case createNamedRange(DocsCreateNamedRangeRequest)
    /// Deletes a named range by its id, or every range sharing a name.
    case deleteNamedRange(DocsDeleteNamedRangeRequest)
    /// Replaces the content of a named range (by id or name) with text.
    case replaceNamedRangeContent(DocsReplaceNamedRangeContentRequest)
    /// Sets document-wide style (page size, margins, header/footer flags,
    /// background); the `fields` mask decides which properties apply.
    case updateDocumentStyle(DocsUpdateDocumentStyleRequest)
    /// Sets the style (margins, page numbering, direction, column separator,
    /// header/footer flags) of every section a range overlaps; the `fields`
    /// mask decides which properties apply.
    case updateSectionStyle(DocsUpdateSectionStyleRequest)

    private enum CodingKeys: String, CodingKey {
        case insertText
        case deleteContentRange
        case replaceAllText
        case updateTextStyle
        case updateParagraphStyle
        case createParagraphBullets
        case deleteParagraphBullets
        case insertTable
        case insertTableRow
        case insertTableColumn
        case deleteTableRow
        case deleteTableColumn
        case mergeTableCells
        case unmergeTableCells
        case pinTableHeaderRows
        case updateTableCellStyle
        case updateTableRowStyle
        case updateTableColumnProperties
        case insertPageBreak
        case insertInlineImage
        case replaceImage
        case insertSectionBreak
        case createHeader
        case createFooter
        case deleteHeader
        case deleteFooter
        case createFootnote
        case createNamedRange
        case deleteNamedRange
        case replaceNamedRangeContent
        case updateDocumentStyle
        case updateSectionStyle
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .insertText(let request):
            try container.encode(request, forKey: .insertText)
        case .deleteContentRange(let request):
            try container.encode(request, forKey: .deleteContentRange)
        case .replaceAllText(let request):
            try container.encode(request, forKey: .replaceAllText)
        case .updateTextStyle(let request):
            try container.encode(request, forKey: .updateTextStyle)
        case .updateParagraphStyle(let request):
            try container.encode(request, forKey: .updateParagraphStyle)
        case .createParagraphBullets(let request):
            try container.encode(request, forKey: .createParagraphBullets)
        case .deleteParagraphBullets(let request):
            try container.encode(request, forKey: .deleteParagraphBullets)
        case .insertTable(let request):
            try container.encode(request, forKey: .insertTable)
        case .insertTableRow(let request):
            try container.encode(request, forKey: .insertTableRow)
        case .insertTableColumn(let request):
            try container.encode(request, forKey: .insertTableColumn)
        case .deleteTableRow(let request):
            try container.encode(request, forKey: .deleteTableRow)
        case .deleteTableColumn(let request):
            try container.encode(request, forKey: .deleteTableColumn)
        case .mergeTableCells(let request):
            try container.encode(request, forKey: .mergeTableCells)
        case .unmergeTableCells(let request):
            try container.encode(request, forKey: .unmergeTableCells)
        case .pinTableHeaderRows(let request):
            try container.encode(request, forKey: .pinTableHeaderRows)
        case .updateTableCellStyle(let request):
            try container.encode(request, forKey: .updateTableCellStyle)
        case .updateTableRowStyle(let request):
            try container.encode(request, forKey: .updateTableRowStyle)
        case .updateTableColumnProperties(let request):
            try container.encode(request, forKey: .updateTableColumnProperties)
        case .insertPageBreak(let request):
            try container.encode(request, forKey: .insertPageBreak)
        case .insertInlineImage(let request):
            try container.encode(request, forKey: .insertInlineImage)
        case .replaceImage(let request):
            try container.encode(request, forKey: .replaceImage)
        case .insertSectionBreak(let request):
            try container.encode(request, forKey: .insertSectionBreak)
        case .createHeader(let request):
            try container.encode(request, forKey: .createHeader)
        case .createFooter(let request):
            try container.encode(request, forKey: .createFooter)
        case .deleteHeader(let request):
            try container.encode(request, forKey: .deleteHeader)
        case .deleteFooter(let request):
            try container.encode(request, forKey: .deleteFooter)
        case .createFootnote(let request):
            try container.encode(request, forKey: .createFootnote)
        case .createNamedRange(let request):
            try container.encode(request, forKey: .createNamedRange)
        case .deleteNamedRange(let request):
            try container.encode(request, forKey: .deleteNamedRange)
        case .replaceNamedRangeContent(let request):
            try container.encode(request, forKey: .replaceNamedRangeContent)
        case .updateDocumentStyle(let request):
            try container.encode(request, forKey: .updateDocumentStyle)
        case .updateSectionStyle(let request):
            try container.encode(request, forKey: .updateSectionStyle)
        }
    }
}

/// Optimistic-concurrency control for a `documents.batchUpdate` write.
///
/// `requiredRevisionId` makes the write apply only if the document is still at
/// that revision, failing otherwise so a concurrent edit is never silently
/// overwritten. `targetRevisionId` applies the write against an older revision,
/// transforming it forward. The two are a Google `oneof` (mutually exclusive),
/// so the two dedicated inits set exactly one; the other stays nil and is
/// omitted when encoded, and a dual-field body is unrepresentable. graham sets
/// only `requiredRevisionId`. Both stay optional so the response, which echoes
/// one, still decodes. The document's current revision is `Document.revisionId`
/// (populated by the richer read phase).
public struct DocsWriteControl: Codable, Sendable, Equatable {
    public let requiredRevisionId: String?
    public let targetRevisionId: String?

    /// Require the document be at this revision; the write fails otherwise.
    public init(requiredRevisionId: String) {
        self.requiredRevisionId = requiredRevisionId
        self.targetRevisionId = nil
    }

    /// Apply the write against this (possibly older) revision, transforming it
    /// forward.
    public init(targetRevisionId: String) {
        self.requiredRevisionId = nil
        self.targetRevisionId = targetRevisionId
    }
}

/// The body of a `documents.batchUpdate` POST.
///
/// `writeControl` is included only when the caller supplies one, so an ordinary
/// write body stays `{"requests": [...]}`.
struct DocsBatchUpdateRequestBody: Encodable, Sendable {
    let requests: [DocsBatchUpdateRequest]
    let writeControl: DocsWriteControl?

    init(requests: [DocsBatchUpdateRequest], writeControl: DocsWriteControl? = nil) {
        self.requests = requests
        self.writeControl = writeControl
    }
}

// MARK: - Shared locations

/// A position within a document, at a zero-based offset.
///
/// `index` is a zero-based offset in **UTF-16 code units** into the document's
/// content, exactly as the Docs API defines it. This is the API index model:
/// unlike the one-based slide, table, and link positions elsewhere in graham,
/// Docs text indices stay zero-based to match the API. `segmentId` names a
/// header, footer, or footnote segment; when omitted, the index refers to the
/// document body. `tabId` names the tab the location lives in; when omitted,
/// the location refers to the singular tab of a document with no explicit tabs.
/// Both optionals encode only when set, so the common body location stays
/// `{"index": ...}`.
public struct DocsLocation: Codable, Sendable, Equatable {
    public let index: Int
    public let segmentId: String?
    public let tabId: String?

    public init(index: Int, segmentId: String? = nil, tabId: String? = nil) {
        self.index = index
        self.segmentId = segmentId
        self.tabId = tabId
    }
}

/// A half-open `[startIndex, endIndex)` span of content, in zero-based UTF-16
/// code units.
///
/// `segmentId` names a header, footer, or footnote segment; when omitted, the
/// range refers to the document body. `tabId` names the tab the range lives in;
/// when omitted, the range refers to the singular tab of a document with no
/// explicit tabs. Both optionals encode only when set, so the common body range
/// stays `{"endIndex": ..., "startIndex": ...}`.
public struct DocsRange: Codable, Sendable, Equatable {
    public let startIndex: Int
    public let endIndex: Int
    public let segmentId: String?
    public let tabId: String?

    public init(startIndex: Int, endIndex: Int, segmentId: String? = nil, tabId: String? = nil) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.segmentId = segmentId
        self.tabId = tabId
    }
}

/// The end of a document segment, as a target for appending content without
/// computing an index. `segmentId` names a header, footer, or footnote segment;
/// when omitted, the target is the end of the document body. `tabId` names the
/// tab the segment lives in; when omitted, it refers to the singular tab of a
/// document with no explicit tabs. Both optionals encode only when set, so the
/// common append-to-body target stays `{}`. The Docs API's
/// `EndOfSegmentLocation`; an `insertText` uses either this or a
/// ``DocsLocation``, never both.
public struct DocsEndOfSegmentLocation: Codable, Sendable, Equatable {
    public let segmentId: String?
    public let tabId: String?

    public init(segmentId: String? = nil, tabId: String? = nil) {
        self.segmentId = segmentId
        self.tabId = tabId
    }
}

/// The location of a single cell in a table, addressed by the table's start
/// location and the cell's row and column.
///
/// `rowIndex` and `columnIndex` are **zero-based**, matching the API. The CLI
/// shows and accepts one-based row and column numbers; ``GrahamKit`` translates
/// at the client boundary. `tableStartLocation` is the ``DocsLocation`` of the
/// table's start index (the value `docs structure` prints).
public struct DocsTableCellLocation: Codable, Sendable, Equatable {
    public let tableStartLocation: DocsLocation
    public let rowIndex: Int
    public let columnIndex: Int

    public init(tableStartLocation: DocsLocation, rowIndex: Int, columnIndex: Int) {
        self.tableStartLocation = tableStartLocation
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
    }
}

/// A rectangular span of table cells, anchored at a ``DocsTableCellLocation``
/// and extending over `rowSpan` rows and `columnSpan` columns.
///
/// Both spans are counts of cells (one-based counts, not indices); the API
/// requires them. Table operations such as merge, unmerge, and cell styling
/// address a `DocsTableRange`.
public struct DocsTableRange: Codable, Sendable, Equatable {
    public let tableCellLocation: DocsTableCellLocation
    public let rowSpan: Int
    public let columnSpan: Int

    public init(tableCellLocation: DocsTableCellLocation, rowSpan: Int, columnSpan: Int) {
        self.tableCellLocation = tableCellLocation
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
    }
}

// MARK: - Operation requests

/// The `insertText` operation. The `text` is always required; the destination
/// is exactly one of a ``DocsLocation`` (an explicit index) or a
/// ``DocsEndOfSegmentLocation`` (append to the end of the body or a segment
/// without computing an index). The two inits keep those mutually exclusive:
/// only the chosen one is set, and the other stays nil and is omitted when
/// encoded.
public struct DocsInsertTextRequest: Codable, Sendable, Equatable {
    public let text: String
    public let location: DocsLocation?
    public let endOfSegmentLocation: DocsEndOfSegmentLocation?

    public init(text: String, location: DocsLocation) {
        self.text = text
        self.location = location
        self.endOfSegmentLocation = nil
    }

    public init(text: String, endOfSegmentLocation: DocsEndOfSegmentLocation) {
        self.text = text
        self.location = nil
        self.endOfSegmentLocation = endOfSegmentLocation
    }
}

/// The `deleteContentRange` operation. The range is required by the API.
public struct DocsDeleteContentRangeRequest: Codable, Sendable, Equatable {
    public let range: DocsRange

    public init(range: DocsRange) {
        self.range = range
    }
}

/// The text-match criteria of a `replaceAllText` operation.
///
/// `matchCase` is required by the API: when false, the match is
/// case-insensitive.
public struct DocsSubstringMatchCriteria: Codable, Sendable, Equatable {
    public let text: String
    public let matchCase: Bool

    public init(text: String, matchCase: Bool) {
        self.text = text
        self.matchCase = matchCase
    }
}

/// The `replaceAllText` operation. The replacement text and the match criteria
/// are required by the API.
public struct DocsReplaceAllTextRequest: Codable, Sendable, Equatable {
    public let replaceText: String
    public let containsText: DocsSubstringMatchCriteria

    public init(replaceText: String, containsText: DocsSubstringMatchCriteria) {
        self.replaceText = replaceText
        self.containsText = containsText
    }
}

// MARK: - Text and paragraph styling
//
// These mirror the Docs v1 `TextStyle`, `ParagraphStyle`, and their color,
// dimension, font, and link sub-models used by the `updateTextStyle` and
// `updateParagraphStyle` requests. Only the writable subset graham sets is
// modeled; every field is optional and the request's `fields` mask, not the
// container, decides which properties the API applies. Docs colors differ from
// Slides: a Docs color is an `OptionalColor` wrapping a `Color` wrapping an
// `RgbColor` (no theme color), so these are prefixed `Docs` and kept separate
// from the Slides `OpaqueColor`/`RgbColor` write models.

/// An explicit RGB color. Each channel is a float from 0 to 1, matching the
/// Docs v1 `RgbColor`.
public struct DocsRgbColor: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Builds a color, clamping each channel into `0...1` so a direct caller
    /// cannot construct an out-of-range color the API would reject. The hex
    /// parse path already yields valid values; this hardens the direct init.
    /// Codable decoding keeps the synthesized `init(from:)`, which does not run
    /// through here.
    public init(red: Double, green: Double, blue: Double) {
        func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
    }
}

/// A Docs v1 `Color`: an explicit RGB color. The API models a bare color with a
/// single optional `rgbColor` field.
public struct DocsColor: Codable, Sendable, Equatable {
    public let rgbColor: DocsRgbColor?

    public init(rgbColor: DocsRgbColor? = nil) {
        self.rgbColor = rgbColor
    }
}

/// A Docs v1 `OptionalColor`: a color that may be explicitly transparent.
///
/// A set ``color`` sets a solid color; an empty `OptionalColor` (`{}`) is the
/// API's way to clear a color to transparent. graham only sets solid colors, so
/// the parse seam always yields a wrapped ``DocsColor``.
public struct DocsOptionalColor: Codable, Sendable, Equatable {
    public let color: DocsColor?

    public init(color: DocsColor? = nil) {
        self.color = color
    }

    /// Wraps an explicit RGB color as an `OptionalColor`.
    public init(rgb: DocsRgbColor) {
        self.color = DocsColor(rgbColor: rgb)
    }

    /// Parses a `#RRGGBB` hex color into an `OptionalColor` whose
    /// `color.rgbColor` channels are floats from 0 to 1.
    ///
    /// This is the one color-parsing seam for Docs styling; the CLI never parses
    /// colors itself. A leading `#` is optional and the six hex digits are
    /// case-insensitive. Each channel maps to `component / 255`, so `#FF0000`
    /// becomes `red: 1, green: 0, blue: 0`. Any other length or a non-hex digit
    /// throws ``GrahamError/invalidArgument(_:)`` naming the input.
    public static func parse(_ input: String) throws -> DocsOptionalColor {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let digits = Array(hex)
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw GrahamError.invalidArgument(
                "could not parse \"\(input)\" as a color; use a hex value like #RRGGBB, "
                + "for example #FF0000")
        }
        func channel(_ start: Int) -> Double {
            Double(Int(String(digits[start..<start + 2]), radix: 16) ?? 0) / 255
        }
        return DocsOptionalColor(
            rgb: DocsRgbColor(red: channel(0), green: channel(2), blue: channel(4)))
    }
}

/// The unit of a Docs write-side ``DocsDimension``. graham writes lengths in
/// points only (font size, spacing, indents), so the write model carries just
/// `PT`; the Docs API's other units (`MM`, `CM`, `IN`) are never emitted.
public enum DocsDimensionUnit: String, Codable, Sendable, Equatable {
    case pt = "PT"
}

/// A Docs v1 `Dimension`: a magnitude and its unit. Both are required on the
/// write side so a partial, unit-less length cannot be built.
public struct DocsDimension: Codable, Sendable, Equatable {
    public let magnitude: Double
    public let unit: DocsDimensionUnit

    public init(magnitude: Double, unit: DocsDimensionUnit = .pt) {
        self.magnitude = magnitude
        self.unit = unit
    }
}

/// A Docs v1 `WeightedFontFamily`: a font family with an optional numeric
/// weight (a multiple of 100 within 100...900; the API defaults to 400 when it
/// is omitted). Docs `TextStyle` has no bare `fontFamily` field — the family is
/// always set through this weighted family.
public struct DocsWeightedFontFamily: Codable, Sendable, Equatable {
    public let fontFamily: String
    public let weight: Int?

    public init(fontFamily: String, weight: Int? = nil) {
        self.fontFamily = fontFamily
        self.weight = weight
    }
}

/// A Docs v1 `Link`. graham only sets a web `url`; the API's heading, bookmark,
/// and tab targets are not part of this styling slice.
public struct DocsLink: Codable, Sendable, Equatable {
    public let url: String?

    public init(url: String) {
        self.url = url
    }
}

/// The vertical offset of a text run from its normal baseline, matching the
/// Docs v1 `TextStyle.baselineOffset` enum values graham writes.
public enum DocsBaselineOffset: String, Codable, Sendable, Equatable {
    case none = "NONE"
    case superscript = "SUPERSCRIPT"
    case `subscript` = "SUBSCRIPT"
}

/// A Docs v1 `ParagraphStyle.namedStyleType`: how a paragraph becomes a body,
/// title, subtitle, or heading. The cases are the writable values (the API's
/// `NAMED_STYLE_TYPE_UNSPECIFIED` is never sent).
public enum DocsNamedStyleType: String, Codable, Sendable, Equatable {
    case normalText = "NORMAL_TEXT"
    case title = "TITLE"
    case subtitle = "SUBTITLE"
    case heading1 = "HEADING_1"
    case heading2 = "HEADING_2"
    case heading3 = "HEADING_3"
    case heading4 = "HEADING_4"
    case heading5 = "HEADING_5"
    case heading6 = "HEADING_6"
}

/// A Docs v1 `ParagraphStyle.alignment`: the horizontal alignment of a
/// paragraph.
public enum DocsParagraphAlignment: String, Codable, Sendable, Equatable {
    case start = "START"
    case center = "CENTER"
    case end = "END"
    case justified = "JUSTIFIED"
}

/// A Docs v1 `ParagraphStyle.direction`: the reading direction of a paragraph.
public enum DocsContentDirection: String, Codable, Sendable, Equatable {
    case leftToRight = "LEFT_TO_RIGHT"
    case rightToLeft = "RIGHT_TO_LEFT"
}

/// The writable subset of a Docs `TextStyle`.
///
/// Every field is optional; the request's `fields` mask, not this container,
/// decides which properties the API applies. `foregroundColor` and
/// `backgroundColor` are ``DocsOptionalColor`` values; the font family is set
/// through ``weightedFontFamily`` because Docs `TextStyle` has no bare
/// `fontFamily` field. `smallCaps` renders the text in small capital letters.
public struct DocsTextStyle: Codable, Sendable, Equatable {
    public let bold: Bool?
    public let italic: Bool?
    public let underline: Bool?
    public let strikethrough: Bool?
    public let foregroundColor: DocsOptionalColor?
    public let backgroundColor: DocsOptionalColor?
    public let fontSize: DocsDimension?
    public let weightedFontFamily: DocsWeightedFontFamily?
    public let baselineOffset: DocsBaselineOffset?
    public let link: DocsLink?
    public let smallCaps: Bool?

    public init(
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        foregroundColor: DocsOptionalColor? = nil,
        backgroundColor: DocsOptionalColor? = nil,
        fontSize: DocsDimension? = nil,
        weightedFontFamily: DocsWeightedFontFamily? = nil,
        baselineOffset: DocsBaselineOffset? = nil,
        link: DocsLink? = nil,
        smallCaps: Bool? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.fontSize = fontSize
        self.weightedFontFamily = weightedFontFamily
        self.baselineOffset = baselineOffset
        self.link = link
        self.smallCaps = smallCaps
    }
}

/// A Docs v1 `Shading`: the shading (background fill) of a paragraph. The API
/// models it with a single ``DocsOptionalColor`` `backgroundColor`. It reaches
/// the wire through ``DocsParagraphStyle/shading``, whose `fields` mask names the
/// `shading` root so the whole shading is replaced.
public struct DocsShading: Codable, Sendable, Equatable {
    public let backgroundColor: DocsOptionalColor?

    public init(backgroundColor: DocsOptionalColor? = nil) {
        self.backgroundColor = backgroundColor
    }
}

/// A Docs v1 `ParagraphStyle.spacingMode` / `SpacingMode`: how a paragraph's
/// space-above and space-below combine with its neighbors' spacing.
/// `NEVER_COLLAPSE` always renders both; `COLLAPSE_LISTS` skips the spacing
/// between list-item paragraphs. The cases are the writable values; the API's
/// `SPACING_MODE_UNSPECIFIED` sentinel is never sent, exactly like the other
/// `*_UNSPECIFIED` sentinels in these models.
public enum DocsSpacingMode: String, Codable, Sendable, Equatable {
    case neverCollapse = "NEVER_COLLAPSE"
    case collapseLists = "COLLAPSE_LISTS"
}

/// The writable subset of a Docs `ParagraphBorder`: the color, width, padding,
/// and dash style of one side of a paragraph.
///
/// Every field is optional, but graham always fills all four when it sets a
/// border (see ``DocsClient/styleParagraphs(documentId:startIndex:endIndex:segmentId:namedStyleType:alignment:direction:lineSpacing:spaceAbove:spaceBelow:indentStart:indentEnd:indentFirstLine:keepLinesTogether:keepWithNext:avoidWidowAndOrphan:pageBreakBefore:shadingBackgroundColor:spacingMode:outerBorderColor:betweenBorderColor:borderWidth:borderDash:borderPadding:requiredRevisionId:)``):
/// the Docs API forbids a partial paragraph-border update ("the new border must
/// be specified in its entirety"), so a border requires a color and defaults its
/// width to 1 pt, its padding to 0 pt, and its dash to solid. `color` is a
/// ``DocsOptionalColor``; `width` and `padding` are ``DocsDimension`` values in
/// points; `dashStyle` reuses the shared ``DocsDashStyle``.
public struct DocsParagraphBorder: Codable, Sendable, Equatable {
    public let color: DocsOptionalColor?
    public let width: DocsDimension?
    public let padding: DocsDimension?
    public let dashStyle: DocsDashStyle?

    public init(
        color: DocsOptionalColor? = nil,
        width: DocsDimension? = nil,
        padding: DocsDimension? = nil,
        dashStyle: DocsDashStyle? = nil
    ) {
        self.color = color
        self.width = width
        self.padding = padding
        self.dashStyle = dashStyle
    }
}

/// The writable subset of a Docs `ParagraphStyle`.
///
/// Every field is optional; the request's `fields` mask, not this container,
/// decides which properties the API applies. `lineSpacing` is a percent of
/// normal (100 = single); the spacing and indent dimensions are in points.
/// `keepLinesTogether`, `keepWithNext`, `avoidWidowAndOrphan`, and
/// `pageBreakBefore` are the pagination toggles; `shading` sets the paragraph
/// background fill; `spacingMode` chooses how the space-above/below collapse.
/// `borderTop`, `borderBottom`, `borderLeft`, and `borderRight` are the four
/// outer borders and `borderBetween` is the border rendered between adjacent
/// paragraphs; each is a ``DocsParagraphBorder``. Tab stops are out of this
/// slice.
public struct DocsParagraphStyle: Codable, Sendable, Equatable {
    public let namedStyleType: DocsNamedStyleType?
    public let alignment: DocsParagraphAlignment?
    public let direction: DocsContentDirection?
    public let lineSpacing: Double?
    public let spaceAbove: DocsDimension?
    public let spaceBelow: DocsDimension?
    public let indentStart: DocsDimension?
    public let indentEnd: DocsDimension?
    public let indentFirstLine: DocsDimension?
    public let keepLinesTogether: Bool?
    public let keepWithNext: Bool?
    public let avoidWidowAndOrphan: Bool?
    public let pageBreakBefore: Bool?
    public let shading: DocsShading?
    public let spacingMode: DocsSpacingMode?
    public let borderTop: DocsParagraphBorder?
    public let borderBottom: DocsParagraphBorder?
    public let borderLeft: DocsParagraphBorder?
    public let borderRight: DocsParagraphBorder?
    public let borderBetween: DocsParagraphBorder?

    public init(
        namedStyleType: DocsNamedStyleType? = nil,
        alignment: DocsParagraphAlignment? = nil,
        direction: DocsContentDirection? = nil,
        lineSpacing: Double? = nil,
        spaceAbove: DocsDimension? = nil,
        spaceBelow: DocsDimension? = nil,
        indentStart: DocsDimension? = nil,
        indentEnd: DocsDimension? = nil,
        indentFirstLine: DocsDimension? = nil,
        keepLinesTogether: Bool? = nil,
        keepWithNext: Bool? = nil,
        avoidWidowAndOrphan: Bool? = nil,
        pageBreakBefore: Bool? = nil,
        shading: DocsShading? = nil,
        spacingMode: DocsSpacingMode? = nil,
        borderTop: DocsParagraphBorder? = nil,
        borderBottom: DocsParagraphBorder? = nil,
        borderLeft: DocsParagraphBorder? = nil,
        borderRight: DocsParagraphBorder? = nil,
        borderBetween: DocsParagraphBorder? = nil
    ) {
        self.namedStyleType = namedStyleType
        self.alignment = alignment
        self.direction = direction
        self.lineSpacing = lineSpacing
        self.spaceAbove = spaceAbove
        self.spaceBelow = spaceBelow
        self.indentStart = indentStart
        self.indentEnd = indentEnd
        self.indentFirstLine = indentFirstLine
        self.keepLinesTogether = keepLinesTogether
        self.keepWithNext = keepWithNext
        self.avoidWidowAndOrphan = avoidWidowAndOrphan
        self.pageBreakBefore = pageBreakBefore
        self.shading = shading
        self.spacingMode = spacingMode
        self.borderTop = borderTop
        self.borderBottom = borderBottom
        self.borderLeft = borderLeft
        self.borderRight = borderRight
        self.borderBetween = borderBetween
    }
}

/// The `updateTextStyle` operation. `fields` is a comma-separated field mask of
/// the ``DocsTextStyle`` paths to apply, relative to the style root; at least
/// one path is required. The `range` is the zero-based UTF-16 span to style.
public struct DocsUpdateTextStyleRequest: Codable, Sendable, Equatable {
    public let textStyle: DocsTextStyle
    public let fields: String
    public let range: DocsRange

    public init(textStyle: DocsTextStyle, fields: String, range: DocsRange) {
        self.textStyle = textStyle
        self.fields = fields
        self.range = range
    }
}

/// The `updateParagraphStyle` operation. `fields` is a comma-separated field
/// mask of the ``DocsParagraphStyle`` paths to apply, relative to the style
/// root; at least one path is required. The `range` is the zero-based UTF-16
/// span whose paragraphs are styled.
public struct DocsUpdateParagraphStyleRequest: Codable, Sendable, Equatable {
    public let paragraphStyle: DocsParagraphStyle
    public let fields: String
    public let range: DocsRange

    public init(paragraphStyle: DocsParagraphStyle, fields: String, range: DocsRange) {
        self.paragraphStyle = paragraphStyle
        self.fields = fields
        self.range = range
    }
}

// MARK: - Lists (bullets)
//
// These mirror the Docs v1 `CreateParagraphBulletsRequest`,
// `DeleteParagraphBulletsRequest`, and the `BulletGlyphPreset` enum used to turn
// paragraphs into (or out of) a bulleted or numbered list.

/// A Docs v1 `BulletGlyphPreset`: the kinds of bullet glyphs (or numbering) a
/// `createParagraphBullets` operation applies across the first three list
/// nesting levels. The cases are the writable presets; the API's
/// `BULLET_GLYPH_PRESET_UNSPECIFIED` is never sent, exactly like the other
/// `*_UNSPECIFIED` sentinels in these models. Each raw value is the exact API
/// spelling, so encoding a preset writes that string verbatim.
public enum DocsBulletPreset: String, Codable, Sendable, Equatable, CaseIterable {
    /// `DISC`, `CIRCLE`, `SQUARE` glyphs for the first three nesting levels.
    case bulletDiscCircleSquare = "BULLET_DISC_CIRCLE_SQUARE"
    /// `DIAMONDX`, `ARROW3D`, `SQUARE` glyphs.
    case bulletDiamondxArrow3dSquare = "BULLET_DIAMONDX_ARROW3D_SQUARE"
    /// `CHECKBOX` glyphs for every nesting level.
    case bulletCheckbox = "BULLET_CHECKBOX"
    /// `ARROW`, `DIAMOND`, `DISC` glyphs.
    case bulletArrowDiamondDisc = "BULLET_ARROW_DIAMOND_DISC"
    /// `STAR`, `CIRCLE`, `SQUARE` glyphs.
    case bulletStarCircleSquare = "BULLET_STAR_CIRCLE_SQUARE"
    /// `ARROW3D`, `CIRCLE`, `SQUARE` glyphs.
    case bulletArrow3dCircleSquare = "BULLET_ARROW3D_CIRCLE_SQUARE"
    /// `LEFTTRIANGLE`, `DIAMOND`, `DISC` glyphs.
    case bulletLefttriangleDiamondDisc = "BULLET_LEFTTRIANGLE_DIAMOND_DISC"
    /// `DIAMONDX`, `HOLLOWDIAMOND`, `SQUARE` glyphs.
    case bulletDiamondxHollowdiamondSquare = "BULLET_DIAMONDX_HOLLOWDIAMOND_SQUARE"
    /// `DIAMOND`, `CIRCLE`, `SQUARE` glyphs.
    case bulletDiamondCircleSquare = "BULLET_DIAMOND_CIRCLE_SQUARE"
    /// `DECIMAL`, `ALPHA`, `ROMAN` numbering, each followed by a period.
    case numberedDecimalAlphaRoman = "NUMBERED_DECIMAL_ALPHA_ROMAN"
    /// `DECIMAL`, `ALPHA`, `ROMAN` numbering, each followed by a parenthesis.
    case numberedDecimalAlphaRomanParens = "NUMBERED_DECIMAL_ALPHA_ROMAN_PARENS"
    /// `DECIMAL` numbering where each level prefixes the previous level's glyph
    /// (`1.`, `1.1.`, `2.`).
    case numberedDecimalNested = "NUMBERED_DECIMAL_NESTED"
    /// `UPPERALPHA`, `ALPHA`, `ROMAN` numbering, each followed by a period.
    case numberedUpperalphaAlphaRoman = "NUMBERED_UPPERALPHA_ALPHA_ROMAN"
    /// `UPPERROMAN`, `UPPERALPHA`, `DECIMAL` numbering, each followed by a period.
    case numberedUpperromanUpperalphaDecimal = "NUMBERED_UPPERROMAN_UPPERALPHA_DECIMAL"
    /// `ZERODECIMAL`, `ALPHA`, `ROMAN` numbering, each followed by a period.
    case numberedZerodecimalAlphaRoman = "NUMBERED_ZERODECIMAL_ALPHA_ROMAN"
}

/// The `createParagraphBullets` operation. Both the `range` (the zero-based
/// UTF-16 span whose overlapping paragraphs become a list) and the
/// `bulletPreset` (the glyphs or numbering to apply) are required by the API.
public struct DocsCreateParagraphBulletsRequest: Codable, Sendable, Equatable {
    public let range: DocsRange
    public let bulletPreset: DocsBulletPreset

    public init(range: DocsRange, bulletPreset: DocsBulletPreset) {
        self.range = range
        self.bulletPreset = bulletPreset
    }
}

/// The `deleteParagraphBullets` operation. The `range` (the zero-based UTF-16
/// span whose overlapping paragraphs lose their bullets) is required by the API.
public struct DocsDeleteParagraphBulletsRequest: Codable, Sendable, Equatable {
    public let range: DocsRange

    public init(range: DocsRange) {
        self.range = range
    }
}

// MARK: - Tables (structure)
//
// These mirror the Docs v1 table structure operations: `insertTable`,
// `insertTableRow`, `insertTableColumn`, `deleteTableRow`, `deleteTableColumn`,
// `mergeTableCells`, `unmergeTableCells`, and `pinTableHeaderRows`. They reuse
// the shared ``DocsLocation``, ``DocsEndOfSegmentLocation``,
// ``DocsTableCellLocation``, and ``DocsTableRange`` location models. The API's
// row and column indices are zero-based; the CLI shows one-based and
// ``DocsClient`` subtracts one at the client boundary. The styling operations
// (`updateTableCellStyle`, `updateTableRowStyle`, `updateTableColumnProperties`)
// are a separate phase and are not modeled here.

/// The `insertTable` operation. `rows` and `columns` are required and give the
/// dimensions of the new, empty table. The destination is exactly one of a
/// ``DocsLocation`` (an explicit index) or a ``DocsEndOfSegmentLocation``
/// (append to the end of the body or a segment). The two inits keep those
/// mutually exclusive: only the chosen one is set, and the other stays nil and
/// is omitted when encoded. The API inserts a newline before the table, so the
/// resulting table start index is the location index + 1.
public struct DocsInsertTableRequest: Codable, Sendable, Equatable {
    public let rows: Int
    public let columns: Int
    public let location: DocsLocation?
    public let endOfSegmentLocation: DocsEndOfSegmentLocation?

    public init(rows: Int, columns: Int, location: DocsLocation) {
        self.rows = rows
        self.columns = columns
        self.location = location
        self.endOfSegmentLocation = nil
    }

    public init(rows: Int, columns: Int, endOfSegmentLocation: DocsEndOfSegmentLocation) {
        self.rows = rows
        self.columns = columns
        self.location = nil
        self.endOfSegmentLocation = endOfSegmentLocation
    }
}

/// The `insertTableRow` operation. `tableCellLocation` is the reference cell and
/// `insertBelow` chooses the side: true inserts below the reference row, false
/// inserts above it. Both are required by the API.
public struct DocsInsertTableRowRequest: Codable, Sendable, Equatable {
    public let tableCellLocation: DocsTableCellLocation
    public let insertBelow: Bool

    public init(tableCellLocation: DocsTableCellLocation, insertBelow: Bool) {
        self.tableCellLocation = tableCellLocation
        self.insertBelow = insertBelow
    }
}

/// The `insertTableColumn` operation. `tableCellLocation` is the reference cell
/// and `insertRight` chooses the side: true inserts to the right of the
/// reference column, false inserts to its left. Both are required by the API.
public struct DocsInsertTableColumnRequest: Codable, Sendable, Equatable {
    public let tableCellLocation: DocsTableCellLocation
    public let insertRight: Bool

    public init(tableCellLocation: DocsTableCellLocation, insertRight: Bool) {
        self.tableCellLocation = tableCellLocation
        self.insertRight = insertRight
    }
}

/// The `deleteTableRow` operation. The row containing `tableCellLocation` is
/// deleted; a merged reference cell deletes every row it spans.
public struct DocsDeleteTableRowRequest: Codable, Sendable, Equatable {
    public let tableCellLocation: DocsTableCellLocation

    public init(tableCellLocation: DocsTableCellLocation) {
        self.tableCellLocation = tableCellLocation
    }
}

/// The `deleteTableColumn` operation. The column containing `tableCellLocation`
/// is deleted; a merged reference cell deletes every column it spans.
public struct DocsDeleteTableColumnRequest: Codable, Sendable, Equatable {
    public let tableCellLocation: DocsTableCellLocation

    public init(tableCellLocation: DocsTableCellLocation) {
        self.tableCellLocation = tableCellLocation
    }
}

/// The `mergeTableCells` operation. Every cell of `tableRange` is merged into
/// the range's head cell, concatenating the text.
public struct DocsMergeTableCellsRequest: Codable, Sendable, Equatable {
    public let tableRange: DocsTableRange

    public init(tableRange: DocsTableRange) {
        self.tableRange = tableRange
    }
}

/// The `unmergeTableCells` operation. Every merged cell overlapping `tableRange`
/// is unmerged back to individual cells.
public struct DocsUnmergeTableCellsRequest: Codable, Sendable, Equatable {
    public let tableRange: DocsTableRange

    public init(tableRange: DocsTableRange) {
        self.tableRange = tableRange
    }
}

/// The `pinTableHeaderRows` operation. `tableStartLocation` is a
/// ``DocsLocation`` at the table's start index and `pinnedHeaderRowsCount` is
/// the number of leading rows to pin as headers (0 unpins). Both are required
/// by the API.
public struct DocsPinTableHeaderRowsRequest: Codable, Sendable, Equatable {
    public let tableStartLocation: DocsLocation
    public let pinnedHeaderRowsCount: Int

    public init(tableStartLocation: DocsLocation, pinnedHeaderRowsCount: Int) {
        self.tableStartLocation = tableStartLocation
        self.pinnedHeaderRowsCount = pinnedHeaderRowsCount
    }
}

// MARK: - Tables (styling)
//
// These mirror the Docs v1 table styling operations: `updateTableCellStyle`,
// `updateTableRowStyle`, and `updateTableColumnProperties`, and their
// `TableCellStyle`, `TableCellBorder`, `TableRowStyle`, and
// `TableColumnProperties` sub-models. Only the writable subset graham sets is
// modeled; every style field is optional and the request's `fields` mask, not
// the container, decides which properties the API applies — the same discipline
// as the text and paragraph styling above. The three enums carry the exact API
// spellings as raw values, and are prefixed `Docs` because `GrahamKit` is one
// module and the bare `DashStyle`/`ContentAlignment` names already belong to the
// Slides write models.

/// A Docs v1 `TableCellStyle.contentAlignment` / `ContentAlignment`: the
/// vertical alignment of a cell's content. The cases are the writable values
/// graham sets; the API's `CONTENT_ALIGNMENT_UNSPECIFIED` and
/// `CONTENT_ALIGNMENT_UNSUPPORTED` sentinels are never sent.
public enum DocsContentAlignment: String, Codable, Sendable, Equatable {
    case top = "TOP"
    case middle = "MIDDLE"
    case bottom = "BOTTOM"
}

/// A Docs v1 `TableCellBorder.dashStyle` / `DashStyle`: how a cell border is
/// dashed. The Docs v1 `DashStyle` enum is exactly `DASH_STYLE_UNSPECIFIED`,
/// `SOLID`, `DOT`, and `DASH`, so these three cases are the complete writable
/// set — only the `DASH_STYLE_UNSPECIFIED` sentinel is omitted. (The extra
/// `DASH_DOT` / `LONG_DASH` / `LONG_DASH_DOT` styles are Slides-only and do not
/// exist in the Docs API.)
public enum DocsDashStyle: String, Codable, Sendable, Equatable {
    case solid = "SOLID"
    case dot = "DOT"
    case dash = "DASH"
}

/// A Docs v1 `TableColumnProperties.widthType` / `WidthType`: how a table column
/// is sized. `EVENLY_DISTRIBUTED` shares the table width across columns and
/// forbids a `width`; `FIXED_WIDTH` pins the column to an explicit `width`
/// (>= 5 pt). The API's `WIDTH_TYPE_UNSPECIFIED` sentinel is never sent.
public enum DocsWidthType: String, Codable, Sendable, Equatable {
    case evenlyDistributed = "EVENLY_DISTRIBUTED"
    case fixedWidth = "FIXED_WIDTH"
}

/// The writable subset of a Docs `TableCellBorder`: the color, width, and dash
/// style of one side of a cell.
///
/// Every field is optional, but graham always fills all three when it sets a
/// border (see ``DocsClient/styleTableCells(documentId:tableStartIndex:row:column:rowSpan:columnSpan:segmentId:backgroundColor:borderColor:borderWidth:borderDash:padding:contentAlignment:requiredRevisionId:)``):
/// a border requires a color, and defaults its width to 1 pt and its dash to
/// solid. `color` is a ``DocsOptionalColor``; `width` is a ``DocsDimension`` in
/// points.
public struct DocsTableCellBorder: Codable, Sendable, Equatable {
    public let color: DocsOptionalColor?
    public let width: DocsDimension?
    public let dashStyle: DocsDashStyle?

    public init(
        color: DocsOptionalColor? = nil,
        width: DocsDimension? = nil,
        dashStyle: DocsDashStyle? = nil
    ) {
        self.color = color
        self.width = width
        self.dashStyle = dashStyle
    }
}

/// The writable subset of a Docs `TableCellStyle`.
///
/// Every field is optional; the request's `fields` mask, not this container,
/// decides which properties the API applies. `backgroundColor` is a
/// ``DocsOptionalColor``; the four borders are ``DocsTableCellBorder`` values;
/// the four paddings are ``DocsDimension`` values in points; `contentAlignment`
/// is the cell's vertical alignment. graham sets all four borders together and
/// all four paddings together, but the type keeps each side separate to mirror
/// the API exactly.
public struct DocsTableCellStyle: Codable, Sendable, Equatable {
    public let backgroundColor: DocsOptionalColor?
    public let borderLeft: DocsTableCellBorder?
    public let borderRight: DocsTableCellBorder?
    public let borderTop: DocsTableCellBorder?
    public let borderBottom: DocsTableCellBorder?
    public let paddingLeft: DocsDimension?
    public let paddingRight: DocsDimension?
    public let paddingTop: DocsDimension?
    public let paddingBottom: DocsDimension?
    public let contentAlignment: DocsContentAlignment?

    public init(
        backgroundColor: DocsOptionalColor? = nil,
        borderLeft: DocsTableCellBorder? = nil,
        borderRight: DocsTableCellBorder? = nil,
        borderTop: DocsTableCellBorder? = nil,
        borderBottom: DocsTableCellBorder? = nil,
        paddingLeft: DocsDimension? = nil,
        paddingRight: DocsDimension? = nil,
        paddingTop: DocsDimension? = nil,
        paddingBottom: DocsDimension? = nil,
        contentAlignment: DocsContentAlignment? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.borderLeft = borderLeft
        self.borderRight = borderRight
        self.borderTop = borderTop
        self.borderBottom = borderBottom
        self.paddingLeft = paddingLeft
        self.paddingRight = paddingRight
        self.paddingTop = paddingTop
        self.paddingBottom = paddingBottom
        self.contentAlignment = contentAlignment
    }
}

/// The writable subset of a Docs `TableRowStyle`.
///
/// Every field is optional; the request's `fields` mask decides which the API
/// applies. `minRowHeight` is a ``DocsDimension`` in points; `preventOverflow`
/// keeps the row's content from spilling across a page break.
///
/// `tableHeader` is deliberately absent. Google's `updateTableRowStyle` rejects
/// it ("Unallowed field: tableHeader"): header designation is structural and
/// read-only once a table exists. Designate headers when the table is created,
/// or pin leading rows with `DocsClient.pinTableHeaderRows`.
public struct DocsTableRowStyle: Codable, Sendable, Equatable {
    public let minRowHeight: DocsDimension?
    public let preventOverflow: Bool?

    public init(
        minRowHeight: DocsDimension? = nil,
        preventOverflow: Bool? = nil
    ) {
        self.minRowHeight = minRowHeight
        self.preventOverflow = preventOverflow
    }
}

/// The writable subset of a Docs `TableColumnProperties`.
///
/// `widthType` is required by the API when this is written; `width` is a
/// ``DocsDimension`` in points and is required only when `widthType` is
/// `FIXED_WIDTH` (and must be >= 5 pt). An `EVENLY_DISTRIBUTED` column carries
/// no `width`. Both stay optional so the container can express either shape; the
/// client enforces the pairing.
public struct DocsTableColumnProperties: Codable, Sendable, Equatable {
    public let widthType: DocsWidthType?
    public let width: DocsDimension?

    public init(widthType: DocsWidthType? = nil, width: DocsDimension? = nil) {
        self.widthType = widthType
        self.width = width
    }
}

/// The `updateTableCellStyle` operation. `tableCellStyle` and `fields` (a
/// comma-separated field mask of the ``DocsTableCellStyle`` paths to apply,
/// relative to the style root) are required. The target is exactly one of a
/// ``DocsTableRange`` (a subset of cells) or a ``DocsLocation`` at the table's
/// start (the whole table); the two inits keep those mutually exclusive — only
/// the chosen one is set, the other stays nil and is omitted when encoded, so a
/// dual-target body is unrepresentable.
public struct DocsUpdateTableCellStyleRequest: Codable, Sendable, Equatable {
    public let tableCellStyle: DocsTableCellStyle
    public let fields: String
    public let tableRange: DocsTableRange?
    public let tableStartLocation: DocsLocation?

    /// Styles the subset of cells in `tableRange`.
    public init(tableCellStyle: DocsTableCellStyle, fields: String, tableRange: DocsTableRange) {
        self.tableCellStyle = tableCellStyle
        self.fields = fields
        self.tableRange = tableRange
        self.tableStartLocation = nil
    }

    /// Styles the whole table at `tableStartLocation`.
    public init(
        tableCellStyle: DocsTableCellStyle, fields: String, tableStartLocation: DocsLocation
    ) {
        self.tableCellStyle = tableCellStyle
        self.fields = fields
        self.tableRange = nil
        self.tableStartLocation = tableStartLocation
    }
}

/// The `updateTableRowStyle` operation. `tableStartLocation`, `tableRowStyle`,
/// and `fields` (a comma-separated field mask of the ``DocsTableRowStyle`` paths
/// to apply) are required. `rowIndices` is the list of zero-based rows to style;
/// when nil (omitted) the API styles every row. graham passes nil for "all
/// rows" rather than an empty array — the two are equivalent to the API, and an
/// omitted field is the cleaner wire form.
public struct DocsUpdateTableRowStyleRequest: Codable, Sendable, Equatable {
    public let tableStartLocation: DocsLocation
    public let rowIndices: [Int]?
    public let tableRowStyle: DocsTableRowStyle
    public let fields: String

    public init(
        tableStartLocation: DocsLocation,
        rowIndices: [Int]?,
        tableRowStyle: DocsTableRowStyle,
        fields: String
    ) {
        self.tableStartLocation = tableStartLocation
        self.rowIndices = rowIndices
        self.tableRowStyle = tableRowStyle
        self.fields = fields
    }
}

/// The `updateTableColumnProperties` operation. `tableStartLocation`,
/// `tableColumnProperties`, and `fields` (a comma-separated field mask of the
/// ``DocsTableColumnProperties`` paths to apply) are required. `columnIndices`
/// is the list of zero-based columns to style; when nil (omitted) the API styles
/// every column. graham passes nil for "all columns" rather than an empty array,
/// matching the row-style shape above.
public struct DocsUpdateTableColumnPropertiesRequest: Codable, Sendable, Equatable {
    public let tableStartLocation: DocsLocation
    public let columnIndices: [Int]?
    public let tableColumnProperties: DocsTableColumnProperties
    public let fields: String

    public init(
        tableStartLocation: DocsLocation,
        columnIndices: [Int]?,
        tableColumnProperties: DocsTableColumnProperties,
        fields: String
    ) {
        self.tableStartLocation = tableStartLocation
        self.columnIndices = columnIndices
        self.tableColumnProperties = tableColumnProperties
        self.fields = fields
    }
}

// MARK: - Structure and images
//
// These mirror the Docs v1 structure and image operations: `insertPageBreak`,
// `insertInlineImage`, `replaceImage`, and `insertSectionBreak`. Page breaks and
// section breaks are body-only in the API
// (their location's segment id must be empty), so those two requests carry no
// segment. Inline images may go in the body, a header, or a footer (not a
// footnote), so they reuse the shared ``DocsLocation`` /
// ``DocsEndOfSegmentLocation`` segment handling. The two enums carry the exact
// API spellings as raw values and are prefixed `Docs` to stay clear of the
// Slides write models in this single module.

/// A Docs v1 `Size`: the width and height an object should appear as. Both are
/// ``DocsDimension`` values in points and both are optional — the API computes a
/// missing dimension from the image's resolution and the other dimension. graham
/// only ever sets an image's `objectSize`, so this is used solely by
/// ``DocsInsertInlineImageRequest``.
public struct DocsSize: Codable, Sendable, Equatable {
    public let height: DocsDimension?
    public let width: DocsDimension?

    public init(height: DocsDimension? = nil, width: DocsDimension? = nil) {
        self.height = height
        self.width = width
    }
}

/// A Docs v1 `InsertSectionBreakRequest.sectionType` / `SectionType`: whether an
/// inserted section starts immediately after the previous section
/// (`CONTINUOUS`) or on the next page (`NEXT_PAGE`). The cases are the writable
/// values; the API's `SECTION_TYPE_UNSPECIFIED` sentinel is never sent.
public enum DocsSectionType: String, Codable, Sendable, Equatable {
    case continuous = "CONTINUOUS"
    case nextPage = "NEXT_PAGE"
}

/// A Docs v1 `ReplaceImageRequest.imageReplaceMethod` / `ImageReplaceMethod`:
/// how a replacement image is fitted. The API defines exactly one usable value,
/// `CENTER_CROP` (scale-and-center, cropping to fill the original bounds); the
/// `IMAGE_REPLACE_METHOD_UNSPECIFIED` sentinel must not be used, so the only
/// case is `centerCrop` and ``DocsClient/replaceImage(documentId:imageObjectId:uri:requiredRevisionId:)``
/// always sends it.
public enum DocsImageReplaceMethod: String, Codable, Sendable, Equatable {
    case centerCrop = "CENTER_CROP"
}

/// The `insertPageBreak` operation. The destination is exactly one of a body
/// index or the end of the body. Page breaks are body-only in the API — the
/// location's segment id must be empty — so this type is body-only **by
/// construction**: its public entry points take only a bare index or select the
/// end of the body, and build a ``DocsLocation`` / ``DocsEndOfSegmentLocation``
/// with no segment id internally. A caller therefore cannot smuggle in an
/// illegal non-body request through the public ``DocsClient/batchUpdate(documentId:requests:requiredRevisionId:)``.
/// The two entry points keep the destinations mutually exclusive: only the
/// chosen one is set, and the other stays nil and is omitted when encoded.
public struct DocsInsertPageBreakRequest: Codable, Sendable, Equatable {
    public let location: DocsLocation?
    public let endOfSegmentLocation: DocsEndOfSegmentLocation?

    private init(location: DocsLocation?, endOfSegmentLocation: DocsEndOfSegmentLocation?) {
        self.location = location
        self.endOfSegmentLocation = endOfSegmentLocation
    }

    /// Inserts the page break at a zero-based body index. The location carries
    /// no segment id.
    public init(bodyIndex: Int) {
        self.init(location: DocsLocation(index: bodyIndex), endOfSegmentLocation: nil)
    }

    /// A page break at the end of the document body. The end-of-segment location
    /// carries no segment id.
    public static let endOfBody = DocsInsertPageBreakRequest(
        location: nil, endOfSegmentLocation: DocsEndOfSegmentLocation())
}

/// The `insertInlineImage` operation. The `uri` is required and must be a
/// publicly fetchable image (< 50MB, <= 25 megapixels, PNG/JPEG/GIF). The
/// destination is exactly one of a ``DocsLocation`` (an explicit index, in the
/// body or a header/footer segment) or a ``DocsEndOfSegmentLocation`` (append to
/// the end of the body or a segment). `objectSize` is optional; when omitted the
/// API sizes the image from its resolution. The two inits keep the destinations
/// mutually exclusive: only the chosen one is set, and the other stays nil and is
/// omitted when encoded. The reply carries the new object id
/// (``DocsInsertInlineImageReply``).
public struct DocsInsertInlineImageRequest: Codable, Sendable, Equatable {
    public let uri: String
    public let location: DocsLocation?
    public let endOfSegmentLocation: DocsEndOfSegmentLocation?
    public let objectSize: DocsSize?

    public init(uri: String, location: DocsLocation, objectSize: DocsSize? = nil) {
        self.uri = uri
        self.location = location
        self.endOfSegmentLocation = nil
        self.objectSize = objectSize
    }

    public init(
        uri: String, endOfSegmentLocation: DocsEndOfSegmentLocation, objectSize: DocsSize? = nil
    ) {
        self.uri = uri
        self.location = nil
        self.endOfSegmentLocation = endOfSegmentLocation
        self.objectSize = objectSize
    }
}

/// The `replaceImage` operation. `imageObjectId` names the existing image to
/// replace, `uri` is the new image (same fetch rules as `insertInlineImage`),
/// and `imageReplaceMethod` is the fit method — all required by the API. The
/// only usable method is ``DocsImageReplaceMethod/centerCrop``.
public struct DocsReplaceImageRequest: Codable, Sendable, Equatable {
    public let imageObjectId: String
    public let uri: String
    public let imageReplaceMethod: DocsImageReplaceMethod

    public init(imageObjectId: String, uri: String, imageReplaceMethod: DocsImageReplaceMethod) {
        self.imageObjectId = imageObjectId
        self.uri = uri
        self.imageReplaceMethod = imageReplaceMethod
    }
}

/// The `insertSectionBreak` operation. `sectionType` is required. The
/// destination is exactly one of a body index or the end of the body. Section
/// breaks are body-only in the API — the location's segment id must be empty —
/// so this type is body-only **by construction**: its public entry points take
/// only a bare index or select the end of the body, and build a ``DocsLocation``
/// / ``DocsEndOfSegmentLocation`` with no segment id internally, so a caller
/// cannot smuggle in an illegal non-body request through the public
/// ``DocsClient/batchUpdate(documentId:requests:requiredRevisionId:)``. The two
/// entry points keep the destinations mutually exclusive: only the chosen one is
/// set, and the other stays nil and is omitted when encoded.
public struct DocsInsertSectionBreakRequest: Codable, Sendable, Equatable {
    public let sectionType: DocsSectionType
    public let location: DocsLocation?
    public let endOfSegmentLocation: DocsEndOfSegmentLocation?

    private init(
        sectionType: DocsSectionType,
        location: DocsLocation?,
        endOfSegmentLocation: DocsEndOfSegmentLocation?
    ) {
        self.sectionType = sectionType
        self.location = location
        self.endOfSegmentLocation = endOfSegmentLocation
    }

    /// Inserts the section break at a zero-based body index. The location
    /// carries no segment id.
    public init(sectionType: DocsSectionType, bodyIndex: Int) {
        self.init(
            sectionType: sectionType,
            location: DocsLocation(index: bodyIndex),
            endOfSegmentLocation: nil)
    }

    /// A section break at the end of the document body. The end-of-segment
    /// location carries no segment id.
    public static func endOfBody(sectionType: DocsSectionType) -> DocsInsertSectionBreakRequest {
        DocsInsertSectionBreakRequest(
            sectionType: sectionType,
            location: nil,
            endOfSegmentLocation: DocsEndOfSegmentLocation())
    }
}

// MARK: - Headers, footers, footnotes
//
// These mirror the Docs v1 `createHeader`, `createFooter`, `deleteHeader`,
// `deleteFooter`, and `createFootnote` operations. A create's reply carries the
// new segment id (`headerId` / `footerId` / `footnoteId`) so follow-up
// segment-aware writes can target it. Headers and footers can optionally be
// scoped to a section through a body ``DocsLocation`` at a section break;
// footnote references live in the document body, so a `createFootnote`'s
// location is body-only **by construction**, exactly like the page-break and
// section-break requests above. The `type` enum carries the exact API spelling
// and is prefixed `Docs` to stay clear of the Slides write models in this single
// module.

/// A Docs v1 `HeaderFooterType`: the kind of header or footer to create. The API
/// enum is `HEADER_FOOTER_TYPE_UNSPECIFIED` and `DEFAULT`; only `DEFAULT` is a
/// usable value (the `*_UNSPECIFIED` sentinel is never sent), so this enum models
/// exactly the one writable case. ``DocsClient`` always sends it.
public enum DocsHeaderFooterType: String, Codable, Sendable, Equatable {
    case `default` = "DEFAULT"
}

/// The `createHeader` operation. `type` is required and is always
/// ``DocsHeaderFooterType/default``. `sectionBreakLocation` optionally scopes the
/// header to the section a body ``DocsLocation`` names (a zero-based UTF-16 index
/// at a section break); when omitted, the header applies to the whole document.
/// The reply carries the new header segment id (``DocsCreateHeaderReply``).
public struct DocsCreateHeaderRequest: Codable, Sendable, Equatable {
    public let type: DocsHeaderFooterType
    public let sectionBreakLocation: DocsLocation?

    public init(type: DocsHeaderFooterType = .default, sectionBreakLocation: DocsLocation? = nil) {
        self.type = type
        self.sectionBreakLocation = sectionBreakLocation
    }
}

/// The `createFooter` operation. Same shape as ``DocsCreateHeaderRequest``: a
/// required ``DocsHeaderFooterType`` (always `DEFAULT`) and an optional body
/// ``DocsLocation`` scoping the footer to a section. The reply carries the new
/// footer segment id (``DocsCreateFooterReply``).
public struct DocsCreateFooterRequest: Codable, Sendable, Equatable {
    public let type: DocsHeaderFooterType
    public let sectionBreakLocation: DocsLocation?

    public init(type: DocsHeaderFooterType = .default, sectionBreakLocation: DocsLocation? = nil) {
        self.type = type
        self.sectionBreakLocation = sectionBreakLocation
    }
}

/// The `deleteHeader` operation. `headerId` names the header segment to delete
/// (the id a `createHeader` reply returned). Required by the API.
public struct DocsDeleteHeaderRequest: Codable, Sendable, Equatable {
    public let headerId: String

    public init(headerId: String) {
        self.headerId = headerId
    }
}

/// The `deleteFooter` operation. `footerId` names the footer segment to delete
/// (the id a `createFooter` reply returned). Required by the API.
public struct DocsDeleteFooterRequest: Codable, Sendable, Equatable {
    public let footerId: String

    public init(footerId: String) {
        self.footerId = footerId
    }
}

/// The `createFootnote` operation. The destination is exactly one of a body index
/// or the end of the body. A footnote reference lives in the document body — the
/// location's segment id must be empty — so this type is body-only **by
/// construction**: its public entry points take only a bare index or select the
/// end of the body, and build a ``DocsLocation`` / ``DocsEndOfSegmentLocation``
/// with no segment id internally, so a caller cannot smuggle in an illegal
/// non-body request through the public
/// ``DocsClient/batchUpdate(documentId:requests:requiredRevisionId:)``. The two
/// entry points keep the destinations mutually exclusive: only the chosen one is
/// set, and the other stays nil and is omitted when encoded. The reply carries
/// the new footnote segment id (``DocsCreateFootnoteReply``); the created
/// footnote segment starts with an auto-inserted space and newline.
public struct DocsCreateFootnoteRequest: Codable, Sendable, Equatable {
    public let location: DocsLocation?
    public let endOfSegmentLocation: DocsEndOfSegmentLocation?

    private init(location: DocsLocation?, endOfSegmentLocation: DocsEndOfSegmentLocation?) {
        self.location = location
        self.endOfSegmentLocation = endOfSegmentLocation
    }

    /// Inserts the footnote reference at a zero-based body index. The location
    /// carries no segment id.
    public init(bodyIndex: Int) {
        self.init(location: DocsLocation(index: bodyIndex), endOfSegmentLocation: nil)
    }

    /// A footnote reference at the end of the document body. The end-of-segment
    /// location carries no segment id.
    public static let endOfBody = DocsCreateFootnoteRequest(
        location: nil, endOfSegmentLocation: DocsEndOfSegmentLocation())
}

// MARK: - Named ranges and document style
//
// These mirror the Docs v1 `createNamedRange`, `deleteNamedRange`,
// `replaceNamedRangeContent`, and `updateDocumentStyle` operations, plus the
// `DocumentStyle`, `Background`, and (reused) `Size` / `Dimension` sub-models.
// A named range labels a zero-based UTF-16 range so a later write can fill it —
// the template-filling primitive. The two range selectors on the delete and
// replace operations are a Google `oneof`: each is modeled with two dedicated
// inits (exactly one field set, the other nil and omitted when encoded), the
// same discipline as ``DocsWriteControl`` and ``DocsInsertTextRequest``, so a
// dual-selector body is unrepresentable. `updateDocumentStyle` follows the
// styling `fields`-mask discipline: every style field is optional and the
// request's mask, not the container, decides which properties the API applies.

/// The `createNamedRange` operation. `name` is required and must be 1 to 256
/// UTF-16 code units (names need not be unique); `range` is the zero-based
/// UTF-16 span to name. The reply carries the new named-range id
/// (``DocsCreateNamedRangeReply``).
public struct DocsCreateNamedRangeRequest: Codable, Sendable, Equatable {
    public let name: String
    public let range: DocsRange

    public init(name: String, range: DocsRange) {
        self.name = name
        self.range = range
    }
}

/// The `deleteNamedRange` operation. The target is exactly one of a
/// `namedRangeId` (deletes that one range) or a `name` (deletes every range
/// sharing the name). The two inits keep those mutually exclusive — only the
/// chosen one is set, and the other stays nil and is omitted when encoded, so a
/// dual-selector body is unrepresentable.
public struct DocsDeleteNamedRangeRequest: Codable, Sendable, Equatable {
    public let namedRangeId: String?
    public let name: String?

    /// Deletes the single named range with this id.
    public init(namedRangeId: String) {
        self.namedRangeId = namedRangeId
        self.name = nil
    }

    /// Deletes every named range sharing this name.
    public init(name: String) {
        self.namedRangeId = nil
        self.name = name
    }
}

/// The `replaceNamedRangeContent` operation. `text` replaces the named range's
/// content (an empty string clears it); a discontinuous named range replaces
/// only its first subrange. The target is exactly one of a `namedRangeId`
/// (that one range) or a `namedRangeName` (every range sharing the name); the
/// two inits keep those mutually exclusive — only the chosen one is set, and the
/// other stays nil and is omitted when encoded. The API field for the name
/// selector is `namedRangeName` (not `name`), unlike ``DocsDeleteNamedRangeRequest``.
public struct DocsReplaceNamedRangeContentRequest: Codable, Sendable, Equatable {
    public let namedRangeId: String?
    public let namedRangeName: String?
    public let text: String

    /// Replaces the content of the single named range with this id.
    public init(namedRangeId: String, text: String) {
        self.namedRangeId = namedRangeId
        self.namedRangeName = nil
        self.text = text
    }

    /// Replaces the content of every named range sharing this name.
    public init(namedRangeName: String, text: String) {
        self.namedRangeId = nil
        self.namedRangeName = namedRangeName
        self.text = text
    }
}

/// A Docs v1 `Background`: the background of a document. The API models it with
/// a single ``DocsOptionalColor`` (a document background cannot be transparent,
/// so graham always sets a solid color). The other appearance surfaces reuse
/// ``DocsOptionalColor`` too, so this is a thin wrapper matching the API shape.
public struct DocsBackground: Codable, Sendable, Equatable {
    public let color: DocsOptionalColor?

    public init(color: DocsOptionalColor? = nil) {
        self.color = color
    }
}

/// A Docs v1 `DocumentMode`: whether the document has pages or is pageless. The
/// cases are the writable values; the API's `DOCUMENT_MODE_UNSPECIFIED` sentinel
/// is never sent, exactly like the other `*_UNSPECIFIED` sentinels in these
/// models. Each raw value is the exact API spelling.
public enum DocsDocumentMode: String, Codable, Sendable, Equatable {
    case pages = "PAGES"
    case pageless = "PAGELESS"
}

/// A Docs v1 `DocumentFormat`: document-level format settings. graham writes only
/// the document mode (pages vs pageless), so this models just ``documentMode``;
/// the field stays optional and the request's `fields` mask decides whether it
/// applies. It reaches the wire through ``DocsDocumentStyle/documentFormat``, and
/// the mask masks the nested path `documentFormat.documentMode` so only the mode
/// is set (never clearing any future `DocumentFormat` field).
public struct DocsDocumentFormat: Codable, Sendable, Equatable {
    public let documentMode: DocsDocumentMode?

    public init(documentMode: DocsDocumentMode? = nil) {
        self.documentMode = documentMode
    }
}

/// The writable subset of a Docs `DocumentStyle`.
///
/// Every field is optional; the request's `fields` mask, not this container,
/// decides which properties the API applies. `pageSize` is a ``DocsSize`` whose
/// width and height are ``DocsDimension`` values in points; the four margins are
/// ``DocsDimension`` values in points; `useFirstPageHeaderFooter` and
/// `useEvenPageHeaderFooter` toggle the first-page and even-page header/footer
/// ids; `background` sets the document background color; `documentFormat` carries
/// the document mode (pages vs pageless). `pageNumberStart` is the first visible
/// page number; `marginHeader` and `marginFooter` are the header and footer
/// margins in points; `flipPageOrientation` swaps the page width and height
/// (landscape). The read-only header/footer ids and the read-only
/// `useCustomHeaderFooterMargins` flag (the server derives whether the custom
/// header/footer margins apply) are out of this slice.
public struct DocsDocumentStyle: Codable, Sendable, Equatable {
    public let pageSize: DocsSize?
    public let marginTop: DocsDimension?
    public let marginBottom: DocsDimension?
    public let marginLeft: DocsDimension?
    public let marginRight: DocsDimension?
    public let useFirstPageHeaderFooter: Bool?
    public let useEvenPageHeaderFooter: Bool?
    public let background: DocsBackground?
    public let documentFormat: DocsDocumentFormat?
    public let pageNumberStart: Int?
    public let marginHeader: DocsDimension?
    public let marginFooter: DocsDimension?
    public let flipPageOrientation: Bool?

    public init(
        pageSize: DocsSize? = nil,
        marginTop: DocsDimension? = nil,
        marginBottom: DocsDimension? = nil,
        marginLeft: DocsDimension? = nil,
        marginRight: DocsDimension? = nil,
        useFirstPageHeaderFooter: Bool? = nil,
        useEvenPageHeaderFooter: Bool? = nil,
        background: DocsBackground? = nil,
        documentFormat: DocsDocumentFormat? = nil,
        pageNumberStart: Int? = nil,
        marginHeader: DocsDimension? = nil,
        marginFooter: DocsDimension? = nil,
        flipPageOrientation: Bool? = nil
    ) {
        self.pageSize = pageSize
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.useFirstPageHeaderFooter = useFirstPageHeaderFooter
        self.useEvenPageHeaderFooter = useEvenPageHeaderFooter
        self.background = background
        self.documentFormat = documentFormat
        self.pageNumberStart = pageNumberStart
        self.marginHeader = marginHeader
        self.marginFooter = marginFooter
        self.flipPageOrientation = flipPageOrientation
    }
}

/// The `updateDocumentStyle` operation. `fields` is a comma-separated field mask
/// of the ``DocsDocumentStyle`` paths to apply, relative to the style root; at
/// least one path is required. The style change is document-wide (Docs has no
/// per-tab document style in this slice).
public struct DocsUpdateDocumentStyleRequest: Codable, Sendable, Equatable {
    public let documentStyle: DocsDocumentStyle
    public let fields: String

    public init(documentStyle: DocsDocumentStyle, fields: String) {
        self.documentStyle = documentStyle
        self.fields = fields
    }
}

// MARK: - Section style

/// A Docs v1 `SectionStyle.columnSeparatorStyle`: the line drawn between columns
/// of a multi-column section.
public enum DocsColumnSeparatorStyle: String, Codable, Sendable, Equatable {
    case none = "NONE"
    case betweenEachColumn = "BETWEEN_EACH_COLUMN"
}

/// The writable subset of a Docs `SectionStyle`.
///
/// Margins are in points; `columnSeparatorStyle` and `contentDirection` are
/// enums; `pageNumberStart` is the first page number for the section;
/// `useFirstPageHeaderFooter` toggles the first-page header/footer for the
/// section; `flipPageOrientation` swaps the section's page width and height.
/// The section's header/footer ids and `sectionType` are read-only (the server
/// assigns them), and the per-column `columnProperties` layout is out of this
/// slice, so none of those are modeled here.
public struct DocsSectionStyle: Codable, Sendable, Equatable {
    public let marginTop: DocsDimension?
    public let marginBottom: DocsDimension?
    public let marginLeft: DocsDimension?
    public let marginRight: DocsDimension?
    public let marginHeader: DocsDimension?
    public let marginFooter: DocsDimension?
    public let columnSeparatorStyle: DocsColumnSeparatorStyle?
    public let contentDirection: DocsContentDirection?
    public let pageNumberStart: Int?
    public let useFirstPageHeaderFooter: Bool?
    public let flipPageOrientation: Bool?

    public init(
        marginTop: DocsDimension? = nil,
        marginBottom: DocsDimension? = nil,
        marginLeft: DocsDimension? = nil,
        marginRight: DocsDimension? = nil,
        marginHeader: DocsDimension? = nil,
        marginFooter: DocsDimension? = nil,
        columnSeparatorStyle: DocsColumnSeparatorStyle? = nil,
        contentDirection: DocsContentDirection? = nil,
        pageNumberStart: Int? = nil,
        useFirstPageHeaderFooter: Bool? = nil,
        flipPageOrientation: Bool? = nil
    ) {
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.marginHeader = marginHeader
        self.marginFooter = marginFooter
        self.columnSeparatorStyle = columnSeparatorStyle
        self.contentDirection = contentDirection
        self.pageNumberStart = pageNumberStart
        self.useFirstPageHeaderFooter = useFirstPageHeaderFooter
        self.flipPageOrientation = flipPageOrientation
    }
}

/// The `updateSectionStyle` operation. `range` selects the sections to restyle
/// (its `segmentId` must be empty — section style is a body-only concept);
/// `sectionStyle` carries the new values; `fields` is a comma-separated field
/// mask of the ``DocsSectionStyle`` paths to apply, relative to the style root.
/// At least one path is required.
public struct DocsUpdateSectionStyleRequest: Codable, Sendable, Equatable {
    public let range: DocsRange
    public let sectionStyle: DocsSectionStyle
    public let fields: String

    public init(range: DocsRange, sectionStyle: DocsSectionStyle, fields: String) {
        self.range = range
        self.sectionStyle = sectionStyle
        self.fields = fields
    }
}

// MARK: - Responses

/// The response of a `documents.batchUpdate` call.
public struct DocsBatchUpdateResponse: Codable, Sendable {
    public let documentId: String?
    /// One reply per request, in request order. Operations such as
    /// `insertText` and `deleteContentRange` return an empty reply object.
    public let replies: [DocsBatchUpdateReply]?
    /// The write control after the write, carrying the resulting
    /// `requiredRevisionId`/`targetRevisionId`. Optional and decoded
    /// defensively, like every other response field.
    public let writeControl: DocsWriteControl?
}

/// One reply in a Docs batch-update response.
///
/// Only some operations carry a payload: `replaceAllText` reports the number of
/// occurrences changed, `insertInlineImage` returns the new object id,
/// `createHeader` / `createFooter` / `createFootnote` return the new segment id,
/// and `createNamedRange` returns the new named-range id. The structure
/// operations (`insertText`, `deleteContentRange`, `insertPageBreak`,
/// `replaceImage`, `insertSectionBreak`,
/// `deleteHeader`, `deleteFooter`, `deleteNamedRange`, `replaceNamedRangeContent`,
/// `updateDocumentStyle`, and the table ops) reply with an empty object, so this
/// decodes to a reply whose every field is nil.
public struct DocsBatchUpdateReply: Codable, Sendable {
    public let replaceAllText: DocsReplaceAllTextReply?
    public let insertInlineImage: DocsInsertInlineImageReply?
    public let createHeader: DocsCreateHeaderReply?
    public let createFooter: DocsCreateFooterReply?
    public let createFootnote: DocsCreateFootnoteReply?
    public let createNamedRange: DocsCreateNamedRangeReply?
}

/// The reply of a `replaceAllText` operation.
public struct DocsReplaceAllTextReply: Codable, Sendable {
    /// The number of occurrences that were replaced.
    public let occurrencesChanged: Int?
}

/// The reply of an `insertInlineImage` operation, carrying the id of the newly
/// created inline object so a caller can address the image afterwards.
public struct DocsInsertInlineImageReply: Codable, Sendable {
    /// The ID of the created inline object.
    public let objectId: String?
}

/// The reply of a `createHeader` operation, carrying the id of the newly created
/// header segment so a caller can target it with segment-aware writes.
public struct DocsCreateHeaderReply: Codable, Sendable {
    /// The ID of the created header.
    public let headerId: String?
}

/// The reply of a `createFooter` operation, carrying the id of the newly created
/// footer segment so a caller can target it with segment-aware writes.
public struct DocsCreateFooterReply: Codable, Sendable {
    /// The ID of the created footer.
    public let footerId: String?
}

/// The reply of a `createFootnote` operation, carrying the id of the newly
/// created footnote segment so a caller can target it with segment-aware writes.
public struct DocsCreateFootnoteReply: Codable, Sendable {
    /// The ID of the created footnote.
    public let footnoteId: String?
}

/// The reply of a `createNamedRange` operation, carrying the id of the newly
/// created named range so a caller can address it with the delete and
/// replace-content operations.
public struct DocsCreateNamedRangeReply: Codable, Sendable {
    /// The ID of the created named range.
    public let namedRangeId: String?
}
