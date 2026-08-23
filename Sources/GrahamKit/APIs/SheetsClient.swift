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
}
