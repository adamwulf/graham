import Foundation

extension DocsClient {
    /// Sets document-wide style: page size, margins, the first-page and even-page
    /// header/footer flags, the background color, and the document mode.
    ///
    /// - Parameters:
    ///   - pageWidth / pageHeight: the page size in points. They are a pair —
    ///     provide **both** or neither. Sending only one would leave the other at
    ///     zero (the API replaces the whole `pageSize` when it is masked), so a
    ///     lone dimension is rejected. Each must be a finite value greater than
    ///     zero.
    ///   - marginTop / marginBottom / marginLeft / marginRight: the page margins
    ///     in points; each must be a finite value greater than zero when given.
    ///   - useFirstPageHeaderFooter / useEvenPageHeaderFooter: toggle the
    ///     first-page and even-page header/footer ids.
    ///   - background: the document background color, already parsed to a
    ///     ``DocsOptionalColor`` (a document background cannot be transparent).
    ///   - documentMode: the document mode, pages or pageless. It masks the nested
    ///     `documentFormat.documentMode` path so only the mode is set.
    ///   - pageNumberStart: the first visible page number; must be 1 or greater.
    ///   - marginHeader / marginFooter: the header and footer margins in points;
    ///     each must be a finite value greater than zero when given. These are
    ///     writable, but the `useCustomHeaderFooterMargins` flag that governs
    ///     whether they apply is read-only (the server derives it), so the client
    ///     sends the margins alone and never masks that flag.
    ///   - flipPageOrientation: swap the page width and height (landscape).
    ///
    /// The `fields` mask is emitted in the fixed order `pageSize`, `marginTop`,
    /// `marginBottom`, `marginLeft`, `marginRight`, `useFirstPageHeaderFooter`,
    /// `useEvenPageHeaderFooter`, `background`, `documentFormat.documentMode`,
    /// `pageNumberStart`, `marginHeader`, `marginFooter`, `flipPageOrientation`.
    /// At least one parameter is required.
    public func updateDocumentStyle(
        documentId: String,
        pageWidth: Double? = nil,
        pageHeight: Double? = nil,
        marginTop: Double? = nil,
        marginBottom: Double? = nil,
        marginLeft: Double? = nil,
        marginRight: Double? = nil,
        useFirstPageHeaderFooter: Bool? = nil,
        useEvenPageHeaderFooter: Bool? = nil,
        background: DocsOptionalColor? = nil,
        documentMode: DocsDocumentMode? = nil,
        pageNumberStart: Int? = nil,
        marginHeader: Double? = nil,
        marginFooter: Double? = nil,
        flipPageOrientation: Bool? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        // Page size is a pair: masking `pageSize` replaces the whole Size, so a
        // lone width or height would zero the other dimension. Require both, or
        // neither.
        if (pageWidth == nil) != (pageHeight == nil) {
            throw GrahamError.invalidArgument(
                "provide both a page width and a page height, or neither")
        }
        // Every dimension must be a finite value strictly greater than zero. The
        // finiteness check rejects NaN and +/-infinity before they reach the JSON
        // encoder (which would otherwise fail there instead of here).
        func requirePositive(_ value: Double?, _ label: String) throws {
            if let value, !(value.isFinite && value > 0) {
                throw GrahamError.invalidArgument(
                    "\(label) must be a finite value greater than zero, got \(value)")
            }
        }
        try requirePositive(pageWidth, "page width")
        try requirePositive(pageHeight, "page height")
        try requirePositive(marginTop, "top margin")
        try requirePositive(marginBottom, "bottom margin")
        try requirePositive(marginLeft, "left margin")
        try requirePositive(marginRight, "right margin")
        try requirePositive(marginHeader, "header margin")
        try requirePositive(marginFooter, "footer margin")

        // A page number must be a real one-based page number.
        if let pageNumberStart {
            guard pageNumberStart >= 1 else {
                throw GrahamError.invalidArgument(
                    "page number start must be 1 or greater, got \(pageNumberStart)")
            }
        }

        // `useCustomHeaderFooterMargins` is read-only on DocumentStyle — the
        // server derives whether the custom header/footer margins apply — so
        // masking it would make the request invalid (Google 400s). We send the
        // writable marginHeader/marginFooter alone and never set or mask the flag.

        func points(_ value: Double?) -> DocsDimension? {
            value.map { DocsDimension(magnitude: $0, unit: .pt) }
        }
        let pageSize: DocsSize?
        if let pageWidth, let pageHeight {
            pageSize = DocsSize(
                height: DocsDimension(magnitude: pageHeight, unit: .pt),
                width: DocsDimension(magnitude: pageWidth, unit: .pt))
        } else {
            pageSize = nil
        }
        let backgroundValue = background.map { DocsBackground(color: $0) }
        let documentFormat = documentMode.map { DocsDocumentFormat(documentMode: $0) }

        var mask: [String] = []
        if pageSize != nil { mask.append("pageSize") }
        if marginTop != nil { mask.append("marginTop") }
        if marginBottom != nil { mask.append("marginBottom") }
        if marginLeft != nil { mask.append("marginLeft") }
        if marginRight != nil { mask.append("marginRight") }
        if useFirstPageHeaderFooter != nil { mask.append("useFirstPageHeaderFooter") }
        if useEvenPageHeaderFooter != nil { mask.append("useEvenPageHeaderFooter") }
        if backgroundValue != nil { mask.append("background") }
        // The mode masks the nested path so only the mode is set, never clearing
        // any other (future) DocumentFormat field.
        if documentFormat != nil { mask.append("documentFormat.documentMode") }
        if pageNumberStart != nil { mask.append("pageNumberStart") }
        if marginHeader != nil { mask.append("marginHeader") }
        if marginFooter != nil { mask.append("marginFooter") }
        if flipPageOrientation != nil { mask.append("flipPageOrientation") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "page setup requires at least one style option")

        let style = DocsDocumentStyle(
            pageSize: pageSize,
            marginTop: points(marginTop),
            marginBottom: points(marginBottom),
            marginLeft: points(marginLeft),
            marginRight: points(marginRight),
            useFirstPageHeaderFooter: useFirstPageHeaderFooter,
            useEvenPageHeaderFooter: useEvenPageHeaderFooter,
            background: backgroundValue,
            documentFormat: documentFormat,
            pageNumberStart: pageNumberStart,
            marginHeader: points(marginHeader),
            marginFooter: points(marginFooter),
            flipPageOrientation: flipPageOrientation)
        let request = DocsBatchUpdateRequest.updateDocumentStyle(
            DocsUpdateDocumentStyleRequest(documentStyle: style, fields: fields))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Restyles every section a body range overlaps.
    ///
    /// The `range` is body-only (its `segmentId` is empty) — section style is a
    /// body concept. Indices are zero-based UTF-16 code units; `endIndex` must be
    /// greater than `startIndex`. Margins are in points and each must be a finite
    /// value greater than zero when given; `pageNumberStart` must be one or
    /// greater. The `fields` mask is emitted in the fixed order `marginTop`,
    /// `marginBottom`, `marginLeft`, `marginRight`, `marginHeader`,
    /// `marginFooter`, `columnSeparatorStyle`, `contentDirection`,
    /// `pageNumberStart`, `useFirstPageHeaderFooter`, `flipPageOrientation`. At
    /// least one parameter is required.
    ///
    /// The section's header/footer ids and `sectionType` are read-only, and the
    /// per-column layout (`columnProperties`) is out of this slice, so none are
    /// settable here.
    public func updateSectionStyle(
        documentId: String,
        startIndex: Int,
        endIndex: Int,
        marginTop: Double? = nil,
        marginBottom: Double? = nil,
        marginLeft: Double? = nil,
        marginRight: Double? = nil,
        marginHeader: Double? = nil,
        marginFooter: Double? = nil,
        columnSeparatorStyle: DocsColumnSeparatorStyle? = nil,
        contentDirection: DocsContentDirection? = nil,
        pageNumberStart: Int? = nil,
        useFirstPageHeaderFooter: Bool? = nil,
        flipPageOrientation: Bool? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard startIndex >= 0 else {
            throw GrahamError.invalidArgument("the range start must be zero or greater")
        }
        guard endIndex > startIndex else {
            throw GrahamError.invalidArgument("the range end must be greater than the start")
        }
        func requirePositive(_ value: Double?, _ label: String) throws {
            if let value, !(value.isFinite && value > 0) {
                throw GrahamError.invalidArgument(
                    "\(label) must be a finite value greater than zero, got \(value)")
            }
        }
        try requirePositive(marginTop, "top margin")
        try requirePositive(marginBottom, "bottom margin")
        try requirePositive(marginLeft, "left margin")
        try requirePositive(marginRight, "right margin")
        try requirePositive(marginHeader, "header margin")
        try requirePositive(marginFooter, "footer margin")
        if let pageNumberStart {
            guard pageNumberStart >= 1 else {
                throw GrahamError.invalidArgument(
                    "page number start must be 1 or greater, got \(pageNumberStart)")
            }
        }

        func points(_ value: Double?) -> DocsDimension? {
            value.map { DocsDimension(magnitude: $0, unit: .pt) }
        }

        var mask: [String] = []
        if marginTop != nil { mask.append("marginTop") }
        if marginBottom != nil { mask.append("marginBottom") }
        if marginLeft != nil { mask.append("marginLeft") }
        if marginRight != nil { mask.append("marginRight") }
        if marginHeader != nil { mask.append("marginHeader") }
        if marginFooter != nil { mask.append("marginFooter") }
        if columnSeparatorStyle != nil { mask.append("columnSeparatorStyle") }
        if contentDirection != nil { mask.append("contentDirection") }
        if pageNumberStart != nil { mask.append("pageNumberStart") }
        if useFirstPageHeaderFooter != nil { mask.append("useFirstPageHeaderFooter") }
        if flipPageOrientation != nil { mask.append("flipPageOrientation") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "section style requires at least one style option")

        let style = DocsSectionStyle(
            marginTop: points(marginTop),
            marginBottom: points(marginBottom),
            marginLeft: points(marginLeft),
            marginRight: points(marginRight),
            marginHeader: points(marginHeader),
            marginFooter: points(marginFooter),
            columnSeparatorStyle: columnSeparatorStyle,
            contentDirection: contentDirection,
            pageNumberStart: pageNumberStart,
            useFirstPageHeaderFooter: useFirstPageHeaderFooter,
            flipPageOrientation: flipPageOrientation)
        let request = DocsBatchUpdateRequest.updateSectionStyle(
            DocsUpdateSectionStyleRequest(
                range: DocsRange(startIndex: startIndex, endIndex: endIndex),
                sectionStyle: style,
                fields: fields))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }

    /// Redefines a named style (e.g. what `HEADING_2` looks like) document-wide.
    ///
    /// `namedStyleType` selects the style (`NORMAL_TEXT`, `TITLE`, `SUBTITLE`, or
    /// `HEADING_1` through `HEADING_6`, matched case-insensitively). The text and
    /// paragraph parameters mirror `styleText` / `styleParagraphs`, and at least
    /// one of them is required (redefining a style with no change is rejected).
    /// The `fields` mask always begins with `namedStyleType` (the API requires
    /// it), then the set `textStyle.*` paths in the fixed order `bold`, `italic`,
    /// `underline`, `strikethrough`, `foregroundColor`, `backgroundColor`,
    /// `fontSize`, `weightedFontFamily`, `smallCaps`, then the set
    /// `paragraphStyle.*` paths in the fixed order `alignment`, `direction`,
    /// `lineSpacing`, `spaceAbove`, `spaceBelow`, `indentStart`, `indentEnd`,
    /// `indentFirstLine`. `tabId` optionally scopes the change to one tab.
    ///
    /// Only the text attributes and the paragraph alignment, spacing, and
    /// indents are settable here; some `NamedStyle` fields are intentionally not
    /// exposed (see the CLAUDE.md gotcha).
    public func updateNamedStyle(
        documentId: String,
        namedStyleType: String,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        foregroundColor: DocsOptionalColor? = nil,
        backgroundColor: DocsOptionalColor? = nil,
        fontSize: Double? = nil,
        fontFamily: String? = nil,
        fontWeight: Int? = nil,
        smallCaps: Bool? = nil,
        alignment: DocsParagraphAlignment? = nil,
        direction: DocsContentDirection? = nil,
        lineSpacing: Double? = nil,
        spaceAbove: Double? = nil,
        spaceBelow: Double? = nil,
        indentStart: Double? = nil,
        indentEnd: Double? = nil,
        indentFirstLine: Double? = nil,
        tabId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        guard let selector = DocsNamedStyleType(rawValue: namedStyleType.uppercased()) else {
            throw GrahamError.invalidArgument(
                "unknown named style \"\(namedStyleType)\"; use one of NORMAL_TEXT, TITLE, "
                + "SUBTITLE, or HEADING_1 through HEADING_6")
        }

        let weightedFontFamily = try Self.makeWeightedFontFamily(
            fontFamily: fontFamily, fontWeight: fontWeight)
        try Self.validateStylePositive(fontSize, label: "font size")
        try Self.validateStylePositive(lineSpacing, label: "line spacing")
        try Self.validateStyleNonNegative(spaceAbove, label: "space above")
        try Self.validateStyleNonNegative(spaceBelow, label: "space below")
        try Self.validateStyleNonNegative(indentStart, label: "indent start")
        try Self.validateStyleNonNegative(indentEnd, label: "indent end")
        try Self.validateStyleNonNegative(indentFirstLine, label: "first-line indent")

        func points(_ value: Double?) -> DocsDimension? {
            value.map { DocsDimension(magnitude: $0, unit: .pt) }
        }

        // The mask always leads with the selector, then the set text paths, then
        // the set paragraph paths — each nested under its style root.
        var mask: [String] = ["namedStyleType"]
        var textMask: [String] = []
        if bold != nil { textMask.append("textStyle.bold") }
        if italic != nil { textMask.append("textStyle.italic") }
        if underline != nil { textMask.append("textStyle.underline") }
        if strikethrough != nil { textMask.append("textStyle.strikethrough") }
        if foregroundColor != nil { textMask.append("textStyle.foregroundColor") }
        if backgroundColor != nil { textMask.append("textStyle.backgroundColor") }
        if fontSize != nil { textMask.append("textStyle.fontSize") }
        if weightedFontFamily != nil { textMask.append("textStyle.weightedFontFamily") }
        if smallCaps != nil { textMask.append("textStyle.smallCaps") }

        var paragraphMask: [String] = []
        if alignment != nil { paragraphMask.append("paragraphStyle.alignment") }
        if direction != nil { paragraphMask.append("paragraphStyle.direction") }
        if lineSpacing != nil { paragraphMask.append("paragraphStyle.lineSpacing") }
        if spaceAbove != nil { paragraphMask.append("paragraphStyle.spaceAbove") }
        if spaceBelow != nil { paragraphMask.append("paragraphStyle.spaceBelow") }
        if indentStart != nil { paragraphMask.append("paragraphStyle.indentStart") }
        if indentEnd != nil { paragraphMask.append("paragraphStyle.indentEnd") }
        if indentFirstLine != nil { paragraphMask.append("paragraphStyle.indentFirstLine") }

        guard !textMask.isEmpty || !paragraphMask.isEmpty else {
            throw GrahamError.invalidArgument(
                "named style requires at least one text or paragraph style option")
        }
        mask.append(contentsOf: textMask)
        mask.append(contentsOf: paragraphMask)

        let textStyle: DocsTextStyle? = textMask.isEmpty ? nil : DocsTextStyle(
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            fontSize: points(fontSize),
            weightedFontFamily: weightedFontFamily,
            smallCaps: smallCaps)
        let paragraphStyle: DocsParagraphStyle? = paragraphMask.isEmpty ? nil : DocsParagraphStyle(
            alignment: alignment,
            direction: direction,
            lineSpacing: lineSpacing,
            spaceAbove: points(spaceAbove),
            spaceBelow: points(spaceBelow),
            indentStart: points(indentStart),
            indentEnd: points(indentEnd),
            indentFirstLine: points(indentFirstLine))
        let request = DocsBatchUpdateRequest.updateNamedStyle(
            DocsUpdateNamedStyleRequest(
                namedStyle: DocsNamedStyle(
                    namedStyleType: selector,
                    textStyle: textStyle,
                    paragraphStyle: paragraphStyle),
                fields: mask.joined(separator: ","),
                tabId: tabId))
        return try await batchUpdate(
            documentId: documentId, requests: [request],
            requiredRevisionId: requiredRevisionId)
    }
}
