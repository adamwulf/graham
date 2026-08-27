import Foundation

extension DocsClient {
    public func insertInlineImage(
        documentId: String,
        uri: String,
        index: Int? = nil,
        endOfSegment: Bool = false,
        segmentId: String? = nil,
        width: Double? = nil,
        height: Double? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, objectId: String?) {
        guard !uri.isEmpty else {
            throw GrahamError.invalidArgument("the image URI must not be empty")
        }
        // The destination is exactly one of an explicit index or the end of the
        // segment: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfSegment, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the segment, not both")
        }
        try Self.validateStylePositive(width, label: "image width")
        try Self.validateStylePositive(height, label: "image height")
        // A size is sent only when a width or height is given; an omitted size
        // lets the API size the image from its resolution.
        var objectSize: DocsSize?
        if width != nil || height != nil {
            objectSize = DocsSize(
                height: height.map { DocsDimension(magnitude: $0, unit: .pt) },
                width: width.map { DocsDimension(magnitude: $0, unit: .pt) })
        }
        // The Docs API reads an empty segment id as the document body, so
        // normalize "" to nil before choosing the guard and building the target.
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        let insert: DocsInsertInlineImageRequest
        if endOfSegment {
            insert = DocsInsertInlineImageRequest(
                uri: uri,
                endOfSegmentLocation: DocsEndOfSegmentLocation(segmentId: segmentId),
                objectSize: objectSize)
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the segment")
            }
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
            insert = DocsInsertInlineImageRequest(
                uri: uri,
                location: DocsLocation(index: index, segmentId: segmentId),
                objectSize: objectSize)
        }
        let request = DocsBatchUpdateRequest.insertInlineImage(insert)
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        let objectId = response.replies?.first?.insertInlineImage?.objectId
        return (response, objectId)
    }

    /// Replaces an existing image, in place, with a new image from `uri`.
    ///
    /// The only replace method the API defines is
    /// ``DocsImageReplaceMethod/centerCrop`` (scale-and-center, cropping to fill
    /// the original bounds), so the client always sends it. The new `uri` follows
    /// the same fetch rules as ``insertInlineImage(documentId:uri:index:endOfSegment:segmentId:width:height:requiredRevisionId:)``.
    ///
    /// - Parameters:
    ///   - imageObjectId: the id of the existing image to replace; must not be
    ///     empty.
    ///   - uri: the new image URI; must not be empty.
    public func replaceImage(
        documentId: String,
        imageObjectId: String,
        uri: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !imageObjectId.isEmpty else {
            throw GrahamError.invalidArgument("the image object id must not be empty")
        }
        guard !uri.isEmpty else {
            throw GrahamError.invalidArgument("the image URI must not be empty")
        }
        let request = DocsBatchUpdateRequest.replaceImage(DocsReplaceImageRequest(
            imageObjectId: imageObjectId, uri: uri, imageReplaceMethod: .centerCrop))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Inserts a section break (with a preceding newline) in the document body.
    ///
    /// The destination is exactly one of an explicit body `index` (a
    /// ``DocsLocation``) or the end of the body (`endOfSegment`). Section breaks
    /// are body-only in the Docs API, so there is no segment option.
    ///
    /// - Parameters:
    ///   - sectionType: the section-type spelling (case-insensitive), `CONTINUOUS`
    ///     or `NEXT_PAGE`. A value outside that set is rejected before any request
    ///     goes out.
    ///   - index: the zero-based UTF-16 body index to insert at. Required unless
    ///     `endOfSegment` is set. The body's first editable index is 1 (index 0
    ///     lands inside the initial section break).
    ///   - endOfSegment: append the section break to the end of the body without
    ///     computing an index. Mutually exclusive with `index`; provide exactly
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
                try writeRefusingSymlink(data, to: fileURL)
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
