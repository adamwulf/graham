import Foundation

extension SlidesClient {
    /// Gets one presentation, with its slides.
    ///
    /// - Parameters:
    ///   - id: The presentation id.
    ///   - fields: An optional field mask, for example `slides.objectId`, so a
    ///     caller that needs only the slide order does not pull the full deck.
    ///     `nil` returns every field.
    public func presentation(id: String, fields: String? = nil) async throws -> Presentation {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/presentations/\(GoogleURL.escapePathComponent(id))",
            query: [("fields", fields)]
        )
        return try await api.getJSON(Presentation.self, from: url)
    }
}
