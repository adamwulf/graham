import Foundation

extension DocsClient {
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
        tabId: String? = nil,
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
                endOfSegmentLocation: DocsEndOfSegmentLocation(segmentId: segmentId, tabId: tabId)
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
                location: DocsLocation(index: index, segmentId: segmentId, tabId: tabId)
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
        tabId: String? = nil,
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
            range: DocsRange(
                startIndex: startIndex, endIndex: endIndex, segmentId: segmentId, tabId: tabId)
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
        tabIds: [String] = [],
        requiredRevisionId: String? = nil
    ) async throws -> Int {
        guard !find.isEmpty else {
            throw GrahamError.invalidArgument("the text to find must not be empty")
        }
        let request = DocsBatchUpdateRequest.replaceAllText(DocsReplaceAllTextRequest(
            replaceText: replace,
            containsText: DocsSubstringMatchCriteria(text: find, matchCase: matchCase),
            tabsCriteria: tabIds.isEmpty ? nil : DocsTabsCriteria(tabIds: tabIds)
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
    static func makeStyleRange(
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

    /// Validates and builds the weighted font value shared by text runs and
    /// named styles.
    static func makeWeightedFontFamily(
        fontFamily: String?, fontWeight: Int?
    ) throws -> DocsWeightedFontFamily? {
        if let fontFamily {
            guard !fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrahamError.invalidArgument("font family must not be empty")
            }
            if let fontWeight {
                guard (100...900).contains(fontWeight), fontWeight % 100 == 0 else {
                    throw GrahamError.invalidArgument(
                        "font weight must be a multiple of 100 within 100 and 900, got \(fontWeight)")
                }
            }
            return DocsWeightedFontFamily(fontFamily: fontFamily, weight: fontWeight)
        }
        guard fontWeight == nil else {
            throw GrahamError.invalidArgument("a font weight requires a font family")
        }
        return nil
    }

    /// Validates a positive style measurement. The established message stays
    /// unchanged while the finite check consistently rejects NaN and infinity.
    static func validateStylePositive(_ value: Double?, label: String) throws {
        if let value, !(value.isFinite && value > 0) {
            throw GrahamError.invalidArgument(
                "\(label) must be greater than zero, got \(value)")
        }
    }

    /// Validates a style measurement for which zero is meaningful.
    static func validateStyleNonNegative(_ value: Double?, label: String) throws {
        if let value, value < 0 {
            throw GrahamError.invalidArgument("\(label) must be 0 or greater, got \(value)")
        }
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
    ///   - smallCaps: render the text in small capital letters.
    ///
    /// The `fields` mask is emitted in the fixed order `bold`, `italic`,
    /// `underline`, `strikethrough`, `foregroundColor`, `backgroundColor`,
    /// `fontSize`, `weightedFontFamily`, `baselineOffset`, `link`, `smallCaps`.
    /// At least one style parameter is required.
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
        smallCaps: Bool? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        let range = try Self.makeStyleRange(
            startIndex: startIndex, endIndex: endIndex, segmentId: segmentId)

        let weightedFontFamily = try Self.makeWeightedFontFamily(
            fontFamily: fontFamily, fontWeight: fontWeight)
        try Self.validateStylePositive(fontSize, label: "font size")

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
        if smallCaps != nil { mask.append("smallCaps") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style text requires at least one style option")

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
            link: link,
            smallCaps: smallCaps
        )
        let request = DocsBatchUpdateRequest.updateTextStyle(DocsUpdateTextStyleRequest(
            textStyle: style, fields: fields, range: range))
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
    ///   - keepLinesTogether / keepWithNext / avoidWidowAndOrphan /
    ///     pageBreakBefore: the pagination toggles; nil leaves each unchanged.
    ///   - shadingBackgroundColor: the paragraph background fill, already parsed
    ///     to a ``DocsOptionalColor``; wrapped into a ``DocsShading``.
    ///   - spacingMode: how the space-above/below collapse (never or lists).
    ///   - outerBorderColor: the color of the four outer paragraph borders (top,
    ///     bottom, left, right), already parsed to a ``DocsOptionalColor``. A
    ///     single color fans to all four sides. A border is set only when a color
    ///     is given; a `borderWidth`, `borderDash`, or `borderPadding` with no
    ///     `outerBorderColor` and no `betweenBorderColor` is rejected.
    ///   - betweenBorderColor: the color of the between-paragraph border, already
    ///     parsed to a ``DocsOptionalColor``.
    ///   - borderWidth: the border width in points, shared by the outer and
    ///     between borders (defaults to 1); must be finite and not negative. A
    ///     width of 0 hides the border.
    ///   - borderDash: the border dash style shared by both borders (defaults to
    ///     solid).
    ///   - borderPadding: the border padding in points shared by both borders
    ///     (defaults to 0); must be finite and not negative.
    ///
    /// The `fields` mask is emitted in the fixed order `namedStyleType`,
    /// `alignment`, `direction`, `lineSpacing`, `spaceAbove`, `spaceBelow`,
    /// `indentStart`, `indentEnd`, `indentFirstLine`, `keepLinesTogether`,
    /// `keepWithNext`, `avoidWidowAndOrphan`, `pageBreakBefore`, `shading`,
    /// `spacingMode`, `borderTop`, `borderBottom`, `borderLeft`, `borderRight`,
    /// `borderBetween` — the border paths are appended last, so a caller that
    /// sets no border produces exactly the same mask as before. Each set border
    /// encodes a full ``DocsParagraphBorder`` (color, width, padding, dash),
    /// because the Docs API forbids a partial paragraph-border update. At least
    /// one parameter is required. Tab stops are out of scope because
    /// `ParagraphStyle.tabStops` is read-only in the Docs API.
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
        keepLinesTogether: Bool? = nil,
        keepWithNext: Bool? = nil,
        avoidWidowAndOrphan: Bool? = nil,
        pageBreakBefore: Bool? = nil,
        shadingBackgroundColor: DocsOptionalColor? = nil,
        spacingMode: DocsSpacingMode? = nil,
        outerBorderColor: DocsOptionalColor? = nil,
        betweenBorderColor: DocsOptionalColor? = nil,
        borderWidth: Double? = nil,
        borderDash: DocsDashStyle? = nil,
        borderPadding: Double? = nil,
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

        try Self.validateStylePositive(lineSpacing, label: "line spacing")
        try Self.validateStyleNonNegative(spaceAbove, label: "space above")
        try Self.validateStyleNonNegative(spaceBelow, label: "space below")
        try Self.validateStyleNonNegative(indentStart, label: "indent start")
        try Self.validateStyleNonNegative(indentEnd, label: "indent end")
        try Self.validateStyleNonNegative(indentFirstLine, label: "first-line indent")

        let shading = shadingBackgroundColor.map { DocsShading(backgroundColor: $0) }

        // Paragraph borders. A full border requires a color, so a width, dash,
        // or padding with neither an outer nor a between color has nothing to
        // attach to. The width, dash, and padding are shared by both borders; the
        // Docs API forbids a partial border update, so each set border carries a
        // complete ``DocsParagraphBorder``.
        let hasBorderColor = outerBorderColor != nil || betweenBorderColor != nil
        if !hasBorderColor, borderWidth != nil || borderDash != nil || borderPadding != nil {
            throw GrahamError.invalidArgument(
                "a paragraph border requires a color; set an outer or between border color "
                + "to set its width, dash, or padding")
        }
        var outerBorder: DocsParagraphBorder?
        var betweenBorder: DocsParagraphBorder?
        if hasBorderColor {
            let width = borderWidth ?? 1
            // A width of 0 hides the border (border removal), so 0 is valid; only
            // a negative or non-finite width is invalid.
            guard width.isFinite, width >= 0 else {
                throw GrahamError.invalidArgument(
                    "border width must be finite and not negative, got \(width)")
            }
            let padding = borderPadding ?? 0
            // A padding of 0 is valid (no padding); only a negative or non-finite
            // padding is invalid.
            guard padding.isFinite, padding >= 0 else {
                throw GrahamError.invalidArgument(
                    "border padding must be finite and not negative, got \(padding)")
            }
            let dash = borderDash ?? .solid
            func makeBorder(_ color: DocsOptionalColor) -> DocsParagraphBorder {
                DocsParagraphBorder(
                    color: color,
                    width: DocsDimension(magnitude: width, unit: .pt),
                    padding: DocsDimension(magnitude: padding, unit: .pt),
                    dashStyle: dash)
            }
            outerBorder = outerBorderColor.map(makeBorder)
            betweenBorder = betweenBorderColor.map(makeBorder)
        }

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
        if keepLinesTogether != nil { mask.append("keepLinesTogether") }
        if keepWithNext != nil { mask.append("keepWithNext") }
        if avoidWidowAndOrphan != nil { mask.append("avoidWidowAndOrphan") }
        if pageBreakBefore != nil { mask.append("pageBreakBefore") }
        if shading != nil { mask.append("shading") }
        if spacingMode != nil { mask.append("spacingMode") }
        // The border paths are appended last, in a fixed order, so a caller that
        // sets no border produces exactly the same mask as before.
        if outerBorder != nil {
            mask.append(contentsOf: ["borderTop", "borderBottom", "borderLeft", "borderRight"])
        }
        if betweenBorder != nil { mask.append("borderBetween") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style paragraphs requires at least one style option")

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
            indentFirstLine: points(indentFirstLine),
            keepLinesTogether: keepLinesTogether,
            keepWithNext: keepWithNext,
            avoidWidowAndOrphan: avoidWidowAndOrphan,
            pageBreakBefore: pageBreakBefore,
            shading: shading,
            spacingMode: spacingMode,
            borderTop: outerBorder,
            borderBottom: outerBorder,
            borderLeft: outerBorder,
            borderRight: outerBorder,
            borderBetween: betweenBorder
        )
        let request = DocsBatchUpdateRequest.updateParagraphStyle(DocsUpdateParagraphStyleRequest(
            paragraphStyle: style, fields: fields, range: range))
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
}
