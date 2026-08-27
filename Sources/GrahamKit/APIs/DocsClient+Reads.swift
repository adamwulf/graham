import Foundation

extension DocsClient {
    /// Gets one document, with its body content.
    ///
    /// When `includeTabsContent` is true, the response populates `Document.tabs`
    /// (the per-tab bodies) instead of the legacy top-level `body`, so a tabbed
    /// document can be read tab by tab. When false (the default), the API returns
    /// the classic single-body shape.
    public func document(id: String, includeTabsContent: Bool = false) async throws -> Document {
        let query: [(String, String?)] =
            includeTabsContent ? [("includeTabsContent", "true")] : []
        let url = try GoogleURL.build(
            "\(Self.baseURL)/documents/\(GoogleURL.escapePathComponent(id))",
            query: query
        )
        return try await api.getJSON(Document.self, from: url)
    }
}
