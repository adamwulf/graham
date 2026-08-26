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

    // MARK: - Styling
    //
    // Both style methods build a deterministic `fields` mask: one path per
    // provided parameter, in a fixed documented order, and require at least one
    // parameter or they throw ``GrahamError/invalidArgument(_:)`` and send
    // nothing. The mask paths are relative to the style root, so they are bare
    // field names. The range is zero-based UTF-16, with an empty `segmentId`
    // normalized to the body exactly like the text edits above.

    /// Normalizes a style range: an empty `segmentId` means the body (encoded
    /// with no segment id), and `endIndex` must be greater than `startIndex`.
    private static func makeStyleRange(
        startIndex: Int, endIndex: Int, segmentId: String?
    ) throws -> DocsRange {
        // The Docs API reads an empty segment id as the document body, so
        // normalize "" to nil: an empty or nil segmentId encodes no segmentId.
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        guard endIndex > startIndex else {
            throw GrahamError.invalidArgument(
                "endIndex (\(endIndex)) must be greater than startIndex (\(startIndex))")
        }
        return DocsRange(startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)
    }

    /// Styles a range of text: bold, italic, underline, strikethrough, colors,
    /// font, size, baseline offset, and link.
    ///
    /// - Parameters:
    ///   - startIndex / endIndex: the zero-based, half-open UTF-16 range to
    ///     style; `endIndex` must be greater than `startIndex`.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///   - bold / italic / underline / strikethrough: optional toggles; nil
    ///     leaves each unchanged.
    ///   - foregroundColor / backgroundColor: solid colors, already parsed to
    ///     ``DocsOptionalColor`` (the CLI parses the hex through
    ///     ``DocsOptionalColor/parse(_:)``).
    ///   - fontSize: the point size; must be greater than zero.
    ///   - fontFamily / fontWeight: the font. A `fontWeight` must be a multiple
    ///     of 100 within 100...900 and requires a `fontFamily`; both go into the
    ///     `weightedFontFamily` (Docs `TextStyle` has no bare family field).
    ///   - baselineOffset: superscript, subscript, or none.
    ///   - linkURL: sets a web link on the run.
    ///
    /// The `fields` mask is emitted in the fixed order `bold`, `italic`,
    /// `underline`, `strikethrough`, `foregroundColor`, `backgroundColor`,
    /// `fontSize`, `weightedFontFamily`, `baselineOffset`, `link`. At least one
    /// style parameter is required.
    public func styleText(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        segmentId: String? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        foregroundColor: DocsOptionalColor? = nil,
        backgroundColor: DocsOptionalColor? = nil,
        fontSize: Double? = nil,
        fontFamily: String? = nil,
        fontWeight: Int? = nil,
        baselineOffset: DocsBaselineOffset? = nil,
        linkURL: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.makeStyleRange(
            startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)

        // Weighted font family: a weight is a multiple of 100 in 100...900 and
        // requires a family.
        var weightedFontFamily: DocsWeightedFontFamily?
        if let fontFamily {
            if let fontWeight {
                guard (100...900).contains(fontWeight), fontWeight % 100 == 0 else {
                    throw GrahamError.invalidArgument(
                        "font weight must be a multiple of 100 within 100 and 900, got \(fontWeight)")
                }
            }
            weightedFontFamily = DocsWeightedFontFamily(fontFamily: fontFamily, weight: fontWeight)
        } else if fontWeight != nil {
            throw GrahamError.invalidArgument("a font weight requires a font family")
        }

        if let fontSize {
            guard fontSize > 0 else {
                throw GrahamError.invalidArgument(
                    "font size must be greater than zero, got \(fontSize)")
            }
        }

        let link = linkURL.map { DocsLink(url: $0) }

        var mask: [String] = []
        if bold != nil { mask.append("bold") }
        if italic != nil { mask.append("italic") }
        if underline != nil { mask.append("underline") }
        if strikethrough != nil { mask.append("strikethrough") }
        if foregroundColor != nil { mask.append("foregroundColor") }
        if backgroundColor != nil { mask.append("backgroundColor") }
        if fontSize != nil { mask.append("fontSize") }
        if weightedFontFamily != nil { mask.append("weightedFontFamily") }
        if baselineOffset != nil { mask.append("baselineOffset") }
        if link != nil { mask.append("link") }

        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument("style text requires at least one style option")
        }

        let style = DocsTextStyle(
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            fontSize: fontSize.map { DocsDimension(magnitude: $0, unit: .pt) },
            weightedFontFamily: weightedFontFamily,
            baselineOffset: baselineOffset,
            link: link
        )
        let request = DocsBatchUpdateRequest.updateTextStyle(DocsUpdateTextStyleRequest(
            textStyle: style, fields: mask.joined(separator: ","), range: range))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Styles the paragraphs a range touches: named style, alignment,
    /// direction, line spacing, spacing, and indents.
    ///
    /// - Parameters:
    ///   - startIndex / endIndex: the zero-based, half-open UTF-16 range; every
    ///     paragraph it touches is styled. `endIndex` must be greater than
    ///     `startIndex`.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///   - namedStyleType: the named style (`NORMAL_TEXT`, `TITLE`, `SUBTITLE`,
    ///     or `HEADING_1` through `HEADING_6`), matched case-insensitively; a
    ///     value outside that set is rejected before any request goes out.
    ///   - alignment / direction: the horizontal alignment and reading
    ///     direction.
    ///   - lineSpacing: a percent of normal (100 = single); must be greater
    ///     than zero.
    ///   - spaceAbove / spaceBelow / indentStart / indentEnd / indentFirstLine:
    ///     point measurements; each must be 0 or greater.
    ///
    /// The `fields` mask is emitted in the fixed order `namedStyleType`,
    /// `alignment`, `direction`, `lineSpacing`, `spaceAbove`, `spaceBelow`,
    /// `indentStart`, `indentEnd`, `indentFirstLine`. At least one parameter is
    /// required.
    public func styleParagraphs(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        segmentId: String? = nil,
        namedStyleType: String? = nil,
        alignment: DocsParagraphAlignment? = nil,
        direction: DocsContentDirection? = nil,
        lineSpacing: Double? = nil,
        spaceAbove: Double? = nil,
        spaceBelow: Double? = nil,
        indentStart: Double? = nil,
        indentEnd: Double? = nil,
        indentFirstLine: Double? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.makeStyleRange(
            startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)

        var resolvedNamedStyle: DocsNamedStyleType?
        if let namedStyleType {
            guard let value = DocsNamedStyleType(rawValue: namedStyleType.uppercased()) else {
                throw GrahamError.invalidArgument(
                    "unknown named style \"\(namedStyleType)\"; use one of NORMAL_TEXT, TITLE, "
                    + "SUBTITLE, or HEADING_1 through HEADING_6")
            }
            resolvedNamedStyle = value
        }

        if let lineSpacing {
            guard lineSpacing > 0 else {
                throw GrahamError.invalidArgument(
                    "line spacing must be greater than zero, got \(lineSpacing)")
            }
        }
        func requireNonNegative(_ value: Double?, _ label: String) throws {
            if let value, value < 0 {
                throw GrahamError.invalidArgument("\(label) must be 0 or greater, got \(value)")
            }
        }
        try requireNonNegative(spaceAbove, "space above")
        try requireNonNegative(spaceBelow, "space below")
        try requireNonNegative(indentStart, "indent start")
        try requireNonNegative(indentEnd, "indent end")
        try requireNonNegative(indentFirstLine, "first-line indent")

        var mask: [String] = []
        if resolvedNamedStyle != nil { mask.append("namedStyleType") }
        if alignment != nil { mask.append("alignment") }
        if direction != nil { mask.append("direction") }
        if lineSpacing != nil { mask.append("lineSpacing") }
        if spaceAbove != nil { mask.append("spaceAbove") }
        if spaceBelow != nil { mask.append("spaceBelow") }
        if indentStart != nil { mask.append("indentStart") }
        if indentEnd != nil { mask.append("indentEnd") }
        if indentFirstLine != nil { mask.append("indentFirstLine") }

        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument(
                "style paragraphs requires at least one style option")
        }

        func points(_ value: Double?) -> DocsDimension? {
            value.map { DocsDimension(magnitude: $0, unit: .pt) }
        }
        let style = DocsParagraphStyle(
            namedStyleType: resolvedNamedStyle,
            alignment: alignment,
            direction: direction,
            lineSpacing: lineSpacing,
            spaceAbove: points(spaceAbove),
            spaceBelow: points(spaceBelow),
            indentStart: points(indentStart),
            indentEnd: points(indentEnd),
            indentFirstLine: points(indentFirstLine)
        )
        let request = DocsBatchUpdateRequest.updateParagraphStyle(DocsUpdateParagraphStyleRequest(
            paragraphStyle: style, fields: mask.joined(separator: ","), range: range))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
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
                // The lexical guard above is blind to a symlink already sitting
                // at the target name: `Data.write(to:)` would follow it and
                // write outside the directory. Writing through `O_NOFOLLOW`
                // refuses a symlink atomically, so it cannot redirect the write.
                try Self.writeRefusingSymlink(data, to: fileURL)
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

    /// A downloaded image could not be written to disk.
    private struct ImageWriteError: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    /// Writes `data` to `url` without following a symlink at the final path
    /// component.
    ///
    /// `Data.write(to:)` follows a symlink, so a symlink pre-planted at the
    /// deterministic target name could redirect the write outside the target
    /// directory — the lexical parent-directory guard in
    /// ``downloadImages(_:to:)`` cannot see it. Opening with `O_NOFOLLOW`
    /// makes `open` fail (`ELOOP`) when the final component is a symlink,
    /// closing that hole atomically with no check-then-write race, while
    /// `O_CREAT | O_TRUNC` still create or overwrite an ordinary file. Any
    /// failure throws, so the caller records a `.failed` download instead of
    /// writing through the link.
    private static func writeRefusingSymlink(_ data: Data, to url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return open(pointer, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o644)
        }
        guard descriptor >= 0 else {
            throw ImageWriteError(
                reason: "cannot open \(url.lastPathComponent): "
                    + String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(descriptor, pointer, remaining)
                if written < 0 {
                    throw ImageWriteError(
                        reason: "cannot write \(url.lastPathComponent): "
                            + String(cString: strerror(errno)))
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }
}
