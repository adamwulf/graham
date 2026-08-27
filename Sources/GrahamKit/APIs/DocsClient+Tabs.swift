import Foundation

extension DocsClient {
    // MARK: - Document tabs

    /// Adds a document tab and returns the batch response plus the new tab's
    /// server-assigned id (from the reply).
    ///
    /// `title`, `parentTabId` (nest under a tab), and `iconEmoji` are optional;
    /// `position` is the one-based tab position the CLI uses, translated to the
    /// API's zero-based `index` here (a nil position appends). The tab id and
    /// nesting level are assigned by the server.
    public func addDocumentTab(
        documentId: String,
        title: String? = nil,
        position: Int? = nil,
        parentTabId: String? = nil,
        iconEmoji: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, tabId: String?) {
        var apiIndex: Int?
        if let position {
            guard position >= 1 else {
                throw GrahamError.invalidArgument(
                    "the tab position must be 1 or greater, got \(position)")
            }
            apiIndex = position - 1
        }
        let properties = DocsTabProperties(
            title: title, index: apiIndex, iconEmoji: iconEmoji, parentTabId: parentTabId)
        let request = DocsBatchUpdateRequest.addDocumentTab(
            DocsAddDocumentTabRequest(tabProperties: properties))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, response.replies?.first?.addDocumentTab?.tabProperties?.tabId)
    }

    /// Deletes the tab `tabId` and its child tabs.
    public func deleteTab(
        documentId: String,
        tabId: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !tabId.isEmpty else {
            throw GrahamError.invalidArgument("a tab id is required to delete a tab")
        }
        let request = DocsBatchUpdateRequest.deleteTab(DocsDeleteTabRequest(tabId: tabId))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Renames or moves the tab `tabId`.
    ///
    /// `title` renames it, `position` (one-based, translated to the API's
    /// zero-based `index`) moves it, `parentTabId` re-nests it, and `iconEmoji`
    /// changes its icon. The `fields` mask is emitted in the fixed order `title`,
    /// `index`, `parentTabId`, `iconEmoji`; `tabId` is the selector and is never
    /// masked. At least one change is required.
    public func updateDocumentTabProperties(
        documentId: String,
        tabId: String,
        title: String? = nil,
        position: Int? = nil,
        parentTabId: String? = nil,
        iconEmoji: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !tabId.isEmpty else {
            throw GrahamError.invalidArgument("a tab id is required to update a tab")
        }
        var apiIndex: Int?
        if let position {
            guard position >= 1 else {
                throw GrahamError.invalidArgument(
                    "the tab position must be 1 or greater, got \(position)")
            }
            apiIndex = position - 1
        }
        var mask: [String] = []
        if title != nil { mask.append("title") }
        if apiIndex != nil { mask.append("index") }
        if parentTabId != nil { mask.append("parentTabId") }
        if iconEmoji != nil { mask.append("iconEmoji") }
        let fields = try GrahamValidation.requireFieldMask(
            mask, "updating a tab requires at least one property")
        let properties = DocsTabProperties(
            tabId: tabId, title: title, index: apiIndex,
            iconEmoji: iconEmoji, parentTabId: parentTabId)
        let request = DocsBatchUpdateRequest.updateDocumentTabProperties(
            DocsUpdateDocumentTabPropertiesRequest(
                tabProperties: properties, fields: fields))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }
}
