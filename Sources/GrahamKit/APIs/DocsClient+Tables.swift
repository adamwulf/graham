import Foundation

extension DocsClient {
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

        let fields = try GrahamValidation.requireFieldMask(
            mask, "style table cells requires at least one style option")

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

    /// Sets the row style of the listed rows, or every row: minimum height and
    /// overflow behavior.
    ///
    /// - Parameters:
    ///   - tableStartIndex: the table's zero-based UTF-16 start index.
    ///   - rows: the one-based rows to style; each is translated to a zero-based
    ///     API index. An empty list styles every row (encoded as no
    ///     `rowIndices`).
    ///   - minRowHeight: the minimum row height in points; must be greater than
    ///     zero.
    ///   - preventOverflow: keep each row's content from spilling across a page
    ///     break.
    ///   - segmentId: a header, footer, or footnote segment; nil or an empty
    ///     string targets the body.
    ///
    /// The `fields` mask is emitted in the fixed order `minRowHeight`,
    /// `preventOverflow`. At least one style option is required. There is no
    /// header flag: `updateTableRowStyle` rejects `tableHeader` because header
    /// designation is read-only after a table exists; pin leading rows with
    /// ``pinTableHeaderRows(documentId:tableStartIndex:pinnedHeaderRowsCount:segmentId:requiredRevisionId:)``
    /// instead.
    public func styleTableRow(
        documentId: String,
        tableStartIndex: Int,
        rows: [Int] = [],
        minRowHeight: Double? = nil,
        preventOverflow: Bool? = nil,
        segmentId: String? = nil,
        requiredRevisionId: String? = nil
    ) async throws -> DocsBatchUpdateResponse {
        try Self.validateStylePositive(minRowHeight, label: "minimum row height")
        var mask: [String] = []
        if minRowHeight != nil { mask.append("minRowHeight") }
        if preventOverflow != nil { mask.append("preventOverflow") }
        let fields = try GrahamValidation.requireFieldMask(
            mask, "style table row requires at least one style option")

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
            preventOverflow: preventOverflow)
        let request = DocsUpdateTableRowStyleRequest(
            tableStartLocation: start, rowIndices: rowIndices,
            tableRowStyle: style, fields: fields)
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
}
