import Foundation

extension DocsClient {
    // MARK: - Smart chips

    /// Where a smart-chip insert lands: a body/segment index location, or the
    /// end of a segment (no index needed). Exactly one, so a chip request never
    /// carries both.
    private enum InsertTarget {
        case location(DocsLocation)
        case endOfSegment(DocsEndOfSegmentLocation)
    }

    /// Builds a smart-chip insert target, applying the same index guards as
    /// `insertText`: the document body's first editable index is 1; a named
    /// segment starts its content at 0. An empty `segmentId` is normalized to the
    /// body. `endOfSegment` appends to the end of the segment (or body).
    private static func makeInsertTarget(
        index: Int, segmentId: String?, endOfSegment: Bool, tabId: String?
    ) throws -> InsertTarget {
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        if endOfSegment {
            return .endOfSegment(DocsEndOfSegmentLocation(segmentId: segmentId, tabId: tabId))
        }
        if segmentId == nil {
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
        } else {
            guard index >= 0 else {
                throw GrahamError.invalidArgument("index must be 0 or greater in a segment")
            }
        }
        return .location(DocsLocation(index: index, segmentId: segmentId, tabId: tabId))
    }

    /// Inserts a person smart chip (a linked `email`, with an optional display
    /// `name`) at an index or the end of a segment. See ``makeInsertTarget`` for
    /// the index rules.
    public func insertPerson(
        documentId: String,
        email: String,
        name: String? = nil,
        index: Int = 1,
        segmentId: String? = nil,
        endOfSegment: Bool = false,
        tabId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrahamError.invalidArgument("a person chip requires an email")
        }
        let properties = DocsPersonProperties(email: email, name: name)
        let request: DocsInsertPersonRequest
        switch try Self.makeInsertTarget(
            index: index, segmentId: segmentId, endOfSegment: endOfSegment, tabId: tabId) {
        case .location(let location):
            request = DocsInsertPersonRequest(personProperties: properties, location: location)
        case .endOfSegment(let end):
            request = DocsInsertPersonRequest(
                personProperties: properties, endOfSegmentLocation: end)
        }
        return try await batchUpdate(
            documentId: documentId, requests: [.insertPerson(request)],
            requiredRevisionId: requiredRevisionId)
    }

    /// Inserts a rich-link smart chip (a Drive/YouTube/Calendar `uri`, with an
    /// optional `title` and `mimeType`) at an index or the end of a segment.
    public func insertRichLink(
        documentId: String,
        uri: String,
        title: String? = nil,
        mimeType: String? = nil,
        index: Int = 1,
        segmentId: String? = nil,
        endOfSegment: Bool = false,
        tabId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrahamError.invalidArgument("a rich-link chip requires a uri")
        }
        let properties = DocsRichLinkProperties(uri: uri, title: title, mimeType: mimeType)
        let request: DocsInsertRichLinkRequest
        switch try Self.makeInsertTarget(
            index: index, segmentId: segmentId, endOfSegment: endOfSegment, tabId: tabId) {
        case .location(let location):
            request = DocsInsertRichLinkRequest(richLinkProperties: properties, location: location)
        case .endOfSegment(let end):
            request = DocsInsertRichLinkRequest(
                richLinkProperties: properties, endOfSegmentLocation: end)
        }
        return try await batchUpdate(
            documentId: documentId, requests: [.insertRichLink(request)],
            requiredRevisionId: requiredRevisionId)
    }

    /// Inserts a date smart chip (a `timestamp`, an RFC 3339 date-time, with an
    /// optional locale, time zone, and date/time formats) at an index or the end
    /// of a segment.
    public func insertDate(
        documentId: String,
        timestamp: String,
        locale: String? = nil,
        timeZoneId: String? = nil,
        dateFormat: DocsDateFormat? = nil,
        timeFormat: DocsTimeFormat? = nil,
        index: Int = 1,
        segmentId: String? = nil,
        endOfSegment: Bool = false,
        tabId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !timestamp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrahamError.invalidArgument("a date chip requires a timestamp")
        }
        let properties = DocsDateElementProperties(
            timestamp: timestamp,
            locale: locale,
            timeZoneId: timeZoneId,
            dateFormat: dateFormat,
            timeFormat: timeFormat)
        let request: DocsInsertDateRequest
        switch try Self.makeInsertTarget(
            index: index, segmentId: segmentId, endOfSegment: endOfSegment, tabId: tabId) {
        case .location(let location):
            request = DocsInsertDateRequest(dateElementProperties: properties, location: location)
        case .endOfSegment(let end):
            request = DocsInsertDateRequest(
                dateElementProperties: properties, endOfSegmentLocation: end)
        }
        return try await batchUpdate(
            documentId: documentId, requests: [.insertDate(request)],
            requiredRevisionId: requiredRevisionId)
    }
}
