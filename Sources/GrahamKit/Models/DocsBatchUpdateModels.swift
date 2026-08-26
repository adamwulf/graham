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

    private enum CodingKeys: String, CodingKey {
        case insertText
        case deleteContentRange
        case replaceAllText
        case updateTextStyle
        case updateParagraphStyle
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

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
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
/// `fontFamily` field.
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
        link: DocsLink? = nil
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
    }
}

/// The writable subset of a Docs `ParagraphStyle`.
///
/// Every field is optional; the request's `fields` mask, not this container,
/// decides which properties the API applies. `lineSpacing` is a percent of
/// normal (100 = single); the spacing and indent dimensions are in points.
/// Paragraph borders and shading are out of this slice.
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

    public init(
        namedStyleType: DocsNamedStyleType? = nil,
        alignment: DocsParagraphAlignment? = nil,
        direction: DocsContentDirection? = nil,
        lineSpacing: Double? = nil,
        spaceAbove: DocsDimension? = nil,
        spaceBelow: DocsDimension? = nil,
        indentStart: DocsDimension? = nil,
        indentEnd: DocsDimension? = nil,
        indentFirstLine: DocsDimension? = nil
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
/// Only `replaceAllText` carries a payload; `insertText` and
/// `deleteContentRange` reply with an empty object, so this decodes to a reply
/// whose every field is nil.
public struct DocsBatchUpdateReply: Codable, Sendable {
    public let replaceAllText: DocsReplaceAllTextReply?
}

/// The reply of a `replaceAllText` operation.
public struct DocsReplaceAllTextReply: Codable, Sendable {
    /// The number of occurrences that were replaced.
    public let occurrencesChanged: Int?
}
