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
            query: [("fields", "spreadsheetId,properties.title,spreadsheetUrl,sheets.properties")]
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

    /// Adds a basic chart on its own new sheet and returns its numeric chart id.
    ///
    /// The first input column is the chart domain and every remaining column
    /// becomes a series. The first row supplies the headers.
    public func addChart(
        spreadsheetId: String,
        title: String? = nil,
        type: BasicChartType = .column,
        range: String
    ) async throws -> Int {
        let parsed = try A1Range.parse(range)
        guard parsed.endColumnIndex - parsed.startColumnIndex >= 2 else {
            throw GrahamError.invalidArgument(
                "chart range \"\(range)\" must be at least 2 columns wide")
        }
        guard parsed.endRowIndex - parsed.startRowIndex >= 2 else {
            throw GrahamError.invalidArgument(
                "chart range \"\(range)\" must be at least 2 rows tall")
        }

        let metadata = try await spreadsheet(id: spreadsheetId)
        let sheet: Sheet
        if let sheetName = parsed.sheetName {
            guard let matchingSheet = metadata.sheets?.first(where: {
                $0.properties?.title == sheetName
            }) else {
                throw GrahamError.invalidArgument(
                    "spreadsheet has no sheet named \"\(sheetName)\"")
            }
            sheet = matchingSheet
        } else {
            guard let firstSheet = metadata.sheets?.first else {
                throw GrahamError.invalidResponse("the spreadsheet has no sheets")
            }
            sheet = firstSheet
        }
        guard let sheetId = sheet.properties?.sheetId else {
            throw GrahamError.invalidResponse("the selected sheet has no sheetId")
        }

        func data(forColumn column: Int) -> ChartData {
            ChartData(sourceRange: ChartSourceRange(sources: [GridRange(
                sheetId: sheetId,
                startRowIndex: parsed.startRowIndex,
                endRowIndex: parsed.endRowIndex,
                startColumnIndex: column,
                endColumnIndex: column + 1
            )]))
        }

        let domain = BasicChartDomain(domain: data(forColumn: parsed.startColumnIndex))
        let series = ((parsed.startColumnIndex + 1)..<parsed.endColumnIndex).map { column in
            BasicChartSeries(series: data(forColumn: column), targetAxis: "LEFT_AXIS")
        }
        let request = SheetsBatchUpdateRequest.addChart(AddChartRequest(chart: EmbeddedChart(
            spec: ChartSpec(
                title: title,
                basicChart: BasicChartSpec(
                    chartType: type,
                    legendPosition: "BOTTOM_LEGEND",
                    headerCount: 1,
                    domains: [domain],
                    series: series
                )
            ),
            position: EmbeddedObjectPosition(newSheet: true)
        )))

        let response = try await batchUpdate(spreadsheetId: spreadsheetId, requests: [request])
        guard let chartId = response.replies?.first?.addChart?.chart?.chartId else {
            throw GrahamError.invalidResponse("addChart returned no chartId")
        }
        return chartId
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
}

/// An empty JSON request body (`{}`), for POST endpoints such as
/// `values.clear` that require a body with no fields.
private struct EmptyJSONBody: Encodable {}
