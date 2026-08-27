import Foundation

/// The high-level client for the Docs v1 API.
public struct DocsClient: Sendable {
    public static let baseURL = "https://docs.googleapis.com/v1"

    let api: GoogleAPI
    let downloadTransport: any HTTPTransport

    /// Builds the client.
    ///
    /// - Parameters:
    ///   - api: The low-level executor for Docs API calls (with the OAuth
    ///     bearer, retry, and backoff).
    ///   - downloadTransport: A separate transport for image downloads. It is
    ///     deliberately not the ``GoogleAPI`` path: an image `contentUri` is a
    ///     pre-authorized, short-lived URL on a Google user-content host, not on
    ///     the Docs API host, so a download must **not** attach the Docs API
    ///     bearer token — doing so would leak the token to a different host and
    ///     is unnecessary. Tests inject a stub here; production uses a plain
    ///     `URLSession`. This mirrors the Slides ``SlidesClient`` seam.
    public init(api: GoogleAPI, downloadTransport: any HTTPTransport = URLSessionTransport()) {
        self.api = api
        self.downloadTransport = downloadTransport
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
}
