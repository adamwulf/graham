import Foundation

extension DocsClient {
    // MARK: - Structure and images
    //
    // Page breaks and section breaks are body-only in the API (their location's
    // segment id must be empty), so those two methods take no segment and apply
    // the body guard `index >= 1` (index 0 lands inside the initial section
    // break the body cannot edit). Inline images may go in the body, a header,
    // or a footer (not a footnote), so `insertInlineImage` normalizes an empty
    // segment id to the body and uses the shared per-segment index rules (body
    // >= 1, a named segment >= 0), exactly like the text and table inserts.
    // Indices stay zero-based UTF-16, matching the API. Replies are empty for
    // every op except `insertInlineImage`, whose reply carries the new object id.

    /// Inserts a page break plus a newline in the document body.
    ///
    /// The destination is exactly one of an explicit body `index` (a
    /// ``DocsLocation``) or the end of the body (`endOfSegment`). Page breaks are
    /// body-only in the Docs API, so there is no segment option.
    ///
    /// - Parameters:
    ///   - index: the zero-based UTF-16 body index to insert at. Required unless
    ///     `endOfSegment` is set. The body's first editable index is 1 (index 0
    ///     lands inside the initial section break).
    ///   - endOfSegment: append the page break to the end of the body without
    ///     computing an index. Mutually exclusive with `index`; provide exactly
    ///     one.
    public func insertPageBreak(
        documentId: String,
        index: Int? = nil,
        endOfSegment: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // The destination is exactly one of an explicit index or the end of the
        // body: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfSegment, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the body, not both")
        }
        let insert: DocsInsertPageBreakRequest
        if endOfSegment {
            insert = .endOfBody
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the body")
            }
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
            insert = DocsInsertPageBreakRequest(bodyIndex: index)
        }
        let request = DocsBatchUpdateRequest.insertPageBreak(insert)
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Inserts an inline image from a `uri` and returns the batch response plus
    /// the new image's object id (from the reply).
    ///
    /// The `uri` must be publicly fetchable by Google at insertion time
    /// (< 50MB, <= 25 megapixels, PNG/JPEG/GIF); Google fetches it once and
    /// stores a copy. The destination is exactly one of an explicit `index` (a
    /// ``DocsLocation``) or the end of the body or a segment (`endOfSegment`).
    ///
    /// - Parameters:
    ///   - uri: the image URI; must not be empty.
    ///   - index: the zero-based UTF-16 index to insert at. Required unless
    ///     `endOfSegment` is set. The body's first editable index is 1; a named
    ///     segment starts at 0.
    ///   - endOfSegment: append to the end of the body (or the segment named by
    ///     `segmentId`) without computing an index. Mutually exclusive with
    ///     `index`; provide exactly one.
    ///   - segmentId: a header or footer segment (an inline image cannot go in a
    ///     footnote); nil or an empty string targets the body.
    ///   - width / height: the optional display size in points; each must be
    ///     greater than zero when given. Omitting both lets the API size the
    ///     image from its resolution; giving one lets the API compute the other
    public func insertSectionBreak(
        documentId: String,
        sectionType: String,
        index: Int? = nil,
        endOfSegment: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard let type = DocsSectionType(rawValue: sectionType.uppercased()) else {
            throw GrahamError.invalidArgument(
                "unknown section type \"\(sectionType)\"; use CONTINUOUS or NEXT_PAGE")
        }
        // The destination is exactly one of an explicit index or the end of the
        // body: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfSegment, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the body, not both")
        }
        let insert: DocsInsertSectionBreakRequest
        if endOfSegment {
            insert = .endOfBody(sectionType: type)
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the body")
            }
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
            insert = DocsInsertSectionBreakRequest(sectionType: type, bodyIndex: index)
        }
        let request = DocsBatchUpdateRequest.insertSectionBreak(insert)
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    // MARK: - Headers, footers, footnotes
    //
    // A create returns the new segment id from its reply (`headerId` /
    // `footerId` / `footnoteId`) so a follow-up segment-aware write can target
    // it. Headers and footers optionally scope to a section through a body index
    // (a section-break `Location`); that index follows the body guard `>= 1`
    // (index 0 lands inside the initial section break the body cannot edit).
    // Footnote references live in the body, so `createFootnote` is body-only:
    // it takes only a body index or the end of the body, no segment. Indices
    // stay zero-based UTF-16, matching the API. The two delete ops reject an
    // empty id and reply with an empty object.

    /// Creates a header and returns the batch response plus the new header's
    /// segment id (from the reply).
    ///
    /// The header `type` is always `DEFAULT` (the only usable value). First-page
    /// and even-page headers are enabled through `updateDocumentStyle` flags, not
    /// here.
    ///
    /// - Parameters:
    ///   - sectionBreakIndex: an optional zero-based UTF-16 body index at a
    ///     section break, scoping the header to that section. The body's first
    ///     editable index is 1 (index 0 lands inside the initial section break).
    ///     When nil, the header applies to the whole document.
    public func createHeader(
        documentId: String,
        sectionBreakIndex: Int? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, headerId: String?) {
        let sectionBreakLocation = try Self.sectionBreakLocation(from: sectionBreakIndex)
        let request = DocsBatchUpdateRequest.createHeader(
            DocsCreateHeaderRequest(type: .default, sectionBreakLocation: sectionBreakLocation))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, response.replies?.first?.createHeader?.headerId)
    }

    /// Creates a footer and returns the batch response plus the new footer's
    /// segment id (from the reply).
    ///
    /// The footer `type` is always `DEFAULT`. First-page and even-page footers
    /// are enabled through `updateDocumentStyle` flags, not here.
    ///
    /// - Parameter sectionBreakIndex: an optional zero-based UTF-16 body index at
    ///   a section break, scoping the footer to that section (body minimum 1).
    ///   When nil, the footer applies to the whole document.
    public func createFooter(
        documentId: String,
        sectionBreakIndex: Int? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, footerId: String?) {
        let sectionBreakLocation = try Self.sectionBreakLocation(from: sectionBreakIndex)
        let request = DocsBatchUpdateRequest.createFooter(
            DocsCreateFooterRequest(type: .default, sectionBreakLocation: sectionBreakLocation))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, response.replies?.first?.createFooter?.footerId)
    }

    /// Builds the optional section-break body location for a header or footer
    /// create, validating the body index. A nil index means no section scope
    /// (nil location); a provided index must satisfy the body guard `>= 1`.
    private static func sectionBreakLocation(from index: Int?) throws -> DocsLocation? {
        guard let index else { return nil }
        guard index >= 1 else {
            throw GrahamError.invalidArgument(
                "the section-break index must be 1 or greater; the document body starts at index 1")
        }
        return DocsLocation(index: index)
    }

    /// Deletes a header by its segment id.
    ///
    /// - Parameter headerId: the id of the header segment to delete (from a
    ///   `createHeader` reply, or `docs structure`); must not be empty.
    public func deleteHeader(
        documentId: String,
        headerId: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !headerId.isEmpty else {
            throw GrahamError.invalidArgument("the header id must not be empty")
        }
        let request = DocsBatchUpdateRequest.deleteHeader(
            DocsDeleteHeaderRequest(headerId: headerId))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Deletes a footer by its segment id.
    ///
    /// - Parameter footerId: the id of the footer segment to delete (from a
    ///   `createFooter` reply, or `docs structure`); must not be empty.
    public func deleteFooter(
        documentId: String,
        footerId: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !footerId.isEmpty else {
            throw GrahamError.invalidArgument("the footer id must not be empty")
        }
        let request = DocsBatchUpdateRequest.deleteFooter(
            DocsDeleteFooterRequest(footerId: footerId))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Creates a footnote (inserting its reference in the document body) and
    /// returns the batch response plus the new footnote's segment id (from the
    /// reply). When `text` is given, its content is inserted into the new
    /// footnote segment with a second batch update.
    ///
    /// The footnote reference lives in the body, so the destination is exactly
    /// one of an explicit body `index` or the end of the body (`endOfBody`);
    /// there is no segment option.
    ///
    /// - Parameters:
    ///   - index: the zero-based UTF-16 body index to insert the reference at.
    ///     Required unless `endOfBody` is set. The body's first editable index is
    ///     1 (index 0 lands inside the initial section break).
    ///   - endOfBody: insert the reference at the end of the body without
    ///     computing an index. Mutually exclusive with `index`; provide exactly
    ///     one.
    ///   - text: optional footnote text. The created footnote segment begins with
    ///     an auto-inserted space and newline, so the text is inserted at index 1
    ///     of the footnote segment. This needs a **second** `batchUpdate`: the
    ///     footnoteId is only known from the first reply, so the text insert
    ///     cannot ride in the same batch. Must be non-empty when given.
    public func createFootnote(
        documentId: String,
        index: Int? = nil,
        endOfBody: Bool = false,
        text: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, footnoteId: String?) {
        // Validate the text before creating anything, so an empty --text never
        // leaves an orphan footnote behind (the first write would otherwise
        // succeed and only the second fail).
        if let text, text.isEmpty {
            throw GrahamError.invalidArgument("the footnote text must not be empty")
        }
        // The destination is exactly one of an explicit index or the end of the
        // body: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfBody, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the body, not both")
        }
        let create: DocsCreateFootnoteRequest
        if endOfBody {
            create = .endOfBody
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the body")
            }
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
            create = DocsCreateFootnoteRequest(bodyIndex: index)
        }
        let response = try await batchUpdate(
            documentId: documentId,
            requests: [.createFootnote(create)],
            requiredRevisionId: requiredRevisionId)
        let footnoteId = response.replies?.first?.createFootnote?.footnoteId

        if let text {
            // The text goes in a second batch: the footnoteId is only known from
            // the first reply, so it cannot be one batch. The footnote segment's
            // content starts with an auto-inserted space and newline, so the text
            // is inserted at index 1 of the footnote segment.
            guard let footnoteId, !footnoteId.isEmpty else {
                throw GrahamError.invalidArgument(
                    "the footnote was created but Google returned no footnote id, "
                    + "so the text could not be inserted")
            }
            // The second write does not carry the required revision: the first
            // write already advanced the document's revision, so reusing the old
            // required revision would fail the insert.
            _ = try await insertText(
                documentId: documentId, text: text, index: 1, segmentId: footnoteId)
        }
        return (response, footnoteId)
    }
}
