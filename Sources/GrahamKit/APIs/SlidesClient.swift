import Foundation

/// The high-level client for the Slides v1 API.
public struct SlidesClient: Sendable {
    public static let baseURL = "https://slides.googleapis.com/v1"

    private let api: GoogleAPI
    private let downloadTransport: any HTTPTransport

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

    /// Gets one presentation, with its slides.
    public func presentation(id: String) async throws -> Presentation {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/presentations/\(GoogleURL.escapePathComponent(id))"
        )
        return try await api.getJSON(Presentation.self, from: url)
    }

    // MARK: - Image download

    /// Downloads the bytes at an image `contentUrl`.
    ///
    /// The request is a plain GET with no `Authorization` header. A Slides
    /// `Image.contentUrl` has a ~30-minute lifetime and is "tagged with the
    /// account of the requester"; the URL itself carries the authorization, and
    /// it points at a Google user-content host rather than the Slides API host.
    /// Attaching the API OAuth bearer would therefore both leak the token to a
    /// third-party host and be redundant, so the download bypasses
    /// ``GoogleAPI`` and goes straight through the injected transport.
    ///
    /// See the Slides `Image.contentUrl` reference:
    /// https://developers.google.com/slides/api/reference/rest/v1/presentations.pages
    public func downloadImage(from contentUrl: String) async throws -> Data {
        guard let url = URL(string: contentUrl), url.scheme != nil else {
            throw GrahamError.invalidURL(contentUrl)
        }
        let response = try await downloadTransport.send(HTTPRequest(method: "GET", url: url))
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: response.body, encoding: .utf8) ?? ""
            throw GrahamError.httpError(statusCode: response.statusCode, body: String(text.prefix(500)))
        }
        return response.body
    }

    /// Downloads every image in `rows` into `directory`.
    ///
    /// The directory is created if it does not exist. Each image is fetched in
    /// order and written under a deterministic, collision-free name (see
    /// ``SlideImageFile``). A row with no content URL is skipped, and a fetch or
    /// write that fails is recorded and does not stop the rest — so one bad
    /// image never loses the others. The returned results are in the same order
    /// as `rows`, one per row.
    public func downloadImages(
        _ rows: [SlideImageRow],
        to directory: URL
    ) async throws -> [SlideImageDownloadResult] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.standardizedFileURL

        var results: [SlideImageDownloadResult] = []
        var sequence = 0
        for row in rows {
            guard let contentUrl = row.contentUrl, !contentUrl.isEmpty else {
                results.append(SlideImageDownloadResult(
                    objectId: row.objectId,
                    slideIndex: row.slideIndex,
                    contentUrl: row.contentUrl,
                    outcome: .skipped(reason: "no content URL")
                ))
                continue
            }
            sequence += 1
            do {
                let data = try await downloadImage(from: contentUrl)
                let filename = SlideImageFile.filename(
                    sequence: sequence,
                    slideIndex: row.slideIndex,
                    objectId: row.objectId,
                    fileExtension: SlideImageFile.fileExtension(forBytes: data)
                )
                let fileURL = directory.appendingPathComponent(filename)
                // Defense in depth: the name is already sanitized, but confirm
                // the resolved file still sits directly inside the directory.
                guard fileURL.deletingLastPathComponent().standardizedFileURL == target else {
                    results.append(SlideImageDownloadResult(
                        objectId: row.objectId,
                        slideIndex: row.slideIndex,
                        contentUrl: contentUrl,
                        outcome: .failed(reason: "unsafe file path for \(filename)")
                    ))
                    continue
                }
                try data.write(to: fileURL)
                results.append(SlideImageDownloadResult(
                    objectId: row.objectId,
                    slideIndex: row.slideIndex,
                    contentUrl: contentUrl,
                    outcome: .downloaded(filename: filename, byteCount: data.count)
                ))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                results.append(SlideImageDownloadResult(
                    objectId: row.objectId,
                    slideIndex: row.slideIndex,
                    contentUrl: contentUrl,
                    outcome: .failed(reason: reason)
                ))
            }
        }
        return results
    }
}
