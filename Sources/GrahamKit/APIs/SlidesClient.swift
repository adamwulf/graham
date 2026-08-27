import Foundation

/// A link target for a text run, as accepted by
/// ``SlidesClient/styleText(presentationId:objectId:from:to:row:column:bold:italic:underline:strikethrough:smallCaps:color:background:transparentBackground:fontFamily:fontWeight:fontSize:baseline:link:clearLink:)``.
///
/// This is the high-level input the CLI passes; the client translates it into
/// the wire ``Link`` one-of. A ``slide`` position is ONE-based, matching every
/// other slide position graham prints, and is converted to the API's
/// zero-based `slideIndex`.
public enum TextLinkTarget: Sendable, Equatable {
    /// A link to a web page.
    case url(String)
    /// A link to a slide by its one-based position.
    case slide(position: Int)
    /// A link to a slide by its object id.
    case page(objectId: String)
    /// A link to a slide by relation, for example the next slide.
    case relative(RelativeSlideLink)
}

/// The high-level client for the Slides v1 API.
public struct SlidesClient: Sendable {
    public static let baseURL = "https://slides.googleapis.com/v1"

    let api: GoogleAPI
    let downloadTransport: any HTTPTransport

    /// Builds the client.
    ///
    /// - Parameters:
    ///   - api: The low-level executor for Slides API calls (with the OAuth
    ///     bearer, retry, and backoff).
    ///   - downloadTransport: A separate transport for image downloads. It is
    ///     deliberately not the ``GoogleAPI`` path: an image ``contentUrl`` is a
    ///     pre-authorized, short-lived URL on a Google user-content host, not on
    ///     the Slides API host, so a download must **not** attach the Slides API
    ///     bearer token — doing so would leak the token to a different host and
    ///     is unnecessary. Tests inject a stub here; production uses a plain
    ///     `URLSession`.
    public init(api: GoogleAPI, downloadTransport: any HTTPTransport = URLSessionTransport()) {
        self.api = api
        self.downloadTransport = downloadTransport
    }
    // MARK: - Batch update (the shared write path)

    /// Sends one `presentations.batchUpdate` call with `requests`, in order.
    ///
    /// This is the one write path for Slides. Every high-level write method
    /// builds typed ``SlidesBatchUpdateRequest`` values and goes through here,
    /// so the endpoint, the escaped path, and the response decoding live in
    /// exactly one place.
    public func batchUpdate(
        presentationId: String,
        requests: [SlidesBatchUpdateRequest]
    ) async throws -> SlidesBatchUpdateResponse {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/presentations/\(GoogleURL.escapePathComponent(presentationId)):batchUpdate"
        )
        let body = SlidesBatchUpdateRequestBody(requests: requests)
        return try await api.sendJSON(SlidesBatchUpdateResponse.self, method: "POST", url: url, body: body)
    }
}
