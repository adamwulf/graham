import Foundation

extension SlidesClient {
    /// Inserts text into a text-bearing page element, or a table cell.
    ///
    /// `insertionIndex` is a zero-based UTF-16 code-unit offset into the target
    /// text. To insert into a table cell, pass both a one-based `row` and
    /// `column`; the client translates them to the API's zero-based cell
    /// location. Empty text is a no-op and sends no network request.
    public func insertText(
        presentationId: String,
        objectId: String,
        text: String,
        insertionIndex: Int = 0,
        row: Int? = nil,
        column: Int? = nil
    ) async throws {
        guard !text.isEmpty else { return }
        let cellLocation = try Self.cellLocation(row: row, column: column)
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.insertText(InsertTextRequest(
                objectId: objectId,
                text: text,
                insertionIndex: insertionIndex,
                cellLocation: cellLocation
            ))]
        )
    }
    // MARK: - Speaker notes
    //
    // A slide's notes live in a shape on its read-only notes page, named by
    // `slideProperties.notesPage.notesProperties.speakerNotesObjectId`. Notes
    // are read from that page and edited through the ordinary text operations
    // against that shape id, in the same `presentations.batchUpdate` as any
    // other write. The shape may not exist on the notes page until text is
    // first inserted; inserting text with its id creates it.

    /// The mask that limits a notes read to the slide id and its notes page.
    private static let speakerNotesFields = "slides.objectId,slides.slideProperties.notesPage"

    /// Reads every slide's speaker notes, one row per slide.
    ///
    /// This is a single `presentations.get`, masked to the slide ids and their
    /// notes pages. The notes shape id and text come from each slide's
    /// `slideProperties.notesPage`; see ``Presentation/speakerNotesRows``.
    public func speakerNotes(presentationId: String) async throws -> [SlideSpeakerNotesRow] {
        let presentation = try await self.presentation(
            id: presentationId, fields: Self.speakerNotesFields)
        return presentation.speakerNotesRows
    }

    /// Sets one slide's speaker notes to `text`, replacing any existing notes.
    ///
    /// This first reads the presentation to find the slide and its speaker-notes
    /// shape id, then sends ONE atomic batch built from the current state: a
    /// `deleteText(.all)` only when the notes shape currently has text, plus an
    /// `insertText` only when `text` is non-empty. Setting empty text on an
    /// already-empty shape sends no write (the no-op precedent of
    /// ``moveSlide(presentationId:slideId:to:)``).
    ///
    /// Throws ``GrahamError/invalidArgument(_:)`` when no slide has `slideId`
    /// (before any write) and ``GrahamError/invalidResponse(_:)`` when the API
    /// returns no speaker-notes shape id for the slide.
    public func setSpeakerNotes(
        presentationId: String,
        slideId: String,
        text: String
    ) async throws {
        let presentation = try await self.presentation(
            id: presentationId, fields: Self.speakerNotesFields)
        guard let slide = (presentation.slides ?? []).first(where: { $0.objectId == slideId })
        else {
            throw GrahamError.invalidArgument(
                "no slide with id \"\(slideId)\" in presentation \(presentationId)")
        }
        let notesPage = slide.slideProperties?.notesPage
        guard let shapeId = notesPage?.notesProperties?.speakerNotesObjectId else {
            throw GrahamError.invalidResponse(
                "slide \"\(slideId)\" has no speaker-notes shape id in its notes page")
        }
        let currentText = Presentation.speakerNotesText(notesPage: notesPage, shapeId: shapeId)

        var requests: [SlidesBatchUpdateRequest] = []
        if !currentText.isEmpty {
            requests.append(.deleteText(DeleteTextRequest(objectId: shapeId, textRange: .all)))
        }
        if !text.isEmpty {
            requests.append(.insertText(InsertTextRequest(
                objectId: shapeId, text: text, insertionIndex: 0)))
        }
        // Empty text on an already-empty shape has nothing to do.
        guard !requests.isEmpty else { return }
        _ = try await batchUpdate(presentationId: presentationId, requests: requests)
    }

    /// Clears one slide's speaker notes. This is ``setSpeakerNotes`` with empty
    /// text, so an already-empty shape sends no write.
    public func clearSpeakerNotes(presentationId: String, slideId: String) async throws {
        try await setSpeakerNotes(presentationId: presentationId, slideId: slideId, text: "")
    }
    // MARK: - Text and paragraphs
    //
    // These edit the text inside a shape or table cell. Text indices are
    // zero-based UTF-16 code units (matching `insertText`'s insertion index);
    // a shape's or cell's text always ends in an implicit trailing newline that
    // a fixed range may not always be allowed to touch, so Google can reject
    // some ranges. Table cells are addressed with a one-based row and column,
    // per repo convention, and translated to the API's zero-based location.
    // Every style method builds a deterministic field mask: one path per
    // provided parameter, in a fixed documented order, and requires at least
    // one parameter or it throws ``GrahamError/invalidArgument(_:)`` and sends
    // nothing.

    /// Deletes a range of text from a shape or table cell.
    ///
    /// `from` and `to` are zero-based UTF-16 code-unit offsets. With no range
    /// (both `nil`) the whole text is deleted. Because the text always ends in
    /// an implicit trailing newline that a fixed range may not be allowed to
    /// include, Google can reject some `from`/`to` ranges. Pass both a
    /// one-based `row` and `column` to target a table cell.
    public func deleteText(
        presentationId: String,
        objectId: String,
        from: Int? = nil,
        to: Int? = nil,
        row: Int? = nil,
        column: Int? = nil
    ) async throws {
        let cellLocation = try Self.cellLocation(row: row, column: column)
        let range = try Self.textRange(from: from, to: to)
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.deleteText(DeleteTextRequest(
                objectId: objectId,
                cellLocation: cellLocation,
                textRange: range
            ))]
        )
    }

    /// Styles a range of text, and sets or clears its link.
    ///
    /// - Parameters:
    ///   - from / to: The zero-based UTF-16 text range; omit both for the whole
    ///     text.
    ///   - row / column: A one-based table cell, or omit both for a shape.
    ///   - bold...smallCaps: Optional boolean styles; `nil` leaves each unchanged.
    ///   - color: The foreground color, sent as a solid ``OptionalColor``.
    ///   - background / transparentBackground: The background color. They are
    ///     mutually exclusive; `transparentBackground` sends an empty
    ///     ``OptionalColor``, which the API reads as transparent.
    ///   - fontFamily / fontWeight: The font. A `fontWeight` must be a multiple
    ///     of 100 within 100...900 and requires a `fontFamily`; both are written
    ///     to `weightedFontFamily`, and `fontFamily` is also written to the
    ///     plain field, so the two stay consistent.
    ///   - fontSize: The point size; must be greater than zero.
    ///   - baseline: The baseline offset (superscript/subscript, or none).
    ///   - link / clearLink: The run's link. They are mutually exclusive;
    ///     `clearLink` adds the `link` mask path with no link value, which
    ///     clears any existing link.
    ///
    /// The field mask is emitted in the fixed order `bold`, `italic`,
    /// `underline`, `strikethrough`, `smallCaps`, `foregroundColor`,
    /// `backgroundColor`, `fontFamily`, `weightedFontFamily`, `fontSize`,
    /// `baselineOffset`, `link`. At least one style parameter is required.
    public func styleText(
        presentationId: String,
        objectId: String,
        from: Int? = nil,
        to: Int? = nil,
        row: Int? = nil,
        column: Int? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        smallCaps: Bool? = nil,
        color: OpaqueColor? = nil,
        background: OpaqueColor? = nil,
        transparentBackground: Bool = false,
        fontFamily: String? = nil,
        fontWeight: Int? = nil,
        fontSize: Double? = nil,
        baseline: BaselineOffset? = nil,
        link: TextLinkTarget? = nil,
        clearLink: Bool = false
    ) async throws {
        let cellLocation = try Self.cellLocation(row: row, column: column)
        let range = try Self.textRange(from: from, to: to)

        if background != nil && transparentBackground {
            throw GrahamError.invalidArgument(
                "a background color cannot be combined with a transparent background")
        }
        if link != nil && clearLink {
            throw GrahamError.invalidArgument(
                "a link cannot be combined with clear-link")
        }

        // Weighted font family: a weight is a multiple of 100 in 100...900 and
        // requires a family. Setting the plain `fontFamily` too keeps the two
        // consistent, as the API requires when both are present.
        var weightedFontFamily: WeightedFontFamily?
        if let fontWeight {
            guard let fontFamily else {
                throw GrahamError.invalidArgument("a font weight requires a font family")
            }
            guard (100...900).contains(fontWeight), fontWeight % 100 == 0 else {
                throw GrahamError.invalidArgument(
                    "font weight must be a multiple of 100 within 100 and 900, got \(fontWeight)")
            }
            weightedFontFamily = WeightedFontFamily(fontFamily: fontFamily, weight: fontWeight)
        }

        if let fontSize { try Self.validatePositive(fontSize, label: "font size") }

        let foregroundColor = color.map { OptionalColor(opaqueColor: $0) }
        let backgroundColor: OptionalColor?
        if transparentBackground {
            backgroundColor = OptionalColor()
        } else {
            backgroundColor = background.map { OptionalColor(opaqueColor: $0) }
        }

        let resolvedLink = try link.map { try Self.makeLink($0) }

        var mask: [String] = []
        if bold != nil { mask.append("bold") }
        if italic != nil { mask.append("italic") }
        if underline != nil { mask.append("underline") }
        if strikethrough != nil { mask.append("strikethrough") }
        if smallCaps != nil { mask.append("smallCaps") }
        if foregroundColor != nil { mask.append("foregroundColor") }
        if backgroundColor != nil { mask.append("backgroundColor") }
        if fontFamily != nil { mask.append("fontFamily") }
        if weightedFontFamily != nil { mask.append("weightedFontFamily") }
        if fontSize != nil { mask.append("fontSize") }
        if baseline != nil { mask.append("baselineOffset") }
        if resolvedLink != nil || clearLink { mask.append("link") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style text requires at least one style option")

        let style = TextStyleValue(
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            smallCaps: smallCaps,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            fontFamily: fontFamily,
            weightedFontFamily: weightedFontFamily,
            fontSize: fontSize.map { ElementDimension(magnitude: $0, unit: .pt) },
            baselineOffset: baseline,
            link: resolvedLink
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateTextStyle(UpdateTextStyleRequest(
                objectId: objectId,
                cellLocation: cellLocation,
                style: style,
                textRange: range,
                fields: fields
            ))]
        )
    }

    /// Styles the paragraphs that a text range touches.
    ///
    /// - Parameters:
    ///   - from / to: The zero-based UTF-16 text range; omit both for the whole
    ///     text.
    ///   - row / column: A one-based table cell, or omit both for a shape.
    ///   - alignment: The horizontal paragraph alignment.
    ///   - lineSpacing: A percent of normal (100 = normal); must be greater
    ///     than zero.
    ///   - spaceAbove / spaceBelow / indentStart / indentEnd / indentFirstLine:
    ///     Point measurements; each must be 0 or greater.
    ///   - direction: The reading direction.
    ///   - spacingMode: Whether spacing collapses between list items.
    ///
    /// The field mask is emitted in the fixed order `alignment`, `lineSpacing`,
    /// `spaceAbove`, `spaceBelow`, `indentStart`, `indentEnd`,
    /// `indentFirstLine`, `direction`, `spacingMode`. At least one parameter is
    /// required.
    public func styleParagraphs(
        presentationId: String,
        objectId: String,
        from: Int? = nil,
        to: Int? = nil,
        row: Int? = nil,
        column: Int? = nil,
        alignment: ParagraphAlignment? = nil,
        lineSpacing: Double? = nil,
        spaceAbove: Double? = nil,
        spaceBelow: Double? = nil,
        indentStart: Double? = nil,
        indentEnd: Double? = nil,
        indentFirstLine: Double? = nil,
        direction: TextDirection? = nil,
        spacingMode: SpacingMode? = nil
    ) async throws {
        let cellLocation = try Self.cellLocation(row: row, column: column)
        let range = try Self.textRange(from: from, to: to)

        if let lineSpacing { try Self.validatePositive(lineSpacing, label: "line spacing") }
        if let spaceAbove { try Self.validateNonNegative(spaceAbove, label: "space above") }
        if let spaceBelow { try Self.validateNonNegative(spaceBelow, label: "space below") }
        if let indentStart { try Self.validateNonNegative(indentStart, label: "indent start") }
        if let indentEnd { try Self.validateNonNegative(indentEnd, label: "indent end") }
        if let indentFirstLine {
            try Self.validateNonNegative(indentFirstLine, label: "first-line indent")
        }

        var mask: [String] = []
        if alignment != nil { mask.append("alignment") }
        if lineSpacing != nil { mask.append("lineSpacing") }
        if spaceAbove != nil { mask.append("spaceAbove") }
        if spaceBelow != nil { mask.append("spaceBelow") }
        if indentStart != nil { mask.append("indentStart") }
        if indentEnd != nil { mask.append("indentEnd") }
        if indentFirstLine != nil { mask.append("indentFirstLine") }
        if direction != nil { mask.append("direction") }
        if spacingMode != nil { mask.append("spacingMode") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style paragraphs requires at least one style option")

        func points(_ value: Double?) -> ElementDimension? {
            value.map { ElementDimension(magnitude: $0, unit: .pt) }
        }
        let style = ParagraphStyleValue(
            alignment: alignment,
            lineSpacing: lineSpacing,
            spaceAbove: points(spaceAbove),
            spaceBelow: points(spaceBelow),
            indentStart: points(indentStart),
            indentEnd: points(indentEnd),
            indentFirstLine: points(indentFirstLine),
            direction: direction,
            spacingMode: spacingMode
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateParagraphStyle(UpdateParagraphStyleRequest(
                objectId: objectId,
                cellLocation: cellLocation,
                style: style,
                textRange: range,
                fields: fields
            ))]
        )
    }

    /// Turns the paragraphs a text range touches into a bulleted list.
    ///
    /// `preset` chooses the bullet glyphs; `nil` uses the API default,
    /// `BULLET_DISC_CIRCLE_SQUARE`. Pass both a one-based `row` and `column` to
    /// target a table cell.
    public func createBullets(
        presentationId: String,
        objectId: String,
        from: Int? = nil,
        to: Int? = nil,
        row: Int? = nil,
        column: Int? = nil,
        preset: BulletPreset? = nil
    ) async throws {
        let cellLocation = try Self.cellLocation(row: row, column: column)
        let range = try Self.textRange(from: from, to: to)
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createParagraphBullets(CreateParagraphBulletsRequest(
                objectId: objectId,
                cellLocation: cellLocation,
                textRange: range,
                bulletPreset: preset
            ))]
        )
    }

    /// Removes bullets from the paragraphs a text range touches.
    ///
    /// Pass both a one-based `row` and `column` to target a table cell.
    public func deleteBullets(
        presentationId: String,
        objectId: String,
        from: Int? = nil,
        to: Int? = nil,
        row: Int? = nil,
        column: Int? = nil
    ) async throws {
        let cellLocation = try Self.cellLocation(row: row, column: column)
        let range = try Self.textRange(from: from, to: to)
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.deleteParagraphBullets(DeleteParagraphBulletsRequest(
                objectId: objectId,
                cellLocation: cellLocation,
                textRange: range
            ))]
        )
    }
    /// Builds a zero-based ``TextRange`` from optional bounds.
    ///
    /// Both `nil` selects the whole text; a `from` alone selects to the end; a
    /// `from` and `to` select the half-open `[from, to)` range. A `to` without
    /// a `from` is rejected, as is a negative `from` or a `to` not greater than
    /// `from`.
    private static func textRange(from: Int?, to: Int?) throws -> TextRange {
        switch (from, to) {
        case (nil, nil):
            return .all
        case (nil, .some):
            throw GrahamError.invalidArgument("a text range end requires a start index")
        case (.some(let start), nil):
            guard start >= 0 else {
                throw GrahamError.invalidArgument(
                    "text start index must be 0 or greater, got \(start)")
            }
            return .fromIndex(start)
        case (.some(let start), .some(let end)):
            guard start >= 0 else {
                throw GrahamError.invalidArgument(
                    "text start index must be 0 or greater, got \(start)")
            }
            guard end > start else {
                throw GrahamError.invalidArgument(
                    "text end index (\(end)) must be greater than the start index (\(start))")
            }
            return .fixed(start: start, end: end)
        }
    }

    /// Translates a one-based table-cell target to the API's zero-based
    /// ``TableCellLocation``.
    ///
    /// Both `nil` targets a shape (no cell). Both set (one-based, 1 or greater)
    /// give a zero-based location. One without the other is rejected.
    private static func cellLocation(row: Int?, column: Int?) throws -> TableCellLocation? {
        switch (row, column) {
        case (nil, nil):
            return nil
        case (.some(let row), .some(let column)):
            try validateOneBased(row, label: "table row")
            try validateOneBased(column, label: "table column")
            return TableCellLocation(rowIndex: row - 1, columnIndex: column - 1)
        default:
            throw GrahamError.invalidArgument(
                "a table cell requires both a one-based row and column")
        }
    }

    /// Translates a ``TextLinkTarget`` into a wire ``Link``, converting a
    /// one-based slide position into the API's zero-based `slideIndex`.
    private static func makeLink(_ target: TextLinkTarget) throws -> Link {
        switch target {
        case .url(let url):
            return Link(url: url)
        case .slide(let position):
            try validateOneBased(position, label: "link slide position")
            return Link(slideIndex: position - 1)
        case .page(let objectId):
            return Link(pageObjectId: objectId)
        case .relative(let relative):
            return Link(relativeLink: relative)
        }
    }
}
