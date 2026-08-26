import Foundation

/// The high-level client for the Docs v1 API.
public struct DocsClient: Sendable {
    public static let baseURL = "https://docs.googleapis.com/v1"

    private let api: GoogleAPI

    public init(api: GoogleAPI) {
        self.api = api
    }

    /// Gets one document, with its body content.
    public func document(id: String) async throws -> Document {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/documents/\(GoogleURL.escapePathComponent(id))"
        )
        return try await api.getJSON(Document.self, from: url)
    }

    /// Creates a new, blank document from a `title` via `documents.create`,
    /// returning the created ``Document`` (whose `documentId` is the value the
    /// `docs create` command prints). The new document's body is empty until a
    /// later ``batchUpdate(documentId:requests:requiredRevisionId:)`` fills it.
    ///
    /// The title is carried in a JSON request body, not in the URL, so it is
    /// encoded safely no matter what characters it holds.
    public func create(title: String) async throws -> Document {
        let url = try GoogleURL.build("\(Self.baseURL)/documents")
        return try await api.sendJSON(
            Document.self,
            method: "POST",
            url: url,
            body: DocsCreateRequest(title: title)
        )
    }

    // MARK: - Writes

    /// Sends one `documents.batchUpdate` call with `requests`, in order.
    ///
    /// This is the shared Docs batch-write path. High-level operations build
    /// typed ``DocsBatchUpdateRequest`` values and go through this method.
    ///
    /// When `requiredRevisionId` is set, it is carried as a ``DocsWriteControl``
    /// so the write applies only if the document is still at that revision —
    /// optimistic concurrency that fails the write rather than overwriting a
    /// concurrent edit. When nil (the default), no write control is sent and
    /// the body stays `{"requests": [...]}`.
    public func batchUpdate(
        documentId: String,
        requests: [DocsBatchUpdateRequest],
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/documents/\(GoogleURL.escapePathComponent(documentId)):batchUpdate"
        )
        let writeControl = requiredRevisionId.map {
            DocsWriteControl(requiredRevisionId: $0)
        }
        return try await api.sendJSON(
            DocsBatchUpdateResponse.self,
            method: "POST",
            url: url,
            body: DocsBatchUpdateRequestBody(requests: requests, writeControl: writeControl)
        )
    }

    /// Inserts `text` at a zero-based document index.
    ///
    /// `index` is a zero-based offset in **UTF-16 code units** into the
    /// document, exactly as the Docs API defines it (see ``DocsLocation``). The
    /// API index model is kept for Docs text operations; graham does not
    /// translate it to a one-based position the way it does for slides and
    /// tables.
    /// - Parameters:
    ///   - segmentId: names a header, footer, or footnote segment to insert
    ///     into; when nil, the insert targets the document body. A named segment
    ///     starts its content at index 0, so the body-only `index >= 1` guard
    ///     does not apply to it.
    ///   - endOfSegment: append to the end of the segment (or the body, when
    ///     `segmentId` is nil) without computing an index. `index` is ignored in
    ///     this mode, and no index guard applies. This encodes an
    ///     ``DocsEndOfSegmentLocation`` instead of a ``DocsLocation``.
    public func insertText(
        documentId: String,
        text: String,
        index: Int,
        segmentId: String? = nil,
        endOfSegment: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !text.isEmpty else {
            throw GrahamError.invalidArgument("text must not be empty")
        }
        let insert: DocsInsertTextRequest
        if endOfSegment {
            // Appending needs no index; the destination is the end of the
            // segment (or the body when segmentId is nil).
            insert = DocsInsertTextRequest(
                text: text,
                endOfSegmentLocation: DocsEndOfSegmentLocation(segmentId: segmentId)
            )
        } else {
            // The body-only guard rejects index 0, which lands inside the
            // initial section break the body cannot edit. A named segment
            // starts its content at index 0, so it only needs index >= 0.
            if segmentId == nil {
                guard index >= 1 else {
                    throw GrahamError.invalidArgument(
                        "index must be 1 or greater; the document body starts at index 1")
                }
            } else {
                guard index >= 0 else {
                    throw GrahamError.invalidArgument(
                        "index must be 0 or greater in a segment")
                }
            }
            insert = DocsInsertTextRequest(
                text: text,
                location: DocsLocation(index: index, segmentId: segmentId)
            )
        }
        let request = DocsBatchUpdateRequest.insertText(insert)
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Deletes the content in the half-open range `[startIndex, endIndex)`.
    ///
    /// Both indices are zero-based offsets in UTF-16 code units into the
    /// document (see ``DocsRange``).
    /// - Parameter segmentId: names a header, footer, or footnote segment whose
    ///   content is deleted; when nil, the range refers to the document body. A
    ///   named segment starts its content at index 0, so its minimum
    ///   `startIndex` is 0; the body's minimum stays 1.
    public func deleteContentRange(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // The body's first editable index is 1; a named segment starts at 0.
        let minStart = segmentId == nil ? 1 : 0
        guard startIndex >= minStart else {
            throw GrahamError.invalidArgument(
                segmentId == nil
                    ? "startIndex must be 1 or greater; the document body starts at index 1"
                    : "startIndex must be 0 or greater in a segment")
        }
        guard endIndex > startIndex else {
            throw GrahamError.invalidArgument(
                "endIndex (\(endIndex)) must be greater than startIndex (\(startIndex))")
        }
        let request = DocsBatchUpdateRequest.deleteContentRange(DocsDeleteContentRangeRequest(
            range: DocsRange(startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)
        ))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Replaces every match of `find` with `replace`, returning the number of
    /// occurrences replaced.
    ///
    /// The match is case-insensitive unless `matchCase` is true.
    public func replaceAllText(
        documentId: String,
        find: String,
        replace: String,
        matchCase: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> Int {
        guard !find.isEmpty else {
            throw GrahamError.invalidArgument("the text to find must not be empty")
        }
        let request = DocsBatchUpdateRequest.replaceAllText(DocsReplaceAllTextRequest(
            replaceText: replace,
            containsText: DocsSubstringMatchCriteria(text: find, matchCase: matchCase)
        ))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return response.replies?.first?.replaceAllText?.occurrencesChanged ?? 0
    }
}
