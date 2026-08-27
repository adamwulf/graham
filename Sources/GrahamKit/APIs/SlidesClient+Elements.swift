import Foundation

extension SlidesClient {
    /// Creates one slide and returns the new slide's object id.
    ///
    /// - Parameters:
    ///   - presentationId: The presentation to add the slide to.
    ///   - position: The one-based final position of the new slide, matching
    ///     the slide numbers that `slides cat` and `slides list` print. `nil`
    ///     appends the slide at the end. Only the lower bound is checked here;
    ///     the upper bound is left to Google, so an add stays a single write
    ///     with no extra read of the deck.
    ///   - layout: A predefined layout name, for example `BLANK` or
    ///     `TITLE_AND_BODY`. The name is normalized (trimmed, uppercased, `-`
    ///     and spaces become `_`), so `title-and-body` also works. Google
    ///     rejects a name it does not know. `nil` means unspecified: with no
    ///     `layoutId` either, the slide defaults to the `BLANK` predefined
    ///     layout.
    ///   - layoutId: The object id of a layout in the presentation (from
    ///     ``Presentation/layoutRows``). Mutually exclusive with `layout`:
    ///     providing both throws ``GrahamError/invalidArgument(_:)``.
    public func createSlide(
        presentationId: String,
        at position: Int? = nil,
        layout: String? = nil,
        layoutId: String? = nil
    ) async throws -> String {
        if let position, position < 1 {
            throw GrahamError.invalidArgument(
                "slide position must be 1 or greater, got \(position)")
        }
        // Exclusivity is checked on what the caller actually provided, so the
        // BLANK default (applied only when neither is given) never collides.
        if layout != nil && layoutId != nil {
            throw GrahamError.invalidArgument(
                "a slide cannot take both a layout name and a layout id")
        }
        let layoutReference: SlideLayoutReference
        if let layoutId {
            layoutReference = SlideLayoutReference(layoutId: layoutId)
        } else {
            let normalized = Self.normalizeLayout(layout ?? "BLANK")
            guard !normalized.isEmpty else {
                throw GrahamError.invalidArgument("the layout name is empty")
            }
            layoutReference = SlideLayoutReference(predefinedLayout: normalized)
        }
        let request = CreateSlideRequest(
            insertionIndex: position.map { $0 - 1 },
            slideLayoutReference: layoutReference
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createSlide(request)]
        )
        guard let objectId = response.replies?.first?.createSlide?.objectId else {
            throw GrahamError.invalidResponse(
                "the createSlide reply carries no object id")
        }
        return objectId
    }

    /// Creates a text box on one slide, optionally inserts its initial text,
    /// and returns the new element's object id.
    ///
    /// Geometry is measured in points. Shape creation and non-empty text
    /// insertion are sent together in one atomic batch update.
    public func createTextBox(
        presentationId: String,
        slideId: String,
        text: String,
        objectId: String? = nil,
        x: Double = 50,
        y: Double = 50,
        width: Double = 300,
        height: Double = 50
    ) async throws -> String {
        let sentObjectId = Self.makeObjectId(objectId)
        let size = ElementSize(
            width: ElementDimension(magnitude: width, unit: .pt),
            height: ElementDimension(magnitude: height, unit: .pt)
        )
        let transform = ElementTransform(
            translateX: x,
            translateY: y,
            unit: .pt
        )
        let createShape = CreateShapeRequest(
            objectId: sentObjectId,
            elementProperties: PageElementProperties(
                pageObjectId: slideId,
                size: size,
                transform: transform
            ),
            shapeType: "TEXT_BOX"
        )
        var requests: [SlidesBatchUpdateRequest] = [.createShape(createShape)]
        if !text.isEmpty {
            requests.append(.insertText(InsertTextRequest(
                objectId: sentObjectId,
                text: text,
                insertionIndex: 0
            )))
        }

        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: requests
        )
        return response.replies?.first?.createShape?.objectId ?? sentObjectId
    }

    /// Creates an image on one slide and returns the new element's object id.
    /// Geometry is measured in points; when omitted, Google keeps the image's
    /// native size and chooses its placement.
    public func createImage(
        presentationId: String,
        slideId: String,
        url: String,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard !url.isEmpty else {
            throw GrahamError.invalidArgument("the image URL is empty")
        }
        let sentObjectId = Self.makeObjectId(objectId)
        let request = CreateImageRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            url: url
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createImage(request)]
        )
        return response.replies?.first?.createImage?.objectId ?? sentObjectId
    }

    /// Creates a YouTube or Drive video on one slide and returns the new
    /// element's object id. Geometry is measured in points.
    public func createVideo(
        presentationId: String,
        slideId: String,
        source: VideoSource = .youtube,
        videoId: String,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard !videoId.isEmpty else {
            throw GrahamError.invalidArgument("the video id is empty")
        }
        let sentObjectId = Self.makeObjectId(objectId)
        let request = CreateVideoRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            source: source,
            id: videoId
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createVideo(request)]
        )
        return response.replies?.first?.createVideo?.objectId ?? sentObjectId
    }

    /// Creates a line on one slide and returns the new element's object id.
    /// Geometry is measured in points.
    public func createLine(
        presentationId: String,
        slideId: String,
        category: LineCategory = .straight,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        let sentObjectId = Self.makeObjectId(objectId)
        let request = CreateLineRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            category: category
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createLine(request)]
        )
        return response.replies?.first?.createLine?.objectId ?? sentObjectId
    }

    /// Creates a table on one slide and returns the new element's object id.
    /// Geometry is measured in points.
    public func createTable(
        presentationId: String,
        slideId: String,
        rows: Int,
        columns: Int,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard rows >= 1 else {
            throw GrahamError.invalidArgument("table rows must be 1 or greater, got \(rows)")
        }
        guard columns >= 1 else {
            throw GrahamError.invalidArgument(
                "table columns must be 1 or greater, got \(columns)")
        }
        let sentObjectId = Self.makeObjectId(objectId)
        let request = CreateTableRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            rows: rows,
            columns: columns
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createTable(request)]
        )
        return response.replies?.first?.createTable?.objectId ?? sentObjectId
    }

    /// Creates a page element from a Sheets embedded chart and returns its
    /// object id. Geometry is measured in points.
    public func createSheetsChart(
        presentationId: String,
        slideId: String,
        spreadsheetId: String,
        chartId: Int,
        linked: Bool = false,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard !spreadsheetId.isEmpty else {
            throw GrahamError.invalidArgument("the spreadsheet id is empty")
        }
        let sentObjectId = Self.makeObjectId(objectId)
        let request = CreateSheetsChartRequest(
            objectId: sentObjectId,
            elementProperties: try makeChartElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            spreadsheetId: spreadsheetId,
            chartId: chartId,
            linkingMode: linked ? .linked : nil
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createSheetsChart(request)]
        )
        return response.replies?.first?.createSheetsChart?.objectId ?? sentObjectId
    }

    /// Groups page elements and returns the new group's object id.
    public func groupElements(
        presentationId: String,
        childIds: [String],
        groupObjectId: String? = nil
    ) async throws -> String {
        guard childIds.count >= 2 else {
            throw GrahamError.invalidArgument("a group requires at least 2 child object ids")
        }
        let sentObjectId = Self.makeObjectId(groupObjectId)
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.groupObjects(GroupObjectsRequest(
                groupObjectId: sentObjectId,
                childrenObjectIds: childIds
            ))]
        )
        return response.replies?.first?.groupObjects?.objectId ?? sentObjectId
    }

    /// Removes top-level groups while keeping their children in place.
    public func ungroupElements(
        presentationId: String,
        objectIds: [String]
    ) async throws {
        guard !objectIds.isEmpty else {
            throw GrahamError.invalidArgument("ungroup requires at least 1 group object id")
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.ungroupObjects(UngroupObjectsRequest(objectIds: objectIds))]
        )
    }
    /// Builds optional creation geometry shared by every non-shape element.
    private func makeElementProperties(
        slideId: String,
        x: Double?,
        y: Double?,
        width: Double?,
        height: Double?
    ) throws -> PageElementProperties {
        guard (width == nil) == (height == nil) else {
            throw GrahamError.invalidArgument("width and height must be provided together")
        }

        let size: ElementSize?
        if let width, let height {
            guard width.isFinite, width > 0 else {
                throw GrahamError.invalidArgument("width must be greater than zero")
            }
            guard height.isFinite, height > 0 else {
                throw GrahamError.invalidArgument("height must be greater than zero")
            }
            size = ElementSize(
                width: ElementDimension(magnitude: width, unit: .pt),
                height: ElementDimension(magnitude: height, unit: .pt)
            )
        } else {
            size = nil
        }

        let transform: ElementTransform?
        if x != nil || y != nil {
            transform = ElementTransform(
                translateX: x ?? 0,
                translateY: y ?? 0,
                unit: .pt
            )
        } else {
            transform = nil
        }

        return PageElementProperties(
            pageObjectId: slideId,
            size: size,
            transform: transform
        )
    }

    /// Builds element properties for `createSheetsChart`, always carrying an
    /// explicit size and transform.
    ///
    /// Unlike the other create operations, Slides rejects a `createSheetsChart`
    /// request whose `elementProperties` omit a size: it defaults the dimension
    /// to `UNIT_UNSPECIFIED` and returns "Unknown dimension unit
    /// UNIT_UNSPECIFIED". A default chart box (measured in points) is filled in
    /// when the caller omits geometry so the request always validates.
    private func makeChartElementProperties(
        slideId: String,
        x: Double?,
        y: Double?,
        width: Double?,
        height: Double?
    ) throws -> PageElementProperties {
        // Validate before defaulting so partial geometry is still rejected;
        // once both are nil we substitute the whole default box.
        guard (width == nil) == (height == nil) else {
            throw GrahamError.invalidArgument("width and height must be provided together")
        }
        return try makeElementProperties(
            slideId: slideId,
            x: x ?? 50,
            y: y ?? 50,
            width: width ?? 480,
            height: height ?? 300
        )
    }

    /// Inserts text into a text-bearing page element, or a table cell.
    ///
    /// `insertionIndex` is a zero-based UTF-16 code-unit offset into the target
    /// text. To insert into a table cell, pass both a one-based `row` and
    /// `column`; the client translates them to the API's zero-based cell
    /// Moves one slide so it ends at a one-based final position.
    ///
    /// The API's `updateSlidesPosition.insertionIndex` is zero-based and refers
    /// to the slide order **before** the move. So this method first reads the
    /// current slide order, then translates: for a final zero-based index `f`
    /// and a current index `c`, the insertion index is `f` when the slide moves
    /// backward (`f < c`) and `f + 1` when it moves forward (`f > c`), because
    /// the slide's own pre-move position still counts in the insertion order.
    /// When the slide is already at `position`, no write is sent.
    ///
    /// - Parameters:
    ///   - presentationId: The presentation that holds the slide.
    ///   - slideId: The exact object id of the slide to move.
    ///   - position: The one-based final position, matching the slide numbers
    ///     that `slides cat` and `slides list` print.
    public func moveSlide(
        presentationId: String,
        slideId: String,
        to position: Int
    ) async throws {
        guard position >= 1 else {
            throw GrahamError.invalidArgument(
                "slide position must be 1 or greater, got \(position)")
        }
        // Only the slide order is needed, so the read pulls just the ids.
        let presentation = try await self.presentation(
            id: presentationId, fields: "slides.objectId")
        let slides = presentation.slides ?? []
        guard let currentIndex = slides.firstIndex(where: { $0.objectId == slideId }) else {
            throw GrahamError.invalidArgument(
                "no slide with id \"\(slideId)\" in presentation \(presentationId)")
        }
        guard position <= slides.count else {
            throw GrahamError.invalidArgument(
                "slide position \(position) is out of range; "
                + "the presentation has \(slides.count) slide(s)")
        }
        let targetIndex = position - 1
        if targetIndex == currentIndex {
            return
        }
        let insertionIndex = targetIndex > currentIndex ? targetIndex + 1 : targetIndex
        let request = UpdateSlidesPositionRequest(
            slideObjectIds: [slideId],
            insertionIndex: insertionIndex
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateSlidesPosition(request)]
        )
    }

    /// Deletes one slide or page element by its exact object id.
    ///
    /// The id is sent as given: this method never infers, expands, or looks up
    /// a target. Google rejects an id that does not exist.
    public func deleteObject(presentationId: String, objectId: String) async throws {
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.deleteObject(DeleteObjectRequest(objectId: objectId))]
        )
    }

    /// Sets or clears a page element's alt text (its title and description).
    ///
    /// The Slides `updatePageElementAltText` operation has no field mask: an
    /// omitted field keeps its current value and an empty string clears it. So
    /// `title` and `description` are each `String?` — `nil` omits the field
    /// (leave it unchanged) and `""` clears it. Passing both `nil` has nothing
    /// to do and throws ``GrahamError/invalidArgument(_:)`` before any request.
    /// Clearing both fields (`title: "", description: ""`) is the API's way to
    /// delete an element's alt text. The reply is empty.
    public func setAltText(
        presentationId: String,
        objectId: String,
        title: String? = nil,
        description: String? = nil
    ) async throws {
        guard title != nil || description != nil else {
            throw GrahamError.invalidArgument(
                "set alt text requires a title or a description "
                + "(each may be an empty string to clear it)")
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updatePageElementAltText(UpdatePageElementAltTextRequest(
                objectId: objectId,
                title: title,
                description: description
            ))]
        )
    }
    // MARK: - Tables

    /// Inserts `count` rows above or below a one-based reference row.
    /// Google permits at most 20 rows per request.
    public func insertTableRows(
        presentationId: String,
        tableId: String,
        row: Int,
        below: Bool = true,
        count: Int = 1
    ) async throws {
        try Self.validateOneBased(row, label: "table row")
        guard (1...20).contains(count) else {
            throw GrahamError.invalidArgument(
                "table row count must be between 1 and 20, got \(count)")
        }
        let request = InsertTableRowsRequest(
            tableObjectId: tableId,
            cellLocation: TableCellLocation(rowIndex: row - 1),
            number: count,
            insertBelow: below
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.insertTableRows(request)]
        )
    }

    /// Inserts `count` columns to the left or right of a one-based reference
    /// column. Google permits at most 20 columns per request.
    public func insertTableColumns(
        presentationId: String,
        tableId: String,
        column: Int,
        right: Bool = true,
        count: Int = 1
    ) async throws {
        try Self.validateOneBased(column, label: "table column")
        guard (1...20).contains(count) else {
            throw GrahamError.invalidArgument(
                "table column count must be between 1 and 20, got \(count)")
        }
        let request = InsertTableColumnsRequest(
            tableObjectId: tableId,
            cellLocation: TableCellLocation(columnIndex: column - 1),
            number: count,
            insertRight: right
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.insertTableColumns(request)]
        )
    }

    /// Deletes the row containing a one-based reference cell. If the cell is
    /// merged across rows, Google deletes every row that it spans.
    public func deleteTableRow(
        presentationId: String,
        tableId: String,
        row: Int
    ) async throws {
        try Self.validateOneBased(row, label: "table row")
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.deleteTableRow(DeleteTableRowRequest(
                tableObjectId: tableId,
                cellLocation: TableCellLocation(rowIndex: row - 1)
            ))]
        )
    }

    /// Deletes the column containing a one-based reference cell. If the cell
    /// is merged across columns, Google deletes every column that it spans.
    public func deleteTableColumn(
        presentationId: String,
        tableId: String,
        column: Int
    ) async throws {
        try Self.validateOneBased(column, label: "table column")
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.deleteTableColumn(DeleteTableColumnRequest(
                tableObjectId: tableId,
                cellLocation: TableCellLocation(columnIndex: column - 1)
            ))]
        )
    }

    /// Merges a one-based table range. Text from every merged cell is
    /// concatenated into the range's upper-left cell.
    public func mergeTableCells(
        presentationId: String,
        tableId: String,
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int
    ) async throws {
        let range = try Self.buildTableRange(
            row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.mergeTableCells(MergeTableCellsRequest(
                objectId: tableId,
                tableRange: range
            ))]
        )
    }

    /// Unmerges every merged cell in a one-based table range.
    public func unmergeTableCells(
        presentationId: String,
        tableId: String,
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int
    ) async throws {
        let range = try Self.buildTableRange(
            row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.unmergeTableCells(UnmergeTableCellsRequest(
                objectId: tableId,
                tableRange: range
            ))]
        )
    }
    /// Refreshes a linked Sheets chart to its latest spreadsheet data.
    ///
    /// This works only on a chart embedded with `LINKED` linking mode; Google
    /// rejects an object id that is not a linked chart. The reply is empty.
    public func refreshSheetsChart(presentationId: String, objectId: String) async throws {
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.refreshSheetsChart(RefreshSheetsChartRequest(objectId: objectId))]
        )
    }
    /// Returns a provided object id, or generates one that satisfies Slides'
    /// client-assigned object-id requirements.
    private static func makeObjectId(_ provided: String?) -> String {
        provided ?? "graham-\(UUID().uuidString)"
    }
    /// Normalizes a predefined layout name: trims whitespace, uppercases, and
    /// maps `-` and spaces to `_`, so `title-and-body` becomes `TITLE_AND_BODY`.
    static func normalizeLayout(_ layout: String) -> String {
        layout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
