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

    private enum CodingKeys: String, CodingKey {
        case insertText
        case deleteContentRange
        case replaceAllText
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
        }
    }
}

/// Optimistic-concurrency control for a `documents.batchUpdate` write.
///
/// `requiredRevisionId` makes the write apply only if the document is still at
/// that revision, failing otherwise so a concurrent edit is never silently
/// overwritten. `targetRevisionId` applies the write against an older revision,
/// transforming it forward. The two are mutually exclusive; graham sets only
/// `requiredRevisionId`. Both encode only when set, so a body with no write
/// control omits the field entirely. The document's current revision is
/// `Document.revisionId` (populated by the richer read phase).
public struct DocsWriteControl: Codable, Sendable, Equatable {
    public let requiredRevisionId: String?
    public let targetRevisionId: String?

    public init(requiredRevisionId: String? = nil, targetRevisionId: String? = nil) {
        self.requiredRevisionId = requiredRevisionId
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
/// when omitted, the target is the end of the document body. The Docs API's
/// `EndOfSegmentLocation`; an `insertText` uses either this or a
/// ``DocsLocation``, never both.
public struct DocsEndOfSegmentLocation: Codable, Sendable, Equatable {
    public let segmentId: String?

    public init(segmentId: String? = nil) {
        self.segmentId = segmentId
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

/// The `insertText` operation. Both the text and the insertion location are
/// required by the API.
public struct DocsInsertTextRequest: Codable, Sendable, Equatable {
    public let text: String
    public let location: DocsLocation

    public init(text: String, location: DocsLocation) {
        self.text = text
        self.location = location
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
