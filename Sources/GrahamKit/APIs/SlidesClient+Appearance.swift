import Foundation

extension SlidesClient {
    // MARK: - Element styles
    //
    // Every style method builds a typed style container together with a
    // deterministic field mask: one mask path per provided parameter, in a
    // fixed documented order, so the wire mask is stable and testable. At least
    // one parameter must be provided, or the method throws
    // ``GrahamError/invalidArgument(_:)`` and sends nothing. A `--no-*`
    // parameter clears a fill/outline/shadow by setting its property state to
    // `NOT_RENDERED`, and cannot be combined with any other parameter of the
    // same group. Updating a fill/outline/shadow implicitly renders it, so a
    // set never has to name `propertyState`.

    /// Styles a shape's fill, outline, shadow, and content alignment.
    ///
    /// - Parameters:
    ///   - fillColor / fillAlpha: The solid background fill. `noFill` clears it
    ///     and is mutually exclusive with a fill color or alpha.
    ///   - outlineColor / outlineAlpha / outlineWeight / outlineDash: The
    ///     border. `noOutline` clears it and is mutually exclusive with any
    ///     other outline parameter.
    ///   - shadowColor / shadowAlpha / shadowBlur / shadowOffsetX /
    ///     shadowOffsetY: The drop shadow. The offsets build a single shadow
    ///     transform (a missing axis is 0). `noShadow` clears the shadow and is
    ///     mutually exclusive with any other shadow parameter.
    ///   - contentAlignment: The vertical alignment of the shape's text.
    ///
    /// Weights and the blur are in points and must be greater than zero; every
    /// alpha must be within 0...1.
    public func styleShape(
        presentationId: String,
        objectId: String,
        fillColor: OpaqueColor? = nil,
        fillAlpha: Double? = nil,
        noFill: Bool = false,
        outlineColor: OpaqueColor? = nil,
        outlineAlpha: Double? = nil,
        outlineWeight: Double? = nil,
        outlineDash: DashStyle? = nil,
        noOutline: Bool = false,
        shadowColor: OpaqueColor? = nil,
        shadowAlpha: Double? = nil,
        shadowBlur: Double? = nil,
        shadowOffsetX: Double? = nil,
        shadowOffsetY: Double? = nil,
        noShadow: Bool = false,
        contentAlignment: ContentAlignment? = nil
    ) async throws {
        var mask: [String] = []

        // Fill group.
        var backgroundFill: ShapeBackgroundFill?
        let hasFill = fillColor != nil || fillAlpha != nil
        if noFill {
            guard !hasFill else {
                throw GrahamError.invalidArgument(
                    "no-fill cannot be combined with a fill color or alpha")
            }
            backgroundFill = ShapeBackgroundFill(propertyState: .notRendered)
            mask.append("shapeBackgroundFill.propertyState")
        } else if hasFill {
            if let fillAlpha { try Self.validateAlpha(fillAlpha, label: "fill alpha") }
            backgroundFill = ShapeBackgroundFill(
                solidFill: SolidFill(color: fillColor, alpha: fillAlpha))
            if fillColor != nil { mask.append("shapeBackgroundFill.solidFill.color") }
            if fillAlpha != nil { mask.append("shapeBackgroundFill.solidFill.alpha") }
        }

        // Outline group.
        let outline = try Self.buildOutline(
            color: outlineColor,
            alpha: outlineAlpha,
            weight: outlineWeight,
            dash: outlineDash,
            noOutline: noOutline
        )
        mask.append(contentsOf: outline.mask)

        // Shadow group.
        let shadow = try Self.buildShadow(
            color: shadowColor,
            alpha: shadowAlpha,
            blur: shadowBlur,
            offsetX: shadowOffsetX,
            offsetY: shadowOffsetY,
            noShadow: noShadow
        )
        mask.append(contentsOf: shadow.mask)

        // Content alignment.
        if contentAlignment != nil { mask.append("contentAlignment") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style shape requires at least one style option")

        let style = ShapeStyle(
            shapeBackgroundFill: backgroundFill,
            outline: outline.value,
            shadow: shadow.value,
            contentAlignment: contentAlignment
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateShapeProperties(UpdateShapePropertiesRequest(
                objectId: objectId,
                shapeProperties: style,
                fields: fields
            ))]
        )
    }

    /// Styles an image's outline. This is the only appearance the Slides API
    /// lets a write set on an image.
    ///
    /// The API exposes an image's brightness, contrast, transparency, crop,
    /// recolor, and shadow as **read-only**, so graham cannot change them; only
    /// the outline (and the link, which belongs to a later milestone) is
    /// writable. `noOutline` clears the outline and is mutually exclusive with
    /// any other outline parameter.
    public func styleImage(
        presentationId: String,
        objectId: String,
        outlineColor: OpaqueColor? = nil,
        outlineAlpha: Double? = nil,
        outlineWeight: Double? = nil,
        outlineDash: DashStyle? = nil,
        noOutline: Bool = false
    ) async throws {
        let outline = try Self.buildOutline(
            color: outlineColor,
            alpha: outlineAlpha,
            weight: outlineWeight,
            dash: outlineDash,
            noOutline: noOutline
        )
        let fields = try GrahamValidation.requireFieldMask(
            outline.mask, "style image requires at least one outline option")
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateImageProperties(UpdateImagePropertiesRequest(
                objectId: objectId,
                imageProperties: ImageStyle(outline: outline.value),
                fields: fields
            ))]
        )
    }

    /// Styles a line's fill, weight, dash style, and arrow ends.
    ///
    /// Lines have no fill property state, so there is no `--no-*` clear here.
    /// The weight is in points and must be greater than zero; the alpha must be
    /// within 0...1.
    public func styleLine(
        presentationId: String,
        objectId: String,
        color: OpaqueColor? = nil,
        alpha: Double? = nil,
        weight: Double? = nil,
        dash: DashStyle? = nil,
        startArrow: ArrowStyle? = nil,
        endArrow: ArrowStyle? = nil
    ) async throws {
        if let alpha { try Self.validateAlpha(alpha, label: "line alpha") }
        if let weight { try Self.validatePositive(weight, label: "line weight") }

        var mask: [String] = []
        var lineFill: LineFill?
        if color != nil || alpha != nil {
            lineFill = LineFill(solidFill: SolidFill(color: color, alpha: alpha))
        }
        if color != nil { mask.append("lineFill.solidFill.color") }
        if alpha != nil { mask.append("lineFill.solidFill.alpha") }
        if weight != nil { mask.append("weight") }
        if dash != nil { mask.append("dashStyle") }
        if startArrow != nil { mask.append("startArrow") }
        if endArrow != nil { mask.append("endArrow") }

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style line requires at least one style option")

        let style = LineStyle(
            lineFill: lineFill,
            weight: weight.map { ElementDimension(magnitude: $0, unit: .pt) },
            dashStyle: dash,
            startArrow: startArrow,
            endArrow: endArrow
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateLineProperties(UpdateLinePropertiesRequest(
                objectId: objectId,
                lineProperties: style,
                fields: fields
            ))]
        )
    }

    /// Styles a video's playback options and outline.
    ///
    /// `start` and `end` are whole seconds and must be 0 or greater; when both
    /// are given, `end` must be greater than `start`. The outline parameters
    /// match ``styleShape(presentationId:objectId:fillColor:fillAlpha:noFill:outlineColor:outlineAlpha:outlineWeight:outlineDash:noOutline:shadowColor:shadowAlpha:shadowBlur:shadowOffsetX:shadowOffsetY:noShadow:contentAlignment:)``.
    public func styleVideo(
        presentationId: String,
        objectId: String,
        autoPlay: Bool? = nil,
        mute: Bool? = nil,
        start: Int? = nil,
        end: Int? = nil,
        outlineColor: OpaqueColor? = nil,
        outlineAlpha: Double? = nil,
        outlineWeight: Double? = nil,
        outlineDash: DashStyle? = nil,
        noOutline: Bool = false
    ) async throws {
        if let start, start < 0 {
            throw GrahamError.invalidArgument("video start must be 0 or greater, got \(start)")
        }
        if let end, end < 0 {
            throw GrahamError.invalidArgument("video end must be 0 or greater, got \(end)")
        }
        if let start, let end, end <= start {
            throw GrahamError.invalidArgument(
                "video end (\(end)) must be greater than start (\(start))")
        }

        var mask: [String] = []
        if autoPlay != nil { mask.append("autoPlay") }
        if mute != nil { mask.append("mute") }
        if start != nil { mask.append("start") }
        if end != nil { mask.append("end") }

        let outline = try Self.buildOutline(
            color: outlineColor,
            alpha: outlineAlpha,
            weight: outlineWeight,
            dash: outlineDash,
            noOutline: noOutline
        )
        mask.append(contentsOf: outline.mask)

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style video requires at least one style option")

        let style = VideoStyle(
            autoPlay: autoPlay,
            mute: mute,
            start: start,
            end: end,
            outline: outline.value
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateVideoProperties(UpdateVideoPropertiesRequest(
                objectId: objectId,
                videoProperties: style,
                fields: fields
            ))]
        )
    }
    /// Styles cells in a one-based range, or the whole table when all four
    /// range parameters are omitted. If a range is started, `row` and
    /// `column` are required and each omitted span defaults to 1.
    public func styleTableCells(
        presentationId: String,
        tableId: String,
        row: Int? = nil,
        column: Int? = nil,
        rowSpan: Int? = nil,
        columnSpan: Int? = nil,
        fillColor: OpaqueColor? = nil,
        fillAlpha: Double? = nil,
        noFill: Bool = false,
        alignment: ContentAlignment? = nil
    ) async throws {
        let range = try Self.buildOptionalTableRange(
            row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
        let hasFill = fillColor != nil || fillAlpha != nil
        if noFill && hasFill {
            throw GrahamError.invalidArgument(
                "no-fill cannot be combined with a fill color or alpha")
        }
        if let fillAlpha { try Self.validateAlpha(fillAlpha, label: "table cell fill alpha") }

        var mask: [String] = []
        var backgroundFill: TableCellBackgroundFill?
        if hasFill {
            backgroundFill = TableCellBackgroundFill(
                solidFill: SolidFill(color: fillColor, alpha: fillAlpha))
            if fillColor != nil {
                mask.append("tableCellBackgroundFill.solidFill.color")
            }
            if fillAlpha != nil {
                mask.append("tableCellBackgroundFill.solidFill.alpha")
            }
        } else if noFill {
            backgroundFill = TableCellBackgroundFill(propertyState: .notRendered)
            mask.append("tableCellBackgroundFill.propertyState")
        }
        if alignment != nil { mask.append("contentAlignment") }
        let fields = try GrahamValidation.requireFieldMask(
            mask, "style table cells requires at least one style option")

        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateTableCellProperties(UpdateTableCellPropertiesRequest(
                objectId: tableId,
                tableRange: range,
                tableCellStyle: TableCellStyle(
                    tableCellBackgroundFill: backgroundFill,
                    contentAlignment: alignment
                ),
                fields: fields
            ))]
        )
    }

    /// Sets a positive minimum row height in points. `rows` contains
    /// one-based row numbers; an empty array updates every row.
    public func setTableRowHeight(
        presentationId: String,
        tableId: String,
        rows: [Int],
        minHeight: Double
    ) async throws {
        for row in rows { try Self.validateOneBased(row, label: "table row") }
        try Self.validatePositive(minHeight, label: "table minimum row height")
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateTableRowProperties(UpdateTableRowPropertiesRequest(
                objectId: tableId,
                rowIndices: rows.map { $0 - 1 },
                tableRowStyle: TableRowStyle(
                    minRowHeight: ElementDimension(magnitude: minHeight, unit: .pt)),
                fields: "minRowHeight"
            ))]
        )
    }

    /// Sets a table column width in points. `columns` contains one-based
    /// column numbers; an empty array updates every column. The Slides API
    /// rejects widths below 32 points (406400 EMU).
    public func setTableColumnWidth(
        presentationId: String,
        tableId: String,
        columns: [Int],
        width: Double
    ) async throws {
        for column in columns {
            try Self.validateOneBased(column, label: "table column")
        }
        try Self.validatePositive(width, label: "table column width")
        guard width >= 32 else {
            throw GrahamError.invalidArgument(
                "table column width must be at least 32 points (406400 EMU), got \(width)")
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateTableColumnProperties(UpdateTableColumnPropertiesRequest(
                objectId: tableId,
                columnIndices: columns.map { $0 - 1 },
                tableColumnStyle: TableColumnStyle(
                    columnWidth: ElementDimension(magnitude: width, unit: .pt)),
                fields: "columnWidth"
            ))]
        )
    }

    /// Styles borders in a one-based range, or the whole table when all four
    /// range parameters are omitted. If a range is started, `row` and
    /// `column` are required and each omitted span defaults to 1. Weight is in
    /// points and must be positive; alpha must be within 0...1.
    public func styleTableBorders(
        presentationId: String,
        tableId: String,
        row: Int? = nil,
        column: Int? = nil,
        rowSpan: Int? = nil,
        columnSpan: Int? = nil,
        position: TableBorderPosition = .all,
        color: OpaqueColor? = nil,
        alpha: Double? = nil,
        weight: Double? = nil,
        dash: DashStyle? = nil
    ) async throws {
        let range = try Self.buildOptionalTableRange(
            row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
        if let alpha { try Self.validateAlpha(alpha, label: "table border alpha") }
        if let weight { try Self.validatePositive(weight, label: "table border weight") }

        var mask: [String] = []
        if color != nil { mask.append("tableBorderFill.solidFill.color") }
        if alpha != nil { mask.append("tableBorderFill.solidFill.alpha") }
        if weight != nil { mask.append("weight") }
        if dash != nil { mask.append("dashStyle") }
        let fields = try GrahamValidation.requireFieldMask(
            mask, "style table borders requires at least one style option")

        let borderFill: TableBorderFill?
        if color != nil || alpha != nil {
            borderFill = TableBorderFill(solidFill: SolidFill(color: color, alpha: alpha))
        } else {
            borderFill = nil
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateTableBorderProperties(UpdateTableBorderPropertiesRequest(
                objectId: tableId,
                tableRange: range,
                borderPosition: position,
                tableBorderStyle: TableBorderStyle(
                    tableBorderFill: borderFill,
                    weight: weight.map { ElementDimension(magnitude: $0, unit: .pt) },
                    dashStyle: dash
                ),
                fields: fields
            ))]
        )
    }
    /// The outline (border) shared by ``styleShape``, ``styleImage``, and
    /// ``styleVideo``, together with its deterministic mask paths in the fixed
    /// order color, alpha, weight, dash. `noOutline` instead clears the outline
    /// with a single `outline.propertyState` path and rejects any other
    /// outline parameter.
    private static func buildOutline(
        color: OpaqueColor?,
        alpha: Double?,
        weight: Double?,
        dash: DashStyle?,
        noOutline: Bool
    ) throws -> (value: Outline?, mask: [String]) {
        let hasAny = color != nil || alpha != nil || weight != nil || dash != nil
        if noOutline {
            guard !hasAny else {
                throw GrahamError.invalidArgument(
                    "no-outline cannot be combined with other outline options")
            }
            return (Outline(propertyState: .notRendered), ["outline.propertyState"])
        }
        guard hasAny else { return (nil, []) }

        if let alpha { try validateAlpha(alpha, label: "outline alpha") }
        if let weight { try validatePositive(weight, label: "outline weight") }

        var mask: [String] = []
        let outlineFill: OutlineFill?
        if color != nil || alpha != nil {
            outlineFill = OutlineFill(solidFill: SolidFill(color: color, alpha: alpha))
        } else {
            outlineFill = nil
        }
        if color != nil { mask.append("outline.outlineFill.solidFill.color") }
        if alpha != nil { mask.append("outline.outlineFill.solidFill.alpha") }
        if weight != nil { mask.append("outline.weight") }
        if dash != nil { mask.append("outline.dashStyle") }

        let outline = Outline(
            outlineFill: outlineFill,
            weight: weight.map { ElementDimension(magnitude: $0, unit: .pt) },
            dashStyle: dash
        )
        return (outline, mask)
    }

    /// The drop shadow used by ``styleShape``, together with its deterministic
    /// mask paths in the fixed order color, alpha, blurRadius, transform. The
    /// offsets build one shadow transform (scale 1, no shear, a missing axis is
    /// 0). `noShadow` instead clears the shadow with a single
    /// `shadow.propertyState` path and rejects any other shadow parameter.
    private static func buildShadow(
        color: OpaqueColor?,
        alpha: Double?,
        blur: Double?,
        offsetX: Double?,
        offsetY: Double?,
        noShadow: Bool
    ) throws -> (value: Shadow?, mask: [String]) {
        let hasOffset = offsetX != nil || offsetY != nil
        let hasAny = color != nil || alpha != nil || blur != nil || hasOffset
        if noShadow {
            guard !hasAny else {
                throw GrahamError.invalidArgument(
                    "no-shadow cannot be combined with other shadow options")
            }
            return (Shadow(propertyState: .notRendered), ["shadow.propertyState"])
        }
        guard hasAny else { return (nil, []) }

        if let alpha { try validateAlpha(alpha, label: "shadow alpha") }
        if let blur { try validatePositive(blur, label: "shadow blur") }

        var mask: [String] = []
        if color != nil { mask.append("shadow.color") }
        if alpha != nil { mask.append("shadow.alpha") }
        if blur != nil { mask.append("shadow.blurRadius") }
        var transform: ElementTransform?
        if hasOffset {
            transform = ElementTransform(
                scaleX: 1,
                scaleY: 1,
                shearX: 0,
                shearY: 0,
                translateX: offsetX ?? 0,
                translateY: offsetY ?? 0,
                unit: .pt
            )
            mask.append("shadow.transform")
        }

        let shadow = Shadow(
            color: color,
            alpha: alpha,
            blurRadius: blur.map { ElementDimension(magnitude: $0, unit: .pt) },
            transform: transform
        )
        return (shadow, mask)
    }

    /// Builds a required one-based range and translates its location to the
    /// API's zero-based wire convention.
    static func buildTableRange(
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int
    ) throws -> TableRange {
        guard let range = try buildOptionalTableRange(
            row: row,
            column: column,
            rowSpan: rowSpan,
            columnSpan: columnSpan
        ) else {
            throw GrahamError.invalidArgument("a table range is required")
        }
        return range
    }

    /// Builds the optional range group shared by table-cell and table-border
    /// styling. All four omitted means the whole table; otherwise row and
    /// column are required and omitted spans default to one.
    private static func buildOptionalTableRange(
        row: Int?,
        column: Int?,
        rowSpan: Int?,
        columnSpan: Int?
    ) throws -> TableRange? {
        let hasAny = row != nil || column != nil || rowSpan != nil || columnSpan != nil
        guard hasAny else { return nil }
        guard let row, let column else {
            throw GrahamError.invalidArgument(
                "table range requires both a one-based row and column")
        }
        let resolvedRowSpan = rowSpan ?? 1
        let resolvedColumnSpan = columnSpan ?? 1
        try validateOneBased(row, label: "table row")
        try validateOneBased(column, label: "table column")
        try validateOneBased(resolvedRowSpan, label: "table row span")
        try validateOneBased(resolvedColumnSpan, label: "table column span")
        return TableRange(
            location: TableCellLocation(
                rowIndex: row - 1,
                columnIndex: column - 1
            ),
            rowSpan: resolvedRowSpan,
            columnSpan: resolvedColumnSpan
        )
    }

    /// Throws unless an index or span is at least one.
    static func validateOneBased(_ value: Int, label: String) throws {
        guard value >= 1 else {
            throw GrahamError.invalidArgument(
                "\(label) must be one-based (1 or greater), got \(value)")
        }
    }

    /// Throws ``GrahamError/invalidArgument(_:)`` unless `alpha` is within
    /// 0...1.
    static func validateAlpha(_ alpha: Double, label: String) throws {
        guard (0...1).contains(alpha) else {
            throw GrahamError.invalidArgument(
                "\(label) must be within 0 and 1, got \(alpha)")
        }
    }

    /// Throws ``GrahamError/invalidArgument(_:)`` unless `value` is greater
    /// than zero.
    static func validatePositive(_ value: Double, label: String) throws {
        guard value.isFinite, value > 0 else {
            throw GrahamError.invalidArgument(
                "\(label) must be greater than zero, got \(value)")
        }
    }

    /// Throws ``GrahamError/invalidArgument(_:)`` unless `value` is 0 or
    /// greater. Used for point measurements that may legitimately be zero.
    static func validateNonNegative(_ value: Double, label: String) throws {
        guard value >= 0 else {
            throw GrahamError.invalidArgument(
                "\(label) must be 0 or greater, got \(value)")
        }
    }
}
