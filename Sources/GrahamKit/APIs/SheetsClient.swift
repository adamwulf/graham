import Foundation

/// The high-level client for the Sheets v4 API.
public struct SheetsClient: Sendable {
    public static let baseURL = "https://sheets.googleapis.com/v4"

    private let api: GoogleAPI

    public init(api: GoogleAPI) {
        self.api = api
    }

    /// Gets a spreadsheet's metadata: its title and its sheets.
    public func spreadsheet(id: String) async throws -> Spreadsheet {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(id))",
            query: [("fields",
                "spreadsheetId,properties.title,spreadsheetUrl,sheets.properties,"
                    + "sheets.charts.chartId,sheets.charts.spec.title")]
        )
        return try await api.getJSON(Spreadsheet.self, from: url)
    }

    /// Reads cell values from a range in A1 notation, for example
    /// `Sheet1!A1:C10` or `Sheet1`.
    ///
    /// `renderOption` chooses how each cell is rendered; the default (`nil`)
    /// leaves the server default `FORMATTED_VALUE`, so the URL is unchanged for
    /// callers that do not ask for raw values or formulas.
    public func values(
        spreadsheetId: String,
        range: String,
        renderOption: SheetsValueRenderOption? = nil
    ) async throws -> ValueRange {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId))"
                + "/values/\(GoogleURL.escapePathComponent(range))",
            query: [("valueRenderOption", renderOption?.rawValue)]
        )
        return try await api.getJSON(ValueRange.self, from: url)
    }

    /// Reads several ranges in one call. Each `ValueRange` in the reply matches
    /// one requested range, in request order.
    public func batchGetValues(
        spreadsheetId: String,
        ranges: [String],
        renderOption: SheetsValueRenderOption? = nil
    ) async throws -> BatchGetValuesResponse {
        guard !ranges.isEmpty else {
            throw GrahamError.invalidArgument("provide at least one range to read")
        }
        let query: [(String, String?)] =
            ranges.map { ("ranges", Optional($0)) }
            + [("valueRenderOption", renderOption?.rawValue)]
        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId))"
                + "/values:batchGet",
            query: query
        )
        return try await api.getJSON(BatchGetValuesResponse.self, from: url)
    }

    // MARK: - Writes

    /// Writes rows of cell values to an A1 range.
    ///
    /// Values are sent with `USER_ENTERED`, so Sheets interprets them as if a
    /// user typed them in the UI; for example, numeric strings become numbers.
    public func setValues(
        spreadsheetId: String,
        range: String,
        values: [[String]]
    ) async throws -> UpdateValuesResponse {
        guard !values.isEmpty else {
            throw GrahamError.invalidArgument("values must contain at least one row")
        }
        guard !values.contains(where: \.isEmpty) else {
            throw GrahamError.invalidArgument("each values row must contain at least one cell")
        }

        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId))"
                + "/values/\(GoogleURL.escapePathComponent(range))",
            query: [("valueInputOption", "USER_ENTERED")]
        )
        return try await api.sendJSON(
            UpdateValuesResponse.self,
            method: "PUT",
            url: url,
            body: UpdateValuesRequestBody(values: values)
        )
    }

    /// Appends rows after the logical table found within `range`, without first
    /// finding the next free row. Values use `USER_ENTERED`, and Sheets inserts
    /// new rows (`INSERT_ROWS`) rather than overwriting cells below the table.
    public func appendValues(
        spreadsheetId: String,
        range: String,
        values: [[String]]
    ) async throws -> AppendValuesResponse {
        guard !values.isEmpty else {
            throw GrahamError.invalidArgument("values must contain at least one row")
        }
        guard !values.contains(where: \.isEmpty) else {
            throw GrahamError.invalidArgument("each values row must contain at least one cell")
        }

        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId))"
                + "/values/\(GoogleURL.escapePathComponent(range)):append",
            query: [
                ("valueInputOption", "USER_ENTERED"),
                ("insertDataOption", "INSERT_ROWS"),
            ]
        )
        return try await api.sendJSON(
            AppendValuesResponse.self,
            method: "POST",
            url: url,
            body: UpdateValuesRequestBody(values: values)
        )
    }

    /// Clears the cell values in `range`, leaving formatting intact. The request
    /// body is empty; the reply reports the range that was cleared.
    public func clearValues(
        spreadsheetId: String,
        range: String
    ) async throws -> ClearValuesResponse {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId))"
                + "/values/\(GoogleURL.escapePathComponent(range)):clear"
        )
        return try await api.sendJSON(
            ClearValuesResponse.self,
            method: "POST",
            url: url,
            body: EmptyJSONBody()
        )
    }

    /// Sends one `spreadsheets.batchUpdate` call with `requests`, in order.
    ///
    /// This is the shared Sheets batch-write path. High-level operations build
    /// typed ``SheetsBatchUpdateRequest`` values and go through this method.
    public func batchUpdate(
        spreadsheetId: String,
        requests: [SheetsBatchUpdateRequest]
    ) async throws -> SheetsBatchUpdateResponse {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId)):batchUpdate"
        )
        return try await api.sendJSON(
            SheetsBatchUpdateResponse.self,
            method: "POST",
            url: url,
            body: SheetsBatchUpdateRequestBody(requests: requests)
        )
    }

    /// Adds a chart and returns its numeric chart id.
    ///
    /// The first input column is the chart domain and every remaining column
    /// becomes a series (a pie chart uses only the first two columns). The first
    /// row supplies the headers. By default the chart lands on its own new sheet;
    /// pass `overlay` to float it over an existing sheet instead.
    public func addChart(
        spreadsheetId: String,
        title: String? = nil,
        type: BasicChartType = .column,
        range: String,
        pie: Bool = false,
        overlay: ChartOverlay? = nil
    ) async throws -> Int {
        let parsed = try validatedChartRange(range)
        let metadata = try await spreadsheet(id: spreadsheetId)
        let dataSheetId = try sheetId(from: metadata, name: parsed.sheetName)
        let spec = chartSpec(parsed: parsed, sheetId: dataSheetId, type: type, title: title, pie: pie)

        let position: EmbeddedObjectPosition
        if let overlay {
            let anchor = try A1Range.parse(overlay.anchor)
            let anchorSheetId = try anchor.sheetName == nil
                ? dataSheetId
                : sheetId(from: metadata, name: anchor.sheetName)
            position = EmbeddedObjectPosition(overlayPosition: OverlayPosition(
                anchorCell: GridCoordinate(
                    sheetId: anchorSheetId,
                    rowIndex: anchor.startRowIndex,
                    columnIndex: anchor.startColumnIndex),
                widthPixels: overlay.widthPixels,
                heightPixels: overlay.heightPixels))
        } else {
            position = EmbeddedObjectPosition(newSheet: true)
        }

        let request = SheetsBatchUpdateRequest.addChart(AddChartRequest(
            chart: EmbeddedChart(spec: spec, position: position)))
        let response = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
        guard let chartId = response.replies?.first?.addChart?.chart?.chartId else {
            throw GrahamError.invalidResponse("addChart returned no chartId")
        }
        return chartId
    }

    /// Replaces an existing chart's spec, rebuilt from `range` and `type`.
    public func updateChart(
        spreadsheetId: String,
        chartId: Int,
        title: String? = nil,
        type: BasicChartType = .column,
        range: String,
        pie: Bool = false
    ) async throws {
        let parsed = try validatedChartRange(range)
        let metadata = try await spreadsheet(id: spreadsheetId)
        let dataSheetId = try sheetId(from: metadata, name: parsed.sheetName)
        let spec = chartSpec(parsed: parsed, sheetId: dataSheetId, type: type, title: title, pie: pie)
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.updateChartSpec(UpdateChartSpecRequest(chartId: chartId, spec: spec))])
    }

    /// Deletes an embedded chart by its numeric id.
    public func deleteChart(spreadsheetId: String, chartId: Int) async throws {
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.deleteEmbeddedObject(DeleteEmbeddedObjectRequest(objectId: chartId))])
    }

    // MARK: Chart building

    /// Parses and range-checks a chart source range (at least 2 columns wide and
    /// 2 rows tall — a header row plus a domain column plus a series column).
    private func validatedChartRange(_ range: String) throws -> A1Range {
        let parsed = try A1Range.parse(range)
        guard parsed.endColumnIndex - parsed.startColumnIndex >= 2 else {
            throw GrahamError.invalidArgument(
                "chart range \"\(range)\" must be at least 2 columns wide")
        }
        guard parsed.endRowIndex - parsed.startRowIndex >= 2 else {
            throw GrahamError.invalidArgument(
                "chart range \"\(range)\" must be at least 2 rows tall")
        }
        return parsed
    }

    /// Resolves a sheet name to its numeric id within already-fetched metadata,
    /// or the first sheet when `name` is nil.
    private func sheetId(from metadata: Spreadsheet, name: String?) throws -> Int {
        let sheet: Sheet
        if let name {
            guard let match = metadata.sheets?.first(where: {
                $0.properties?.title == name
            }) else {
                throw GrahamError.invalidArgument("spreadsheet has no sheet named \"\(name)\"")
            }
            sheet = match
        } else {
            guard let first = metadata.sheets?.first else {
                throw GrahamError.invalidResponse("the spreadsheet has no sheets")
            }
            sheet = first
        }
        guard let id = sheet.properties?.sheetId else {
            throw GrahamError.invalidResponse("the selected sheet has no sheetId")
        }
        return id
    }

    /// Builds a basic or pie chart spec from a parsed source range.
    private func chartSpec(
        parsed: A1Range,
        sheetId: Int,
        type: BasicChartType,
        title: String?,
        pie: Bool
    ) -> ChartSpec {
        func data(forColumn column: Int) -> ChartData {
            ChartData(sourceRange: ChartSourceRange(sources: [GridRange(
                sheetId: sheetId,
                startRowIndex: parsed.startRowIndex,
                endRowIndex: parsed.endRowIndex,
                startColumnIndex: column,
                endColumnIndex: column + 1
            )]))
        }
        let domainData = data(forColumn: parsed.startColumnIndex)
        if pie {
            return ChartSpec(title: title, pieChart: PieChartSpec(
                legendPosition: "RIGHT_LEGEND",
                domain: domainData,
                series: data(forColumn: parsed.startColumnIndex + 1)))
        }
        let domain = BasicChartDomain(domain: domainData)
        let series = ((parsed.startColumnIndex + 1)..<parsed.endColumnIndex).map { column in
            BasicChartSeries(series: data(forColumn: column), targetAxis: "LEFT_AXIS")
        }
        return ChartSpec(title: title, basicChart: BasicChartSpec(
            chartType: type,
            legendPosition: "BOTTOM_LEGEND",
            headerCount: 1,
            domains: [domain],
            series: series))
    }

    // MARK: - Sheets (tabs)

    /// Adds a new sheet (tab) and returns its server-assigned properties.
    ///
    /// `position` is the one-based position the tab should occupy; it is
    /// translated to the API's zero-based `index`. Omit it to append the tab.
    public func addSheet(
        spreadsheetId: String,
        title: String,
        position: Int? = nil
    ) async throws -> Sheet.Properties {
        var index: Int?
        if let position {
            guard position >= 1 else {
                throw GrahamError.invalidArgument("position must be one-based (>= 1)")
            }
            index = position - 1
        }
        let request = SheetsBatchUpdateRequest.addSheet(AddSheetRequest(
            properties: SheetPropertiesRequest(title: title, index: index)))
        let response = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
        guard let properties = response.replies?.first?.addSheet?.properties else {
            throw GrahamError.invalidResponse("addSheet returned no sheet properties")
        }
        return properties
    }

    /// Deletes a sheet (tab) by its numeric id.
    public func deleteSheet(spreadsheetId: String, sheetId: Int) async throws {
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.deleteSheet(DeleteSheetRequest(sheetId: sheetId))])
    }

    /// Renames a sheet (tab). Only the title is updated (`fields=title`).
    public func renameSheet(
        spreadsheetId: String,
        sheetId: Int,
        title: String
    ) async throws {
        let request = SheetsBatchUpdateRequest.updateSheetProperties(UpdateSheetPropertiesRequest(
            properties: SheetPropertiesRequest(sheetId: sheetId, title: title),
            fields: "title"))
        _ = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
    }

    /// Resolves a sheet title to its numeric id within a spreadsheet, so a
    /// title-addressed command can target the operations that take a `sheetId`.
    public func sheetId(spreadsheetId: String, title: String) async throws -> Int {
        let metadata = try await spreadsheet(id: spreadsheetId)
        guard let sheet = (metadata.sheets ?? []).first(where: {
            $0.properties?.title == title
        }) else {
            throw GrahamError.invalidArgument("spreadsheet has no sheet named \"\(title)\"")
        }
        guard let id = sheet.properties?.sheetId else {
            throw GrahamError.invalidResponse("the sheet \"\(title)\" has no sheetId")
        }
        return id
    }

    /// The numeric id of the spreadsheet's first sheet, used as the default
    /// target when a command names no specific tab.
    public func firstSheetId(spreadsheetId: String) async throws -> Int {
        let metadata = try await spreadsheet(id: spreadsheetId)
        guard let id = (metadata.sheets ?? []).first?.properties?.sheetId else {
            throw GrahamError.invalidResponse("the spreadsheet has no sheets")
        }
        return id
    }

    // MARK: - Grid shape

    /// Freezes rows and/or columns on a sheet. At least one of `rows` or
    /// `columns` must be given; each is a count and must be non-negative. The
    /// `fields` mask names only the counts provided, so an unset one is left as
    /// is.
    public func freeze(
        spreadsheetId: String,
        sheetId: Int,
        rows: Int? = nil,
        columns: Int? = nil
    ) async throws {
        guard rows != nil || columns != nil else {
            throw GrahamError.invalidArgument("provide a row and/or column count to freeze")
        }
        if let rows, rows < 0 {
            throw GrahamError.invalidArgument("the frozen row count must be non-negative")
        }
        if let columns, columns < 0 {
            throw GrahamError.invalidArgument("the frozen column count must be non-negative")
        }
        var fields: [String] = []
        if rows != nil { fields.append("gridProperties.frozenRowCount") }
        if columns != nil { fields.append("gridProperties.frozenColumnCount") }
        let request = SheetsBatchUpdateRequest.updateSheetProperties(UpdateSheetPropertiesRequest(
            properties: SheetPropertiesRequest(
                sheetId: sheetId,
                gridProperties: GridPropertiesRequest(
                    frozenRowCount: rows, frozenColumnCount: columns)),
            fields: fields.joined(separator: ",")))
        _ = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
    }

    /// Resizes a span of rows or columns to `pixelSize`.
    ///
    /// `start` and `end` are one-based, inclusive positions (the CLI convention);
    /// they translate to the API's zero-based, half-open `DimensionRange`. Omit
    /// `end` (pass it equal to `start`) to resize a single row or column.
    public func resizeDimension(
        spreadsheetId: String,
        sheetId: Int,
        dimension: SheetsDimension,
        start: Int,
        end: Int,
        pixelSize: Int
    ) async throws {
        guard start >= 1 else {
            throw GrahamError.invalidArgument("the start position must be one-based (>= 1)")
        }
        guard end >= start else {
            throw GrahamError.invalidArgument("the end position must be at or after the start")
        }
        guard pixelSize > 0 else {
            throw GrahamError.invalidArgument("the pixel size must be positive")
        }
        let request = SheetsBatchUpdateRequest.updateDimensionProperties(
            UpdateDimensionPropertiesRequest(
                range: DimensionRange(
                    sheetId: sheetId,
                    dimension: dimension.rawValue,
                    startIndex: start - 1,
                    endIndex: end),
                properties: DimensionProperties(pixelSize: pixelSize),
                fields: "pixelSize"))
        _ = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
    }

    // MARK: - Cell formatting

    /// Applies a cell format across an A1 `range`, via `repeatCell`. At least one
    /// of `bold`, `backgroundColor`, `numberFormat`, or `horizontalAlignment`
    /// must be set; the `fields` mask names only the ones provided, so unset
    /// aspects of the existing format are left intact. `numberFormat` is a
    /// pattern applied with the `NUMBER` type.
    public func formatCells(
        spreadsheetId: String,
        range: String,
        bold: Bool? = nil,
        backgroundColor: SheetsColor? = nil,
        numberFormat: String? = nil,
        horizontalAlignment: SheetsHorizontalAlignment? = nil
    ) async throws {
        guard bold != nil || backgroundColor != nil || numberFormat != nil
                || horizontalAlignment != nil else {
            throw GrahamError.invalidArgument("provide at least one format to set")
        }
        let parsed = try A1Range.parse(range)
        let targetSheetId: Int
        if let name = parsed.sheetName {
            targetSheetId = try await sheetId(spreadsheetId: spreadsheetId, title: name)
        } else {
            targetSheetId = try await firstSheetId(spreadsheetId: spreadsheetId)
        }

        var fields: [String] = []
        if bold != nil { fields.append("userEnteredFormat.textFormat.bold") }
        if backgroundColor != nil { fields.append("userEnteredFormat.backgroundColor") }
        if numberFormat != nil { fields.append("userEnteredFormat.numberFormat") }
        if horizontalAlignment != nil { fields.append("userEnteredFormat.horizontalAlignment") }

        let format = SheetsCellFormat(
            backgroundColor: backgroundColor,
            textFormat: bold.map { SheetsTextFormat(bold: $0) },
            numberFormat: numberFormat.map { SheetsNumberFormat(type: "NUMBER", pattern: $0) },
            horizontalAlignment: horizontalAlignment?.rawValue)
        let request = SheetsBatchUpdateRequest.repeatCell(RepeatCellRequest(
            range: GridRange(
                sheetId: targetSheetId,
                startRowIndex: parsed.startRowIndex,
                endRowIndex: parsed.endRowIndex,
                startColumnIndex: parsed.startColumnIndex,
                endColumnIndex: parsed.endColumnIndex),
            cell: SheetsCellData(userEnteredFormat: format),
            fields: fields.joined(separator: ",")))
        _ = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
    }

    // MARK: - Data tooling

    /// Resolves an A1 `range` to a ``GridRange``: the sheet id comes from the
    /// range's tab name, or the spreadsheet's first sheet when the range names
    /// none. This is the shared range-to-grid path for the data-tooling writes.
    private func resolveGridRange(
        spreadsheetId: String,
        range: String
    ) async throws -> GridRange {
        let parsed = try A1Range.parse(range)
        let targetSheetId: Int
        if let name = parsed.sheetName {
            targetSheetId = try await sheetId(spreadsheetId: spreadsheetId, title: name)
        } else {
            targetSheetId = try await firstSheetId(spreadsheetId: spreadsheetId)
        }
        return GridRange(
            sheetId: targetSheetId,
            startRowIndex: parsed.startRowIndex,
            endRowIndex: parsed.endRowIndex,
            startColumnIndex: parsed.startColumnIndex,
            endColumnIndex: parsed.endColumnIndex)
    }

    /// Adds a conditional-format rule over an A1 `range`: when a cell satisfies
    /// the boolean condition (`type` + `values`), its background is set to
    /// `backgroundColor`. `index` is the zero-based insertion position within the
    /// sheet's rule list. The condition's value count is validated before any
    /// request is sent.
    public func addConditionalFormatRule(
        spreadsheetId: String,
        range: String,
        type: SheetsConditionType,
        values: [String],
        backgroundColor: SheetsColor,
        index: Int = 0
    ) async throws {
        guard index >= 0 else {
            throw GrahamError.invalidArgument("the rule index must be non-negative")
        }
        let condition = try SheetsBooleanCondition.make(type: type, values: values)
        let gridRange = try await resolveGridRange(spreadsheetId: spreadsheetId, range: range)
        let rule = ConditionalFormatRule(
            ranges: [gridRange],
            booleanRule: BooleanRule(
                condition: condition,
                format: SheetsCellFormat(backgroundColor: backgroundColor)))
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.addConditionalFormatRule(
                AddConditionalFormatRuleRequest(rule: rule, index: index))])
    }

    /// Deletes the conditional-format rule at `index` on `sheetId`.
    public func deleteConditionalFormatRule(
        spreadsheetId: String,
        sheetId: Int,
        index: Int
    ) async throws {
        guard index >= 0 else {
            throw GrahamError.invalidArgument("the rule index must be non-negative")
        }
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.deleteConditionalFormatRule(
                DeleteConditionalFormatRuleRequest(sheetId: sheetId, index: index))])
    }

    /// Sets a data-validation rule on an A1 `range` from a boolean condition.
    /// `strict` rejects invalid input; `showCustomUi` draws the in-cell dropdown;
    /// `inputMessage` is the hover help. The value count is validated before any
    /// request is sent.
    public func setDataValidation(
        spreadsheetId: String,
        range: String,
        type: SheetsConditionType,
        values: [String],
        strict: Bool? = nil,
        showCustomUi: Bool? = nil,
        inputMessage: String? = nil
    ) async throws {
        let condition = try SheetsBooleanCondition.make(type: type, values: values)
        let gridRange = try await resolveGridRange(spreadsheetId: spreadsheetId, range: range)
        let rule = DataValidationRule(
            condition: condition,
            inputMessage: inputMessage,
            strict: strict,
            showCustomUi: showCustomUi)
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.setDataValidation(
                SetDataValidationRequest(range: gridRange, rule: rule))])
    }

    /// Clears data validation on an A1 `range` by sending a `nil` rule.
    public func clearDataValidation(
        spreadsheetId: String,
        range: String
    ) async throws {
        let gridRange = try await resolveGridRange(spreadsheetId: spreadsheetId, range: range)
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.setDataValidation(
                SetDataValidationRequest(range: gridRange, rule: nil))])
    }

    /// Sets the basic filter over an A1 `range`. One basic filter exists per
    /// sheet, so setting it replaces any existing one.
    public func setBasicFilter(
        spreadsheetId: String,
        range: String
    ) async throws {
        let gridRange = try await resolveGridRange(spreadsheetId: spreadsheetId, range: range)
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.setBasicFilter(SetBasicFilterRequest(filter: BasicFilter(range: gridRange)))])
    }

    /// Clears the basic filter from `sheetId`.
    public func clearBasicFilter(
        spreadsheetId: String,
        sheetId: Int
    ) async throws {
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.clearBasicFilter(ClearBasicFilterRequest(sheetId: sheetId))])
    }

    /// Adds a titled filter view over an A1 `range` and returns its new numeric
    /// id.
    public func addFilterView(
        spreadsheetId: String,
        range: String,
        title: String
    ) async throws -> Int {
        let gridRange = try await resolveGridRange(spreadsheetId: spreadsheetId, range: range)
        let response = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.addFilterView(AddFilterViewRequest(
                filter: FilterViewRequest(title: title, range: gridRange)))])
        guard let id = response.replies?.first?.addFilterView?.filter?.filterViewId else {
            throw GrahamError.invalidResponse("addFilterView returned no filterViewId")
        }
        return id
    }

    /// Adds a protected range over an A1 `range` and returns its new numeric id.
    /// `warningOnly` makes the protection advisory rather than enforced.
    public func addProtectedRange(
        spreadsheetId: String,
        range: String,
        description: String? = nil,
        warningOnly: Bool? = nil
    ) async throws -> Int {
        let gridRange = try await resolveGridRange(spreadsheetId: spreadsheetId, range: range)
        let response = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.addProtectedRange(AddProtectedRangeRequest(
                protectedRange: ProtectedRangeRequest(
                    range: gridRange, description: description, warningOnly: warningOnly)))])
        guard let id = response.replies?.first?.addProtectedRange?.protectedRange?.protectedRangeId
        else {
            throw GrahamError.invalidResponse("addProtectedRange returned no protectedRangeId")
        }
        return id
    }

    /// Deletes a protected range by its numeric id.
    public func deleteProtectedRange(
        spreadsheetId: String,
        protectedRangeId: Int
    ) async throws {
        _ = try await batchUpdate(
            spreadsheetId: spreadsheetId,
            requests: [.deleteProtectedRange(
                DeleteProtectedRangeRequest(protectedRangeId: protectedRangeId))])
    }
}

/// An empty JSON request body (`{}`), for POST endpoints such as
/// `values.clear` that require a body with no fields.
private struct EmptyJSONBody: Encodable {}
