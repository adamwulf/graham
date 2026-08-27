import Foundation

extension DocsClient {
    // MARK: - Named ranges and document style
    //
    // A named range labels a zero-based UTF-16 range so a later write can fill it
    // (the template-filling primitive). `createNamedRange` reuses the shared
    // `makeStyleRange` range rules (an empty segmentId normalizes to the body,
    // the body's first editable index is 1, a named segment starts at 0, and
    // endIndex must be greater than startIndex) and returns the new id from its
    // reply. The delete and replace ops select the target by id or by name — the
    // two are mutually exclusive, so each method requires exactly one non-empty
    // selector and dispatches to the matching typed init. `updateDocumentStyle`
    // builds a deterministic `fields` mask (one path per provided parameter, in a
    // fixed documented order) and requires at least one parameter, the same
    // discipline as the text, paragraph, and table styling above.

    /// Creates a named range over a zero-based UTF-16 range and returns the batch
    /// response plus the new named-range id (from the reply).
    ///
    /// A named range labels a span so a later ``replaceNamedRangeContent(documentId:text:namedRangeId:name:requiredRevisionId:)``
    /// can fill it — the template-filling primitive. Names need not be unique.
    ///
    /// - Parameters:
    ///   - name: the range name; must be 1 to 256 UTF-16 code units.
    ///   - startIndex / endIndex: the zero-based, half-open UTF-16 range to name;
    ///     `endIndex` must be greater than `startIndex`.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body (the body's first editable index is 1; a named
    ///     segment starts at 0).
    public func createNamedRange(
        documentId: String,
        name: String,
        startIndex: Int,
        endIndex: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, namedRangeId: String?) {
        // The API measures the name in UTF-16 code units, so validate that count
        // (not the Character count); this also rejects an empty name.
        let length = name.utf16.count
        guard (1...256).contains(length) else {
            throw GrahamError.invalidArgument(
                "the named range name must be 1 to 256 UTF-16 code units, got \(length)")
        }
        let range = try Self.makeStyleRange(
            startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)
        let request = DocsBatchUpdateRequest.createNamedRange(
            DocsCreateNamedRangeRequest(name: name, range: range))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, response.replies?.first?.createNamedRange?.namedRangeId)
    }

    /// Deletes a named range, selecting the target by exactly one of a
    /// `namedRangeId` (that one range) or a `name` (every range sharing the name).
    ///
    /// The two selectors are mutually exclusive: provide exactly one, and it must
    /// be non-empty. Providing both, or neither, or an empty value, is rejected
    /// before any request goes out. Deleting by a name that matches nothing is a
    /// server-side no-op, not a client error.
    public func deleteNamedRange(
        documentId: String,
        namedRangeId: String? = nil,
        name: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let delete = try Self.deleteNamedRangeRequest(namedRangeId: namedRangeId, name: name)
        return try await batchUpdate(
            documentId: documentId, requests: [.deleteNamedRange(delete)],
            requiredRevisionId: requiredRevisionId)
    }

    /// Builds a ``DocsDeleteNamedRangeRequest`` from exactly one non-empty
    /// selector, dispatching to the matching typed init. The switch makes the
    /// one-of explicit: both, neither, and empty selectors each throw.
    private static func deleteNamedRangeRequest(
        namedRangeId: String?, name: String?
    ) throws -> DocsDeleteNamedRangeRequest {
        switch (namedRangeId, name) {
        case let (id?, nil):
            guard !id.isEmpty else {
                throw GrahamError.invalidArgument("the named range id must not be empty")
            }
            return DocsDeleteNamedRangeRequest(namedRangeId: id)
        case let (nil, name?):
            guard !name.isEmpty else {
                throw GrahamError.invalidArgument("the named range name must not be empty")
            }
            return DocsDeleteNamedRangeRequest(name: name)
        case (nil, nil):
            throw GrahamError.invalidArgument(
                "provide either a named range id or a name to delete")
        case (.some, .some):
            throw GrahamError.invalidArgument(
                "provide either a named range id or a name, not both")
        }
    }

    /// Replaces the content of a named range with `text`, selecting the target by
    /// exactly one of a `namedRangeId` (that one range) or a `name` (every range
    /// sharing the name).
    ///
    /// This is the template-filling primitive: `text` replaces the range's
    /// content, and an empty `text` clears it (empty is allowed). A discontinuous
    /// named range replaces only its first subrange. The two selectors are
    /// mutually exclusive: provide exactly one, and it must be non-empty.
    /// Providing both, or neither, or an empty selector, is rejected before any
    /// request goes out.
    public func replaceNamedRangeContent(
        documentId: String,
        text: String,
        namedRangeId: String? = nil,
        name: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let replace = try Self.replaceNamedRangeContentRequest(
            namedRangeId: namedRangeId, name: name, text: text)
        return try await batchUpdate(
            documentId: documentId, requests: [.replaceNamedRangeContent(replace)],
            requiredRevisionId: requiredRevisionId)
    }

    /// Builds a ``DocsReplaceNamedRangeContentRequest`` from exactly one non-empty
    /// selector, dispatching to the matching typed init. `text` is not validated
    /// (an empty replacement clears the range). The switch makes the one-of
    /// explicit: both, neither, and empty selectors each throw.
    private static func replaceNamedRangeContentRequest(
        namedRangeId: String?, name: String?, text: String
    ) throws -> DocsReplaceNamedRangeContentRequest {
        switch (namedRangeId, name) {
        case let (id?, nil):
            guard !id.isEmpty else {
                throw GrahamError.invalidArgument("the named range id must not be empty")
            }
            return DocsReplaceNamedRangeContentRequest(namedRangeId: id, text: text)
        case let (nil, name?):
            guard !name.isEmpty else {
                throw GrahamError.invalidArgument("the named range name must not be empty")
            }
            return DocsReplaceNamedRangeContentRequest(namedRangeName: name, text: text)
        case (nil, nil):
            throw GrahamError.invalidArgument(
                "provide either a named range id or a name to fill")
        case (.some, .some):
            throw GrahamError.invalidArgument(
                "provide either a named range id or a name, not both")
        }
    }
}
