import Foundation

// The models in this file follow the Google Sheets v4
// `spreadsheets.batchUpdate` and `spreadsheets.values.update` schemas. Request
// fields are required when the API operation requires them, so an invalid
// request fails to compile instead of failing at the server. Response fields
// stay optional and decode defensively.

// MARK: - Request union

/// One operation in a `spreadsheets.batchUpdate` call.
///
/// Each request object sets exactly one operation field. Later Sheets writes
/// join this union as new cases so they all share one batch-update path.
public enum SheetsBatchUpdateRequest: Encodable, Sendable, Equatable {
    /// Adds an embedded chart to the spreadsheet.
    case addChart(AddChartRequest)
    /// Adds a new sheet (tab).
    case addSheet(AddSheetRequest)
    /// Deletes a sheet (tab) by its numeric id.
    case deleteSheet(DeleteSheetRequest)
    /// Updates sheet (tab) properties, e.g. its title, position, or freeze.
    case updateSheetProperties(UpdateSheetPropertiesRequest)
    /// Resizes a row or column dimension (its pixel size).
    case updateDimensionProperties(UpdateDimensionPropertiesRequest)

    private enum CodingKeys: String, CodingKey {
        case addChart
        case addSheet
        case deleteSheet
        case updateSheetProperties
        case updateDimensionProperties
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addChart(let request):
            try container.encode(request, forKey: .addChart)
        case .addSheet(let request):
            try container.encode(request, forKey: .addSheet)
        case .deleteSheet(let request):
            try container.encode(request, forKey: .deleteSheet)
        case .updateSheetProperties(let request):
            try container.encode(request, forKey: .updateSheetProperties)
        case .updateDimensionProperties(let request):
            try container.encode(request, forKey: .updateDimensionProperties)
        }
    }
}

/// The body of a `spreadsheets.batchUpdate` POST.
struct SheetsBatchUpdateRequestBody: Encodable, Sendable {
    let requests: [SheetsBatchUpdateRequest]
}

/// The body of a `spreadsheets.values.update` PUT.
struct UpdateValuesRequestBody: Encodable, Sendable {
    let values: [[String]]
}

// MARK: - Add chart request

/// The `addChart` operation.
public struct AddChartRequest: Codable, Sendable, Equatable {
    public let chart: EmbeddedChart

    public init(chart: EmbeddedChart) {
        self.chart = chart
    }
}

/// A chart definition and its location in the spreadsheet.
///
/// `chartId` is deliberately absent: Google assigns it when the chart is
/// created and reports it in the batch-update reply.
public struct EmbeddedChart: Codable, Sendable, Equatable {
    public let spec: ChartSpec
    public let position: EmbeddedObjectPosition

    public init(spec: ChartSpec, position: EmbeddedObjectPosition) {
        self.spec = spec
        self.position = position
    }
}

/// Where an embedded object is placed.
public struct EmbeddedObjectPosition: Codable, Sendable, Equatable {
    /// When true, Google creates a new sheet containing only the object.
    public let newSheet: Bool?

    /// Overlay positions anchored to a cell and positions on an existing
    /// sheet are intentionally future work for this first write slice.
    public init(newSheet: Bool? = nil) {
        self.newSheet = newSheet
    }
}

/// The visible configuration of a basic chart.
public struct ChartSpec: Codable, Sendable, Equatable {
    public let title: String?
    public let basicChart: BasicChartSpec

    public init(title: String? = nil, basicChart: BasicChartSpec) {
        self.title = title
        self.basicChart = basicChart
    }
}

/// Basic chart types supported by graham's Sheets chart command.
public enum BasicChartType: String, Codable, Sendable, CaseIterable, Equatable {
    case bar = "BAR"
    case line = "LINE"
    case area = "AREA"
    case column = "COLUMN"
    case scatter = "SCATTER"
}

/// A basic chart with one domain column and one or more series columns.
public struct BasicChartSpec: Codable, Sendable, Equatable {
    public let chartType: BasicChartType
    public let legendPosition: String?
    public let headerCount: Int?
    public let domains: [BasicChartDomain]
    public let series: [BasicChartSeries]

    public init(
        chartType: BasicChartType,
        legendPosition: String? = nil,
        headerCount: Int? = nil,
        domains: [BasicChartDomain],
        series: [BasicChartSeries]
    ) {
        self.chartType = chartType
        self.legendPosition = legendPosition
        self.headerCount = headerCount
        self.domains = domains
        self.series = series
    }
}

/// The domain (category or x-axis) data for a basic chart.
public struct BasicChartDomain: Codable, Sendable, Equatable {
    public let domain: ChartData

    public init(domain: ChartData) {
        self.domain = domain
    }
}

/// One data series in a basic chart.
public struct BasicChartSeries: Codable, Sendable, Equatable {
    public let series: ChartData
    public let targetAxis: String?

    public init(series: ChartData, targetAxis: String? = nil) {
        self.series = series
        self.targetAxis = targetAxis
    }
}

/// A chart data source.
public struct ChartData: Codable, Sendable, Equatable {
    public let sourceRange: ChartSourceRange

    public init(sourceRange: ChartSourceRange) {
        self.sourceRange = sourceRange
    }
}

/// The grid ranges feeding a chart data source.
public struct ChartSourceRange: Codable, Sendable, Equatable {
    public let sources: [GridRange]

    public init(sources: [GridRange]) {
        self.sources = sources
    }
}

/// A zero-based, half-open rectangle on one sheet.
public struct GridRange: Codable, Sendable, Equatable {
    public let sheetId: Int
    public let startRowIndex: Int
    public let endRowIndex: Int
    public let startColumnIndex: Int
    public let endColumnIndex: Int

    public init(
        sheetId: Int,
        startRowIndex: Int,
        endRowIndex: Int,
        startColumnIndex: Int,
        endColumnIndex: Int
    ) {
        self.sheetId = sheetId
        self.startRowIndex = startRowIndex
        self.endRowIndex = endRowIndex
        self.startColumnIndex = startColumnIndex
        self.endColumnIndex = endColumnIndex
    }
}

// MARK: - Sheet (tab) requests

/// The writable grid properties of a sheet: the frozen row / column counts.
public struct GridPropertiesRequest: Codable, Sendable, Equatable {
    public let frozenRowCount: Int?
    public let frozenColumnCount: Int?

    public init(frozenRowCount: Int? = nil, frozenColumnCount: Int? = nil) {
        self.frozenRowCount = frozenRowCount
        self.frozenColumnCount = frozenColumnCount
    }
}

/// The writable subset of a sheet's properties used by the add and update
/// operations. Every field is optional so a caller sets only what it changes.
public struct SheetPropertiesRequest: Codable, Sendable, Equatable {
    public let sheetId: Int?
    public let title: String?
    public let index: Int?
    public let gridProperties: GridPropertiesRequest?

    public init(
        sheetId: Int? = nil,
        title: String? = nil,
        index: Int? = nil,
        gridProperties: GridPropertiesRequest? = nil
    ) {
        self.sheetId = sheetId
        self.title = title
        self.index = index
        self.gridProperties = gridProperties
    }
}

/// The dimension a resize targets.
public enum SheetsDimension: String, Sendable, CaseIterable, Equatable {
    case rows = "ROWS"
    case columns = "COLUMNS"
}

/// A zero-based, half-open span of rows or columns on one sheet.
public struct DimensionRange: Codable, Sendable, Equatable {
    public let sheetId: Int
    public let dimension: String
    public let startIndex: Int
    public let endIndex: Int

    public init(sheetId: Int, dimension: String, startIndex: Int, endIndex: Int) {
        self.sheetId = sheetId
        self.dimension = dimension
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

/// The writable properties of a row or column dimension.
public struct DimensionProperties: Codable, Sendable, Equatable {
    public let pixelSize: Int?

    public init(pixelSize: Int? = nil) {
        self.pixelSize = pixelSize
    }
}

/// The `updateDimensionProperties` operation. `fields` is a mask relative to
/// `properties` (for example `pixelSize`).
public struct UpdateDimensionPropertiesRequest: Codable, Sendable, Equatable {
    public let range: DimensionRange
    public let properties: DimensionProperties
    public let fields: String

    public init(range: DimensionRange, properties: DimensionProperties, fields: String) {
        self.range = range
        self.properties = properties
        self.fields = fields
    }
}

/// The `addSheet` operation.
public struct AddSheetRequest: Codable, Sendable, Equatable {
    public let properties: SheetPropertiesRequest

    public init(properties: SheetPropertiesRequest) {
        self.properties = properties
    }
}

/// The `deleteSheet` operation.
public struct DeleteSheetRequest: Codable, Sendable, Equatable {
    public let sheetId: Int

    public init(sheetId: Int) {
        self.sheetId = sheetId
    }
}

/// The `updateSheetProperties` operation. `fields` is a mask of the property
/// paths to update, relative to `properties` (for example `title` or `index`).
public struct UpdateSheetPropertiesRequest: Codable, Sendable, Equatable {
    public let properties: SheetPropertiesRequest
    public let fields: String

    public init(properties: SheetPropertiesRequest, fields: String) {
        self.properties = properties
        self.fields = fields
    }
}

// MARK: - Responses

/// The response of a `spreadsheets.batchUpdate` call.
public struct SheetsBatchUpdateResponse: Codable, Sendable {
    public let spreadsheetId: String?
    /// One reply per request, in request order.
    public let replies: [SheetsBatchUpdateReply]?
}

/// One reply in a Sheets batch-update response. Operations such as
/// `deleteSheet` and `updateSheetProperties` reply with an empty object.
public struct SheetsBatchUpdateReply: Codable, Sendable {
    public let addChart: AddChartReply?
    public let addSheet: AddSheetReply?
}

/// The reply of an `addSheet` operation, carrying the new sheet's properties.
public struct AddSheetReply: Codable, Sendable {
    public let properties: Sheet.Properties?
}

/// The reply of an `addChart` operation.
public struct AddChartReply: Codable, Sendable {
    public let chart: AddedChart?
}

/// The server-assigned identity of a newly added chart.
public struct AddedChart: Codable, Sendable {
    public let chartId: Int?
}

/// The trimmed response of a `spreadsheets.values.update` call.
public struct UpdateValuesResponse: Codable, Sendable {
    public let updatedRange: String?
    public let updatedRows: Int?
    public let updatedColumns: Int?
    public let updatedCells: Int?
}

/// The response of a `spreadsheets.values.append` call. The write counts live in
/// the nested `updates` object; `tableRange` reports the table the append found.
public struct AppendValuesResponse: Codable, Sendable {
    public let spreadsheetId: String?
    public let tableRange: String?
    public let updates: UpdateValuesResponse?
}

/// The response of a `spreadsheets.values.clear` call.
public struct ClearValuesResponse: Codable, Sendable {
    public let spreadsheetId: String?
    public let clearedRange: String?
}

/// The response of a `spreadsheets.values.batchGet` call: one `ValueRange` per
/// requested range, in request order.
public struct BatchGetValuesResponse: Codable, Sendable {
    public let spreadsheetId: String?
    public let valueRanges: [ValueRange]?
}
