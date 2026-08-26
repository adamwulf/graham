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
    /// with no segment id). The body's first editable index is 1; a named
    /// segment starts its content at 0. `endIndex` must be greater than
    /// `startIndex`.
    private static func makeStyleRange(
        startIndex: Int, endIndex: Int, segmentId: String?
    ) throws -> DocsRange {
        // The Docs API reads an empty segment id as the document body, so
        // normalize "" to nil before choosing the guard: an empty or nil
        // segmentId uses the body guard and encodes no segmentId; only a
        // non-empty id is treated as a named segment.
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        // The body's first editable index is 1 (index 0 lands inside the initial
        // section break); a named segment starts at 0. This matches the existing
        // text ops.
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
            // The Docs API requires a non-empty family whenever weightedFontFamily
            // is set, so reject a blank one before it reaches the wire.
            guard !fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrahamError.invalidArgument("font family must not be empty")
            }
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

    // MARK: - Lists (bullets)
    //
    // Both methods reuse `makeStyleRange` for the shared range rules: an empty
    // `segmentId` normalizes to the body, the body's first editable index is 1
    // (a named segment starts at 0), and `endIndex` must be greater than
    // `startIndex`. The range is zero-based UTF-16, exactly like the styling ops.

    /// Turns every paragraph the range touches into a list, using a bullet
    /// `preset` (its glyphs or numbering).
    ///
    /// - Parameters:
    ///   - startIndex / endIndex: the zero-based, half-open UTF-16 range; every
    ///     paragraph it overlaps becomes a list item. `endIndex` must be greater
    ///     than `startIndex`.
    ///   - preset: the ``DocsBulletPreset`` spelling (case-insensitive), such as
    ///     `BULLET_DISC_CIRCLE_SQUARE`, `BULLET_CHECKBOX`, or
    ///     `NUMBERED_DECIMAL_ALPHA_ROMAN`. A value outside the preset set is
    ///     rejected before any request goes out.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///
    /// Nesting comes from the leading tab characters already in each paragraph;
    /// the API counts them, then removes them, so the write may shift later
    /// indices.
    public func createParagraphBullets(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        preset: String,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.makeStyleRange(
            startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)
        guard let bulletPreset = DocsBulletPreset(rawValue: preset.uppercased()) else {
            throw GrahamError.invalidArgument(
                "unknown bullet preset \"\(preset)\"; use one of "
                + DocsBulletPreset.allCases.map(\.rawValue).joined(separator: ", "))
        }
        let request = DocsBatchUpdateRequest.createParagraphBullets(
            DocsCreateParagraphBulletsRequest(range: range, bulletPreset: bulletPreset))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Removes bullets from every paragraph the range touches, preserving the
    /// visual nesting through indents.
    ///
    /// - Parameters:
    ///   - startIndex / endIndex: the zero-based, half-open UTF-16 range; every
    ///     paragraph it overlaps loses its bullets. `endIndex` must be greater
    ///     than `startIndex`.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    public func deleteParagraphBullets(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.makeStyleRange(
            startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)
        let request = DocsBatchUpdateRequest.deleteParagraphBullets(
            DocsDeleteParagraphBulletsRequest(range: range))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    // MARK: - Tables (structure)
    //
    // Every table structure op locates the table by its zero-based UTF-16 start
    // index (the value `docs structure` prints) and, for the cell-addressed ops,
    // a cell's row and column. The CLI shows and accepts one-based row and column
    // numbers; these methods subtract one at the client boundary, exactly as the
    // Slides table methods do. Spans are one-based counts (passed through), and a
    // pinned-header count is a count of 0 or greater. An empty `segmentId`
    // normalizes to the body (encoded with no segment id), matching the text and
    // styling ops. Replies are empty objects.

    /// Throws ``GrahamError/invalidArgument(_:)`` unless a one-based index or
    /// span is at least one.
    private static func requireOneBased(_ value: Int, label: String) throws {
        guard value >= 1 else {
            throw GrahamError.invalidArgument(
                "\(label) must be one-based (1 or greater), got \(value)")
        }
    }

    /// Builds a ``DocsLocation`` at a table's zero-based start index, normalizing
    /// an empty `segmentId` to the body (encoded with no segment id).
    private static func tableStartLocation(
        tableStartIndex: Int, segmentId: String?
    ) -> DocsLocation {
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        return DocsLocation(index: tableStartIndex, segmentId: segmentId)
    }

    /// Translates a one-based cell target to a ``DocsTableCellLocation`` at the
    /// table's zero-based start index. `row` and `column` are validated as
    /// one-based, then subtracted to the API's zero-based `rowIndex`/`columnIndex`.
    private static func tableCellLocation(
        tableStartIndex: Int, segmentId: String?, row: Int, column: Int
    ) throws -> DocsTableCellLocation {
        try requireOneBased(row, label: "table row")
        try requireOneBased(column, label: "table column")
        return DocsTableCellLocation(
            tableStartLocation: tableStartLocation(
                tableStartIndex: tableStartIndex, segmentId: segmentId),
            rowIndex: row - 1,
            columnIndex: column - 1
        )
    }

    /// Inserts an empty `rows` x `columns` table and returns the batch response
    /// plus the resulting table start index.
    ///
    /// The destination is exactly one of an explicit `index` (a ``DocsLocation``)
    /// or the end of a segment (`endOfSegment`). The API inserts a newline before
    /// the table, so when an `index` is given the table starts at `index + 1`;
    /// that value is returned as `tableStartIndex` so the caller can address the
    /// new table with the other table ops. For the end-of-segment path the
    /// resulting index cannot be computed without re-reading the document, so
    /// `tableStartIndex` is nil.
    ///
    /// A table can go in the body, a header, or a footer, but **not** a footnote
    /// (the API rejects an `insertTable` there with a 400). The API also rejects
    /// an insert location that is an existing table's start index; that is a
    /// server-side rule this client cannot check, so such a call reaches Google
    /// and returns its error.
    ///
    /// - Parameters:
    ///   - rows / columns: the table dimensions; each must be 1 or greater.
    ///   - index: the zero-based UTF-16 body index to insert at. Required unless
    ///     `endOfSegment` is set. The body's first editable index is 1 (index 0
    ///     lands inside the initial section break); a named segment starts at 0.
    ///   - endOfSegment: append to the end of the body (or the segment named by
    ///     `segmentId`) without computing an index. Mutually exclusive with
    ///     `index`; provide exactly one.
    ///   - segmentId: a header or footer segment (a footnote cannot hold a
    ///     table); nil or an empty string targets the body.
    public func insertTable(
        documentId: String,
        rows: Int,
        columns: Int,
        index: Int? = nil,
        endOfSegment: Bool = false,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, tableStartIndex: Int?) {
        guard rows >= 1 else {
            throw GrahamError.invalidArgument("table rows must be 1 or greater, got \(rows)")
        }
        guard columns >= 1 else {
            throw GrahamError.invalidArgument(
                "table columns must be 1 or greater, got \(columns)")
        }
        // The destination is exactly one of an explicit index or the end of the
        // segment: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfSegment, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the segment, not both")
        }
        // The Docs API reads an empty segment id as the document body, so
        // normalize "" to nil before choosing the guard and building the target.
        let segmentId = segmentId.flatMap { $0.isEmpty ? nil : $0 }
        let insert: DocsInsertTableRequest
        let tableStartIndex: Int?
        if endOfSegment {
            insert = DocsInsertTableRequest(
                rows: rows, columns: columns,
                endOfSegmentLocation: DocsEndOfSegmentLocation(segmentId: segmentId))
            tableStartIndex = nil
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
            insert = DocsInsertTableRequest(
                rows: rows, columns: columns,
                location: DocsLocation(index: index, segmentId: segmentId))
            // The API inserts a newline before the table, so the table starts one
            // index past the insertion point.
            tableStartIndex = index + 1
        }
        let request = DocsBatchUpdateRequest.insertTable(insert)
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, tableStartIndex)
    }

    /// Inserts an empty row above or below a reference cell.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - row / column: the one-based reference cell; translated to zero-based.
    ///   - below: true inserts below the reference row, false inserts above it.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func insertTableRow(
        documentId: String,
        tableStartIndex: Int,
        row: Int,
        column: Int,
        below: Bool,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let cell = try Self.tableCellLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId, row: row, column: column)
        let request = DocsBatchUpdateRequest.insertTableRow(
            DocsInsertTableRowRequest(tableCellLocation: cell, insertBelow: below))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Inserts an empty column left or right of a reference cell.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - row / column: the one-based reference cell; translated to zero-based.
    ///   - right: true inserts to the right of the reference column, false to its
    ///     left.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func insertTableColumn(
        documentId: String,
        tableStartIndex: Int,
        row: Int,
        column: Int,
        right: Bool,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let cell = try Self.tableCellLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId, row: row, column: column)
        let request = DocsBatchUpdateRequest.insertTableColumn(
            DocsInsertTableColumnRequest(tableCellLocation: cell, insertRight: right))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Deletes the row of a reference cell. A merged reference cell deletes every
    /// row it spans.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - row / column: the one-based reference cell; translated to zero-based.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func deleteTableRow(
        documentId: String,
        tableStartIndex: Int,
        row: Int,
        column: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let cell = try Self.tableCellLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId, row: row, column: column)
        let request = DocsBatchUpdateRequest.deleteTableRow(
            DocsDeleteTableRowRequest(tableCellLocation: cell))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Deletes the column of a reference cell. A merged reference cell deletes
    /// every column it spans.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - row / column: the one-based reference cell; translated to zero-based.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func deleteTableColumn(
        documentId: String,
        tableStartIndex: Int,
        row: Int,
        column: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let cell = try Self.tableCellLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId, row: row, column: column)
        let request = DocsBatchUpdateRequest.deleteTableColumn(
            DocsDeleteTableColumnRequest(tableCellLocation: cell))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Merges the cells of a table range into the range's head cell.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - row / column: the one-based head cell of the range; translated to
    ///     zero-based.
    ///   - rowSpan / columnSpan: the range's cell-count spans; each must be 1 or
    ///     greater and is passed through unchanged.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func mergeTableCells(
        documentId: String,
        tableStartIndex: Int,
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.tableRange(
            tableStartIndex: tableStartIndex, segmentId: segmentId,
            row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
        let request = DocsBatchUpdateRequest.mergeTableCells(
            DocsMergeTableCellsRequest(tableRange: range))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Unmerges every merged cell in a table range.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - row / column: the one-based head cell of the range; translated to
    ///     zero-based.
    ///   - rowSpan / columnSpan: the range's cell-count spans; each must be 1 or
    ///     greater and is passed through unchanged.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func unmergeTableCells(
        documentId: String,
        tableStartIndex: Int,
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.tableRange(
            tableStartIndex: tableStartIndex, segmentId: segmentId,
            row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
        let request = DocsBatchUpdateRequest.unmergeTableCells(
            DocsUnmergeTableCellsRequest(tableRange: range))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Builds a one-based ``DocsTableRange``, validating the head cell and spans
    /// and translating the head cell to the API's zero-based convention.
    private static func tableRange(
        tableStartIndex: Int, segmentId: String?,
        row: Int, column: Int, rowSpan: Int, columnSpan: Int
    ) throws -> DocsTableRange {
        let cell = try tableCellLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId, row: row, column: column)
        try requireOneBased(rowSpan, label: "table row span")
        try requireOneBased(columnSpan, label: "table column span")
        return DocsTableRange(
            tableCellLocation: cell, rowSpan: rowSpan, columnSpan: columnSpan)
    }

    /// Pins the first `pinnedHeaderRowsCount` rows of a table as headers; 0
    /// unpins.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - pinnedHeaderRowsCount: the number of leading rows to pin; must be 0 or
    ///     greater.
    ///   - segmentId: a header, footer, or footnote segment; nil or empty targets
    ///     the body.
    public func pinTableHeaderRows(
        documentId: String,
        tableStartIndex: Int,
        pinnedHeaderRowsCount: Int,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard pinnedHeaderRowsCount >= 0 else {
            throw GrahamError.invalidArgument(
                "pinned header rows count must be 0 or greater, got \(pinnedHeaderRowsCount)")
        }
        let start = Self.tableStartLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId)
        let request = DocsBatchUpdateRequest.pinTableHeaderRows(
            DocsPinTableHeaderRowsRequest(
                tableStartLocation: start, pinnedHeaderRowsCount: pinnedHeaderRowsCount))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    // MARK: - Tables (styling)
    //
    // Each styling method builds a deterministic `fields` mask — one path per
    // provided property, in a fixed documented order — and requires at least one
    // style option or it throws ``GrahamError/invalidArgument(_:)`` and sends
    // nothing, the same discipline as the text and paragraph styling above. The
    // mask paths are relative to the style root, so they are bare field names.
    // Cell styling addresses either a subset of cells (a ``DocsTableRange``) or
    // the whole table (a ``DocsLocation`` at the table start); row and column
    // styling take one-based CLI numbers and subtract one at the client boundary,
    // with an empty list meaning every row or column. All point dimensions must
    // be greater than zero, and a fixed column width must be at least 5 pt.

    /// Styles a subset of table cells, or a whole table: background color, the
    /// four cell borders, the four cell paddings, and the vertical content
    /// alignment.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index (the value
    ///     `docs structure` prints).
    ///   - row / column: the one-based head cell of the range to style;
    ///     translated to the API's zero-based indices. Provide **both** to style
    ///     a range, or omit both to style the whole table. Providing only one is
    ///     rejected.
    ///   - rowSpan / columnSpan: the range's cell-count spans; each must be 1 or
    ///     greater and defaults to 1. They are meaningful only with a `row` and
    ///     `column`.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///   - backgroundColor: the cell background, already parsed to a
    ///     ``DocsOptionalColor``.
    ///   - borderColor: the color of all four cell borders. A border is set only
    ///     when a color is given; passing a `borderWidth` or `borderDash` without
    ///     a color is rejected.
    ///   - borderWidth: the border width in points (defaults to 1); must not be
    ///     negative. A width of 0 hides the border (border removal).
    ///   - borderDash: the border dash style (defaults to solid).
    ///   - padding: the padding of all four cell sides in points; must not be
    ///     negative (0 means no padding).
    ///   - contentAlignment: the vertical content alignment (top, middle, or
    ///     bottom).
    ///
    /// A single `borderColor` sets all four borders and a single `padding` sets
    /// all four paddings; the `fields` mask lists all four border paths when a
    /// border is set and all four padding paths when a padding is set, plus
    /// `backgroundColor` and/or `contentAlignment`, in the fixed order
    /// `backgroundColor`, `borderLeft`, `borderRight`, `borderTop`,
    /// `borderBottom`, `paddingLeft`, `paddingRight`, `paddingTop`,
    /// `paddingBottom`, `contentAlignment`. At least one style option is required.
    public func styleTableCells(
        documentId: String,
        tableStartIndex: Int,
        row: Int? = nil,
        column: Int? = nil,
        rowSpan: Int? = nil,
        columnSpan: Int? = nil,
        segmentId: String? = nil,
        backgroundColor: DocsOptionalColor? = nil,
        borderColor: DocsOptionalColor? = nil,
        borderWidth: Double? = nil,
        borderDash: DocsDashStyle? = nil,
        padding: Double? = nil,
        contentAlignment: DocsContentAlignment? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // A border is set only when a color is provided; a width or dash alone
        // has nothing to attach to.
        if borderColor == nil, borderWidth != nil || borderDash != nil {
            throw GrahamError.invalidArgument(
                "a cell border requires a color; set a border color to set its width or dash")
        }
        var border: DocsTableCellBorder?
        if let borderColor {
            let width = borderWidth ?? 1
            // The Docs API treats a border width of 0 as hiding the border, so 0
            // is a valid value (border removal); only a negative width is invalid.
            guard width >= 0 else {
                throw GrahamError.invalidArgument(
                    "border width must not be negative, got \(width)")
            }
            border = DocsTableCellBorder(
                color: borderColor,
                width: DocsDimension(magnitude: width, unit: .pt),
                dashStyle: borderDash ?? .solid)
        }

        var paddingDimension: DocsDimension?
        if let padding {
            // A padding of 0 is valid (no padding); only a negative value is
            // invalid.
            guard padding >= 0 else {
                throw GrahamError.invalidArgument(
                    "cell padding must not be negative, got \(padding)")
            }
            paddingDimension = DocsDimension(magnitude: padding, unit: .pt)
        }

        var mask: [String] = []
        if backgroundColor != nil { mask.append("backgroundColor") }
        if border != nil {
            mask.append(contentsOf: ["borderLeft", "borderRight", "borderTop", "borderBottom"])
        }
        if paddingDimension != nil {
            mask.append(contentsOf: ["paddingLeft", "paddingRight", "paddingTop", "paddingBottom"])
        }
        if contentAlignment != nil { mask.append("contentAlignment") }

        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument(
                "style table cells requires at least one style option")
        }

        let style = DocsTableCellStyle(
            backgroundColor: backgroundColor,
            borderLeft: border,
            borderRight: border,
            borderTop: border,
            borderBottom: border,
            paddingLeft: paddingDimension,
            paddingRight: paddingDimension,
            paddingTop: paddingDimension,
            paddingBottom: paddingDimension,
            contentAlignment: contentAlignment)
        let fields = mask.joined(separator: ",")

        // A cell target is given when any of row/column/span is present; then
        // both a row and a column are required. Otherwise the whole table is
        // styled.
        let styleRequest: DocsUpdateTableCellStyleRequest
        if row != nil || column != nil || rowSpan != nil || columnSpan != nil {
            guard let row, let column else {
                throw GrahamError.invalidArgument(
                    "provide both a row and a column to style a cell range, "
                    + "or omit them to style the whole table")
            }
            let range = try Self.tableRange(
                tableStartIndex: tableStartIndex, segmentId: segmentId,
                row: row, column: column, rowSpan: rowSpan ?? 1, columnSpan: columnSpan ?? 1)
            styleRequest = DocsUpdateTableCellStyleRequest(
                tableCellStyle: style, fields: fields, tableRange: range)
        } else {
            let start = Self.tableStartLocation(
                tableStartIndex: tableStartIndex, segmentId: segmentId)
            styleRequest = DocsUpdateTableCellStyleRequest(
                tableCellStyle: style, fields: fields, tableStartLocation: start)
        }
        return try await batchUpdate(
            documentId: documentId,
            requests: [.updateTableCellStyle(styleRequest)],
            requiredRevisionId: requiredRevisionId)
    }

    /// Sets the row style of the listed rows, or every row: minimum height,
    /// header flag, and overflow behavior.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - rows: the one-based rows to style; each is translated to a zero-based
    ///     API index. An empty list styles every row (encoded as no
    ///     `rowIndices`).
    ///   - minRowHeight: the minimum row height in points; must be greater than
    ///     zero.
    ///   - tableHeader: mark the rows as repeated table headers.
    ///   - preventOverflow: keep each row's content from spilling across a page
    ///     break.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///
    /// The `fields` mask is emitted in the fixed order `minRowHeight`,
    /// `tableHeader`, `preventOverflow`. At least one style option is required.
    public func styleTableRow(
        documentId: String,
        tableStartIndex: Int,
        rows: [Int] = [],
        minRowHeight: Double? = nil,
        tableHeader: Bool? = nil,
        preventOverflow: Bool? = nil,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        if let minRowHeight {
            guard minRowHeight > 0 else {
                throw GrahamError.invalidArgument(
                    "minimum row height must be greater than zero, got \(minRowHeight)")
            }
        }
        var mask: [String] = []
        if minRowHeight != nil { mask.append("minRowHeight") }
        if tableHeader != nil { mask.append("tableHeader") }
        if preventOverflow != nil { mask.append("preventOverflow") }
        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument(
                "style table row requires at least one style option")
        }

        // One-based CLI rows become zero-based API indices; an empty list means
        // every row, which the API expresses as an omitted rowIndices.
        let rowIndices: [Int]?
        if rows.isEmpty {
            rowIndices = nil
        } else {
            for row in rows { try Self.requireOneBased(row, label: "table row") }
            rowIndices = rows.map { $0 - 1 }
        }

        let start = Self.tableStartLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId)
        let style = DocsTableRowStyle(
            minRowHeight: minRowHeight.map { DocsDimension(magnitude: $0, unit: .pt) },
            tableHeader: tableHeader,
            preventOverflow: preventOverflow)
        let request = DocsUpdateTableRowStyleRequest(
            tableStartLocation: start, rowIndices: rowIndices,
            tableRowStyle: style, fields: mask.joined(separator: ","))
        return try await batchUpdate(
            documentId: documentId,
            requests: [.updateTableRowStyle(request)],
            requiredRevisionId: requiredRevisionId)
    }

    /// Sets the width of the listed columns, or every column: either a fixed
    /// point width or evenly distributed.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - columns: the one-based columns to style; each is translated to a
    ///     zero-based API index. An empty list styles every column (encoded as no
    ///     `columnIndices`).
    ///   - width: a fixed width in points; implies `FIXED_WIDTH` and must be at
    ///     least 5 points. Mutually exclusive with `evenlyDistributed`.
    ///   - evenlyDistributed: distribute the table width evenly across columns;
    ///     implies `EVENLY_DISTRIBUTED` and carries no width. Mutually exclusive
    ///     with `width`.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///
    /// Exactly one of `width` or `evenlyDistributed` is required. The `fields`
    /// mask is `widthType,width` for a fixed width and `widthType` for evenly
    /// distributed.
    public func styleTableColumnWidth(
        documentId: String,
        tableStartIndex: Int,
        columns: [Int] = [],
        width: Double? = nil,
        evenlyDistributed: Bool = false,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // Exactly one sizing mode: a fixed width or evenly distributed.
        if width != nil, evenlyDistributed {
            throw GrahamError.invalidArgument(
                "provide either a fixed width or evenly-distributed, not both")
        }
        guard width != nil || evenlyDistributed else {
            throw GrahamError.invalidArgument(
                "provide a fixed width, or set the columns to evenly-distributed")
        }

        let properties: DocsTableColumnProperties
        let mask: [String]
        if let width {
            guard width >= 5 else {
                throw GrahamError.invalidArgument(
                    "a fixed column width must be at least 5 points, got \(width)")
            }
            properties = DocsTableColumnProperties(
                widthType: .fixedWidth, width: DocsDimension(magnitude: width, unit: .pt))
            mask = ["widthType", "width"]
        } else {
            properties = DocsTableColumnProperties(widthType: .evenlyDistributed)
            mask = ["widthType"]
        }

        // One-based CLI columns become zero-based API indices; an empty list
        // means every column, which the API expresses as an omitted
        // columnIndices.
        let columnIndices: [Int]?
        if columns.isEmpty {
            columnIndices = nil
        } else {
            for column in columns { try Self.requireOneBased(column, label: "table column") }
            columnIndices = columns.map { $0 - 1 }
        }

        let start = Self.tableStartLocation(
            tableStartIndex: tableStartIndex, segmentId: segmentId)
        let request = DocsUpdateTableColumnPropertiesRequest(
            tableStartLocation: start, columnIndices: columnIndices,
            tableColumnProperties: properties, fields: mask.joined(separator: ","))
        return try await batchUpdate(
            documentId: documentId,
            requests: [.updateTableColumnProperties(request)],
            requiredRevisionId: requiredRevisionId)
    }

    // MARK: - Structure and images
    //
    // Page breaks and section breaks are body-only in the API (their location's
    // segment id must be empty), so those two methods take no segment and apply
    // the body guard `index >= 1` (index 0 lands inside the initial section
    // break the body cannot edit). Inline images may go in the body, a header,
    // or a footer (not a footnote), so `insertInlineImage` normalizes an empty
    // segment id to the body and uses the shared per-segment index rules (body
    // >= 1, a named segment >= 0), exactly like the text and table inserts.
    // Indices stay zero-based UTF-16, matching the API. Replies are empty for
    // every op except `insertInlineImage`, whose reply carries the new object id.

    /// Inserts a page break plus a newline in the document body.
    ///
    /// The destination is exactly one of an explicit body `index` (a
    /// ``DocsLocation``) or the end of the body (`endOfSegment`). Page breaks are
    /// body-only in the Docs API, so there is no segment option.
    ///
    /// - Parameters:
    ///   - index: the zero-based UTF-16 body index to insert at. Required unless
    ///     `endOfSegment` is set. The body's first editable index is 1 (index 0
    ///     lands inside the initial section break).
    ///   - endOfSegment: append the page break to the end of the body without
    ///     computing an index. Mutually exclusive with `index`; provide exactly
    ///     one.
    public func insertPageBreak(
        documentId: String,
        index: Int? = nil,
        endOfSegment: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // The destination is exactly one of an explicit index or the end of the
        // body: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfSegment, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the body, not both")
        }
        let insert: DocsInsertPageBreakRequest
        if endOfSegment {
            insert = .endOfBody
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the body")
            }
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
            insert = DocsInsertPageBreakRequest(bodyIndex: index)
        }
        let request = DocsBatchUpdateRequest.insertPageBreak(insert)
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Inserts an inline image from a `uri` and returns the batch response plus
    /// the new image's object id (from the reply).
    ///
    /// The `uri` must be publicly fetchable by Google at insertion time
    /// (< 50MB, <= 25 megapixels, PNG/JPEG/GIF); Google fetches it once and
    /// stores a copy. The destination is exactly one of an explicit `index` (a
    /// ``DocsLocation``) or the end of the body or a segment (`endOfSegment`).
    ///
    /// - Parameters:
    ///   - uri: the image URI; must not be empty.
    ///   - index: the zero-based UTF-16 index to insert at. Required unless
    ///     `endOfSegment` is set. The body's first editable index is 1; a named
    ///     segment starts at 0.
    ///   - endOfSegment: append to the end of the body (or the segment named by
    ///     `segmentId`) without computing an index. Mutually exclusive with
    ///     `index`; provide exactly one.
    ///   - segmentId: a header or footer segment (an inline image cannot go in a
    ///     footnote); nil or an empty string targets the body.
    ///   - width / height: the optional display size in points; each must be
    ///     greater than zero when given. Omitting both lets the API size the
    ///     image from its resolution; giving one lets the API compute the other
    ///     to preserve the aspect ratio.
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
        if let width {
            guard width > 0 else {
                throw GrahamError.invalidArgument(
                    "image width must be greater than zero, got \(width)")
            }
        }
        if let height {
            guard height > 0 else {
                throw GrahamError.invalidArgument(
                    "image height must be greater than zero, got \(height)")
            }
        }
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

    /// Deletes a positioned object by its object id.
    ///
    /// Positioned objects cannot be created through the Docs API, only deleted;
    /// the id comes from a document read (`docs images` lists positioned images).
    ///
    /// - Parameter objectId: the id of the positioned object to delete; must not
    ///   be empty.
    public func deletePositionedObject(
        documentId: String,
        objectId: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !objectId.isEmpty else {
            throw GrahamError.invalidArgument("the object id must not be empty")
        }
        let request = DocsBatchUpdateRequest.deletePositionedObject(
            DocsDeletePositionedObjectRequest(objectId: objectId))
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
    ///     one.
    public func insertSectionBreak(
        documentId: String,
        sectionType: String,
        index: Int? = nil,
        endOfSegment: Bool = false,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard let type = DocsSectionType(rawValue: sectionType.uppercased()) else {
            throw GrahamError.invalidArgument(
                "unknown section type \"\(sectionType)\"; use CONTINUOUS or NEXT_PAGE")
        }
        // The destination is exactly one of an explicit index or the end of the
        // body: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfSegment, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the body, not both")
        }
        let insert: DocsInsertSectionBreakRequest
        if endOfSegment {
            insert = .endOfBody(sectionType: type)
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the body")
            }
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
            insert = DocsInsertSectionBreakRequest(sectionType: type, bodyIndex: index)
        }
        let request = DocsBatchUpdateRequest.insertSectionBreak(insert)
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    // MARK: - Headers, footers, footnotes
    //
    // A create returns the new segment id from its reply (`headerId` /
    // `footerId` / `footnoteId`) so a follow-up segment-aware write can target
    // it. Headers and footers optionally scope to a section through a body index
    // (a section-break `Location`); that index follows the body guard `>= 1`
    // (index 0 lands inside the initial section break the body cannot edit).
    // Footnote references live in the body, so `createFootnote` is body-only:
    // it takes only a body index or the end of the body, no segment. Indices
    // stay zero-based UTF-16, matching the API. The two delete ops reject an
    // empty id and reply with an empty object.

    /// Creates a header and returns the batch response plus the new header's
    /// segment id (from the reply).
    ///
    /// The header `type` is always `DEFAULT` (the only usable value). First-page
    /// and even-page headers are enabled through `updateDocumentStyle` flags, not
    /// here.
    ///
    /// - Parameters:
    ///   - sectionBreakIndex: an optional zero-based UTF-16 body index at a
    ///     section break, scoping the header to that section. The body's first
    ///     editable index is 1 (index 0 lands inside the initial section break).
    ///     When nil, the header applies to the whole document.
    public func createHeader(
        documentId: String,
        sectionBreakIndex: Int? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, headerId: String?) {
        let sectionBreakLocation = try Self.sectionBreakLocation(from: sectionBreakIndex)
        let request = DocsBatchUpdateRequest.createHeader(
            DocsCreateHeaderRequest(type: .default, sectionBreakLocation: sectionBreakLocation))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, response.replies?.first?.createHeader?.headerId)
    }

    /// Creates a footer and returns the batch response plus the new footer's
    /// segment id (from the reply).
    ///
    /// The footer `type` is always `DEFAULT`. First-page and even-page footers
    /// are enabled through `updateDocumentStyle` flags, not here.
    ///
    /// - Parameter sectionBreakIndex: an optional zero-based UTF-16 body index at
    ///   a section break, scoping the footer to that section (body minimum 1).
    ///   When nil, the footer applies to the whole document.
    public func createFooter(
        documentId: String,
        sectionBreakIndex: Int? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, footerId: String?) {
        let sectionBreakLocation = try Self.sectionBreakLocation(from: sectionBreakIndex)
        let request = DocsBatchUpdateRequest.createFooter(
            DocsCreateFooterRequest(type: .default, sectionBreakLocation: sectionBreakLocation))
        let response = try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
        return (response, response.replies?.first?.createFooter?.footerId)
    }

    /// Builds the optional section-break body location for a header or footer
    /// create, validating the body index. A nil index means no section scope
    /// (nil location); a provided index must satisfy the body guard `>= 1`.
    private static func sectionBreakLocation(from index: Int?) throws -> DocsLocation? {
        guard let index else { return nil }
        guard index >= 1 else {
            throw GrahamError.invalidArgument(
                "the section-break index must be 1 or greater; the document body starts at index 1")
        }
        return DocsLocation(index: index)
    }

    /// Deletes a header by its segment id.
    ///
    /// - Parameter headerId: the id of the header segment to delete (from a
    ///   `createHeader` reply, or `docs structure`); must not be empty.
    public func deleteHeader(
        documentId: String,
        headerId: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !headerId.isEmpty else {
            throw GrahamError.invalidArgument("the header id must not be empty")
        }
        let request = DocsBatchUpdateRequest.deleteHeader(
            DocsDeleteHeaderRequest(headerId: headerId))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Deletes a footer by its segment id.
    ///
    /// - Parameter footerId: the id of the footer segment to delete (from a
    ///   `createFooter` reply, or `docs structure`); must not be empty.
    public func deleteFooter(
        documentId: String,
        footerId: String,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard !footerId.isEmpty else {
            throw GrahamError.invalidArgument("the footer id must not be empty")
        }
        let request = DocsBatchUpdateRequest.deleteFooter(
            DocsDeleteFooterRequest(footerId: footerId))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Creates a footnote (inserting its reference in the document body) and
    /// returns the batch response plus the new footnote's segment id (from the
    /// reply). When `text` is given, its content is inserted into the new
    /// footnote segment with a second batch update.
    ///
    /// The footnote reference lives in the body, so the destination is exactly
    /// one of an explicit body `index` or the end of the body (`endOfBody`);
    /// there is no segment option.
    ///
    /// - Parameters:
    ///   - index: the zero-based UTF-16 body index to insert the reference at.
    ///     Required unless `endOfBody` is set. The body's first editable index is
    ///     1 (index 0 lands inside the initial section break).
    ///   - endOfBody: insert the reference at the end of the body without
    ///     computing an index. Mutually exclusive with `index`; provide exactly
    ///     one.
    ///   - text: optional footnote text. The created footnote segment begins with
    ///     an auto-inserted space and newline, so the text is inserted at index 1
    ///     of the footnote segment. This needs a **second** `batchUpdate`: the
    ///     footnoteId is only known from the first reply, so the text insert
    ///     cannot ride in the same batch. Must be non-empty when given.
    public func createFootnote(
        documentId: String,
        index: Int? = nil,
        endOfBody: Bool = false,
        text: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> (response: DocsBatchUpdateResponse, footnoteId: String?) {
        // Validate the text before creating anything, so an empty --text never
        // leaves an orphan footnote behind (the first write would otherwise
        // succeed and only the second fail).
        if let text, text.isEmpty {
            throw GrahamError.invalidArgument("the footnote text must not be empty")
        }
        // The destination is exactly one of an explicit index or the end of the
        // body: providing both is ambiguous (never silently pick one), and the
        // "neither" case is caught by the guard in the index branch below.
        if endOfBody, index != nil {
            throw GrahamError.invalidArgument(
                "provide either an index or the end of the body, not both")
        }
        let create: DocsCreateFootnoteRequest
        if endOfBody {
            create = .endOfBody
        } else {
            guard let index else {
                throw GrahamError.invalidArgument(
                    "provide an index to insert at, or append to the end of the body")
            }
            guard index >= 1 else {
                throw GrahamError.invalidArgument(
                    "index must be 1 or greater; the document body starts at index 1")
            }
            create = DocsCreateFootnoteRequest(bodyIndex: index)
        }
        let response = try await batchUpdate(
            documentId: documentId,
            requests: [.createFootnote(create)],
            requiredRevisionId: requiredRevisionId)
        let footnoteId = response.replies?.first?.createFootnote?.footnoteId

        if let text {
            // The text goes in a second batch: the footnoteId is only known from
            // the first reply, so it cannot be one batch. The footnote segment's
            // content starts with an auto-inserted space and newline, so the text
            // is inserted at index 1 of the footnote segment.
            guard let footnoteId, !footnoteId.isEmpty else {
                throw GrahamError.invalidArgument(
                    "the footnote was created but Google returned no footnote id, "
                    + "so the text could not be inserted")
            }
            // The second write does not carry the required revision: the first
            // write already advanced the document's revision, so reusing the old
            // required revision would fail the insert.
            _ = try await insertText(
                documentId: documentId, text: text, index: 1, segmentId: footnoteId)
        }
        return (response, footnoteId)
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
