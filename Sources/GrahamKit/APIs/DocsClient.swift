import Foundation

/// The high-level client for the Docs v1 API.
public struct DocsClient: Sendable {
    public static let baseURL = "https://docs.googleapis.com/v1"

    private let api: GoogleAPI
    private let downloadTransport: any HTTPTransport

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

    /// Gets one document, with its body content.
    public func document(id: String) async throws -> Document {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/documents/\(GoogleURL.escapePathComponent(id))"
        )
        return try await api.getJSON(Document.self, from: url)
    }

    /// Creates a new, blank document from a `title` via `documents.create`,
    /// returning the created ``Document`` (whose `documentId` is the value the
    /// `docs create` command prints). The new document's body is empty until a
    /// later ``batchUpdate(documentId:requests:requiredRevisionId:)`` fills it.
    ///
    /// The title is carried in a JSON request body, not in the URL, so it is
    /// encoded safely no matter what characters it holds.
    public func create(title: String) async throws -> Document {
        let url = try GoogleURL.build("\(Self.baseURL)/documents")
        return try await api.sendJSON(
            Document.self,
            method: "POST",
            url: url,
            body: DocsCreateRequest(title: title)
        )
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

    /// Inserts `text` at a zero-based document index.
    ///
    /// `index` is a zero-based offset in **UTF-16 code units** into the
    /// document, exactly as the Docs API defines it (see ``DocsLocation``). The
    /// API index model is kept for Docs text operations; graham does not
    /// translate it to a one-based position the way it does for slides and
    /// tables.
    /// - Parameters:
    ///   - segmentId: names a header, footer, or footnote segment to insert
    ///     into; when nil or empty, the insert targets the document body. A
    ///     named segment starts its content at index 0, so the body-only
    ///     `index >= 1` guard does not apply to it.
    ///   - endOfSegment: append to the end of the segment (or the body, when
    ///     `segmentId` is nil or empty) without computing an index. `index` is
    ///     ignored in this mode, and no index guard applies. This encodes an
    ///     ``DocsEndOfSegmentLocation`` instead of a ``DocsLocation``.
    public func insertText(
        documentId: String,
        text: String,
        index: Int,
        segmentId: String? = nil,
        endOfSegment: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !text.isEmpty else {
            throw GrahamError.invalidArgument("text must not be empty")
        }
        // The Docs API reads an empty segment id as the document body, so
        // normalize "" to nil before choosing the guard and building the
        // target: an empty or nil segmentId uses the body guard and encodes no
        // segmentId; only a non-empty id is treated as a named segment.
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        let insert: DocsInsertTextRequest
        if endOfSegment {
            // Appending needs no index; the destination is the end of the
            // segment (or the body when segmentId is nil).
            insert = DocsInsertTextRequest(
                text: text,
                endOfSegmentLocation: DocsEndOfSegmentLocation(segmentId: segmentId)
            )
        } else {
            // The body-only guard rejects index 0, which lands inside the
            // initial section break the body cannot edit. A named segment
            // starts its content at index 0, so it only needs index >= 0.
            if segmentId == nil {
                guard index >= 1 else {
                    throw GrahamError.invalidArgument(
                        "index must be 1 or greater; the document body starts at index 1")
                }
            } else {
                guard index >= 0 else {
                    throw GrahamError.invalidArgument(
                        "index must be 0 or greater in a segment")
                }
            }
            insert = DocsInsertTextRequest(
                text: text,
                location: DocsLocation(index: index, segmentId: segmentId)
            )
        }
        let request = DocsBatchUpdateRequest.insertText(insert)
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Deletes the content in the half-open range `[startIndex, endIndex)`.
    ///
    /// Both indices are zero-based offsets in UTF-16 code units into the
    /// document (see ``DocsRange``).
    /// - Parameter segmentId: names a header, footer, or footnote segment whose
    ///   content is deleted; when nil or empty, the range refers to the document
    ///   body. A named segment starts its content at index 0, so its minimum
    ///   `startIndex` is 0; the body's minimum stays 1.
    public func deleteContentRange(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // The Docs API reads an empty segment id as the document body, so
        // normalize "" to nil before choosing the guard and building the range:
        // an empty or nil segmentId uses the body guard and encodes no
        // segmentId; only a non-empty id is treated as a named segment.
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        // The body's first editable index is 1; a named segment starts at 0.
        let minStart = segmentId == nil ? 1 : 0
        guard startIndex >= minStart else {
            throw GrahamError.invalidArgument(
                segmentId == nil
                    ? "startIndex must be 1 or greater; the document body starts at index 1"
                    : "startIndex must be 0 or greater in a segment")
        }
        guard endIndex > startIndex else {
            throw GrahamError.invalidArgument(
                "endIndex (\(endIndex)) must be greater than startIndex (\(startIndex))")
        }
        let request = DocsBatchUpdateRequest.deleteContentRange(DocsDeleteContentRangeRequest(
            range: DocsRange(startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)
        ))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Replaces every match of `find` with `replace`, returning the number of
    /// occurrences replaced.
    ///
    /// The match is case-insensitive unless `matchCase` is true.
    public func replaceAllText(
        documentId: String,
        find: String,
        replace: String,
        matchCase: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> Int {
        guard !find.isEmpty else {
            throw GrahamError.invalidArgument("the text to find must not be empty")
        }
        let request = DocsBatchUpdateRequest.replaceAllText(DocsReplaceAllTextRequest(
            replaceText: replace,
            containsText: DocsSubstringMatchCriteria(text: find, matchCase: matchCase)
        ))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return response.replies?.first?.replaceAllText?.occurrencesChanged ?? 0
    }

    // MARK: - Image download

    /// Downloads the bytes at an image `contentUri`.
    ///
    /// The request is a plain GET with no `Authorization` header. A Docs
    /// `ImageProperties.contentUri` is short-lived and pre-authorized; the URI
    /// itself carries the authorization, and it points at a Google user-content
    /// host rather than the Docs API host. Attaching the API OAuth bearer would
    /// therefore both leak the token to a third-party host and be redundant, so
    /// the download bypasses ``GoogleAPI`` and goes straight through the
    /// injected transport — exactly like the Slides `Image.contentUrl` seam.
    public func downloadImage(from contentUri: String) async throws -> Data {
        guard let url = URL(string: contentUri), url.scheme != nil else {
            throw GrahamError.invalidURL(contentUri)
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
    /// ``DocImageFile``). A row with no content URI is skipped, and a fetch or
    /// write that fails is recorded and does not stop the rest — so one bad
    /// image never loses the others. The returned results are in the same order
    /// as `rows`, one per row. This mirrors ``SlidesClient/downloadImages(_:to:)``.
    public func downloadImages(
        _ rows: [DocImageRow],
        to directory: URL
    ) async throws -> [DocImageDownloadResult] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.standardizedFileURL

        var results: [DocImageDownloadResult] = []
        var sequence = 0
        for row in rows {
            guard let contentUri = row.contentUri, !contentUri.isEmpty else {
                results.append(DocImageDownloadResult(
                    objectId: row.objectId,
                    origin: row.origin,
                    contentUri: row.contentUri,
                    outcome: .skipped(reason: "no content URI")
                ))
                continue
            }
            sequence += 1
            do {
                let data = try await downloadImage(from: contentUri)
                let filename = DocImageFile.filename(
                    sequence: sequence,
                    origin: row.origin,
                    objectId: row.objectId,
                    fileExtension: DocImageFile.fileExtension(forBytes: data)
                )
                let fileURL = directory.appendingPathComponent(filename)
                // Defense in depth: the name is already sanitized, but confirm
                // the resolved file still sits directly inside the directory.
                guard fileURL.deletingLastPathComponent().standardizedFileURL == target else {
                    results.append(DocImageDownloadResult(
                        objectId: row.objectId,
                        origin: row.origin,
                        contentUri: contentUri,
                        outcome: .failed(reason: "unsafe file path for \(filename)")
                    ))
                    continue
                }
                try data.write(to: fileURL)
                results.append(DocImageDownloadResult(
                    objectId: row.objectId,
                    origin: row.origin,
                    contentUri: contentUri,
                    outcome: .downloaded(filename: filename, byteCount: data.count)
                ))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                results.append(DocImageDownloadResult(
                    objectId: row.objectId,
                    origin: row.origin,
                    contentUri: contentUri,
                    outcome: .failed(reason: reason)
                ))
            }
        }
        return results
    }
}
