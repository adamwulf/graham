import Foundation

/// A Google Sheets spreadsheet. Only the fields graham uses are modeled;
/// the decoder ignores all other fields.
public struct Spreadsheet: Codable, Sendable {
    public struct Properties: Codable, Sendable {
        public let title: String?
    }

    public let spreadsheetId: String
    public let properties: Properties?
    public let sheets: [Sheet]?
    public let spreadsheetUrl: String?
}

/// One sheet (tab) inside a spreadsheet.
public struct Sheet: Codable, Sendable {
    public struct Properties: Codable, Sendable {
        public struct GridProperties: Codable, Sendable {
            public let rowCount: Int?
            public let columnCount: Int?
            public let frozenRowCount: Int?
            public let frozenColumnCount: Int?
        }

        public let sheetId: Int?
        public let title: String?
        public let index: Int?
        public let gridProperties: GridProperties?
    }

    public let properties: Properties?
    public let charts: [SheetChart]?
}

/// One embedded chart, as read from `sheets.charts`.
public struct SheetChart: Codable, Sendable, Equatable {
    public struct Spec: Codable, Sendable, Equatable {
        public let title: String?
    }

    public let chartId: Int?
    public let spec: Spec?
}

extension SheetChart: GrahamRow {
    public static var tableColumns: [String] { ["CHART_ID", "TITLE"] }

    public var tableValues: [String] {
        [chartId.map(String.init) ?? "", spec?.title ?? ""]
    }

    public var idValue: String {
        chartId.map(String.init) ?? ""
    }
}

extension Sheet: GrahamRow {
    public static var tableColumns: [String] {
        ["SHEET_ID", "ROWS", "COLS", "FROZEN_R", "FROZEN_C", "TITLE"]
    }

    public var tableValues: [String] {
        let grid = properties?.gridProperties
        return [
            properties?.sheetId.map(String.init) ?? "",
            grid?.rowCount.map(String.init) ?? "",
            grid?.columnCount.map(String.init) ?? "",
            // The API omits a zero freeze count, so absence reads as 0.
            String(grid?.frozenRowCount ?? 0),
            String(grid?.frozenColumnCount ?? 0),
            properties?.title ?? "",
        ]
    }

    public var idValue: String {
        properties?.sheetId.map(String.init) ?? ""
    }
}

/// A range of cell values, from `spreadsheets.values.get`.
public struct ValueRange: Codable, Sendable {
    public let range: String?
    public let majorDimension: String?
    public let values: [[CellValue]]?
}

/// How a values read renders each cell. The default `FORMATTED_VALUE` returns
/// strings as shown in the UI; `UNFORMATTED_VALUE` returns the raw typed value;
/// `FORMULA` returns the underlying formula for formula cells.
public enum SheetsValueRenderOption: String, Sendable, CaseIterable, Equatable {
    case formatted = "FORMATTED_VALUE"
    case unformatted = "UNFORMATTED_VALUE"
    case formula = "FORMULA"
}

/// One cell value. With the default render option (`FORMATTED_VALUE`) all
/// cells arrive as strings. With `UNFORMATTED_VALUE` cells can be numbers
/// or booleans, so this enum covers all JSON scalar types.
public enum CellValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string): try container.encode(string)
        case .number(let number): try container.encode(number)
        case .bool(let bool): try container.encode(bool)
        case .null: try container.encodeNil()
        }
    }

    /// The value as text, for TSV output.
    public var display: String {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 {
                return String(Int64(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "TRUE" : "FALSE"
        case .null:
            return ""
        }
    }
}
