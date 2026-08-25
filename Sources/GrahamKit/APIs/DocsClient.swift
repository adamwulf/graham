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

    // MARK: - Writes

    /// Sends one `documents.batchUpdate` call with `requests`, in order.
    ///
    /// This is the shared Docs batch-write path. High-level operations build
    /// typed ``DocsBatchUpdateRequest`` values and go through this method.
    public func batchUpdate(
        documentId: String,
        requests: [DocsBatchUpdateRequest]
    ) async throws -> DocsBatchUpdateResponse {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/documents/\(GoogleURL.escapePathComponent(documentId)):batchUpdate"
        )
        return try await api.sendJSON(
            DocsBatchUpdateResponse.self,
            method: "POST",
            url: url,
            body: DocsBatchUpdateRequestBody(requests: requests)
        )
    }

    /// Inserts `text` at a zero-based document index.
    ///
    /// `index` is a zero-based offset in **UTF-16 code units** into the
    /// document, exactly as the Docs API defines it (see ``DocsLocation``). The
    /// API index model is kept for Docs text operations; graham does not
    /// translate it to a one-based position the way it does for slides and
    /// tables.
    public func insertText(
        documentId: String,
        text: String,
        index: Int
    ) async throws -> DocsBatchUpdateResponse {
        guard !text.isEmpty else {
            throw GrahamError.invalidArgument("text must not be empty")
        }
        guard index >= 1 else {
            throw GrahamError.invalidArgument(
                "index must be 1 or greater; the document body starts at index 1")
        }
        let request = DocsBatchUpdateRequest.insertText(DocsInsertTextRequest(
            text: text,
            location: DocsLocation(index: index)
        ))
        return try await batchUpdate(documentId: documentId, requests: [request])
    }

    /// Deletes the content in the half-open range `[startIndex, endIndex)`.
    ///
    /// Both indices are zero-based offsets in UTF-16 code units into the
    /// document (see ``DocsRange``).
    public func deleteContentRange(
        documentId: String,
        startIndex: Int,
        endIndex: Int
    ) async throws -> DocsBatchUpdateResponse {
        guard startIndex >= 1 else {
            throw GrahamError.invalidArgument(
                "startIndex must be 1 or greater; the document body starts at index 1")
        }
        guard endIndex > startIndex else {
            throw GrahamError.invalidArgument(
                "endIndex (\(endIndex)) must be greater than startIndex (\(startIndex))")
        }
        let request = DocsBatchUpdateRequest.deleteContentRange(DocsDeleteContentRangeRequest(
            range: DocsRange(startIndex: startIndex, endIndex: endIndex)
        ))
        return try await batchUpdate(documentId: documentId, requests: [request])
    }

    /// Replaces every match of `find` with `replace`, returning the number of
    /// occurrences replaced.
    ///
    /// The match is case-insensitive unless `matchCase` is true.
    public func replaceAllText(
        documentId: String,
        find: String,
        replace: String,
        matchCase: Bool = false
    ) async throws -> Int {
        guard !find.isEmpty else {
            throw GrahamError.invalidArgument("the text to find must not be empty")
        }
        let request = DocsBatchUpdateRequest.replaceAllText(DocsReplaceAllTextRequest(
            replaceText: replace,
            containsText: DocsSubstringMatchCriteria(text: find, matchCase: matchCase)
        ))
        let response = try await batchUpdate(documentId: documentId, requests: [request])
        return response.replies?.first?.replaceAllText?.occurrencesChanged ?? 0
    }
}
