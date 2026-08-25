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
    public func values(spreadsheetId: String, range: String) async throws -> ValueRange {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/spreadsheets/\(GoogleURL.escapePathComponent(spreadsheetId))"
                + "/values/\(GoogleURL.escapePathComponent(range))"
        )
        return try await api.getJSON(ValueRange.self, from: url)
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
}
