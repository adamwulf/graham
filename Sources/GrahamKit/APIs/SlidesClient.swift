import Foundation

/// The high-level client for the Slides v1 API.
public struct SlidesClient: Sendable {
    public static let baseURL = "https://slides.googleapis.com/v1"

    private let api: GoogleAPI

    public init(api: GoogleAPI) {
        self.api = api
    }

    /// Gets one presentation, with its slides.
    public func presentation(id: String) async throws -> Presentation {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/presentations/\(GoogleURL.escapePathComponent(id))"
        )
        return try await api.getJSON(Presentation.self, from: url)
    }
}
