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

/// The body of a `documents.batchUpdate` POST.
struct DocsBatchUpdateRequestBody: Encodable, Sendable {
    let requests: [DocsBatchUpdateRequest]
}

// MARK: - Shared locations

/// A position within a document, at a zero-based offset.
///
/// `index` is a zero-based offset in **UTF-16 code units** into the document's
/// content, exactly as the Docs API defines it. This is the API index model:
/// unlike the one-based slide, table, and link positions elsewhere in graham,
/// Docs text indices stay zero-based to match the API. `segmentId` names a
/// header, footer, or footnote segment; when omitted, the index refers to the
/// document body.
public struct DocsLocation: Codable, Sendable, Equatable {
    public let index: Int
    public let segmentId: String?

    public init(index: Int, segmentId: String? = nil) {
        self.index = index
        self.segmentId = segmentId
    }
}

/// A half-open `[startIndex, endIndex)` span of content, in zero-based UTF-16
/// code units.
///
/// `segmentId` names a header, footer, or footnote segment; when omitted, the
/// range refers to the document body.
public struct DocsRange: Codable, Sendable, Equatable {
    public let startIndex: Int
    public let endIndex: Int
    public let segmentId: String?

    public init(startIndex: Int, endIndex: Int, segmentId: String? = nil) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.segmentId = segmentId
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
