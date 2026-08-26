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
    /// Repeats one cell's format across a range.
    case repeatCell(RepeatCellRequest)
    /// Deletes an embedded object (such as a chart) by its object id.
    case deleteEmbeddedObject(DeleteEmbeddedObjectRequest)
    /// Replaces an embedded chart's spec.
    case updateChartSpec(UpdateChartSpecRequest)
    /// Adds a conditional format rule at a zero-based index.
    case addConditionalFormatRule(AddConditionalFormatRuleRequest)
    /// Deletes a conditional format rule by sheet id and index.
    case deleteConditionalFormatRule(DeleteConditionalFormatRuleRequest)
    /// Sets or clears data validation on a range.
    case setDataValidation(SetDataValidationRequest)
    /// Sets the basic filter on a sheet.
    case setBasicFilter(SetBasicFilterRequest)
    /// Clears the basic filter from a sheet.
    case clearBasicFilter(ClearBasicFilterRequest)
    /// Adds a filter view and reports its new id.
    case addFilterView(AddFilterViewRequest)
    /// Adds a protected range and reports its new id.
    case addProtectedRange(AddProtectedRangeRequest)
    /// Deletes a protected range by its id.
    case deleteProtectedRange(DeleteProtectedRangeRequest)
    /// Sets or clears cell borders across a range.
    case updateBorders(UpdateBordersRequest)
    /// Merges a range of cells into one, or into merged rows/columns.
    case mergeCells(MergeCellsRequest)
    /// Splits any merged cells within a range back into individual cells.
    case unmergeCells(UnmergeCellsRequest)
    /// Sorts a range's rows by one or more of its columns.
    case sortRange(SortRangeRequest)
    /// Auto-sizes a span of rows or columns to fit their contents.
    case autoResizeDimensions(AutoResizeDimensionsRequest)
    /// Defines a named range over a rectangle of cells.
    case addNamedRange(AddNamedRangeRequest)
    /// Deletes a named range by its id.
    case deleteNamedRange(DeleteNamedRangeRequest)

    private enum CodingKeys: String, CodingKey {
        case addChart
        case addSheet
        case deleteSheet
        case updateSheetProperties
        case updateDimensionProperties
        case repeatCell
        case deleteEmbeddedObject
        case updateChartSpec
        case addConditionalFormatRule
        case deleteConditionalFormatRule
        case setDataValidation
        case setBasicFilter
        case clearBasicFilter
        case addFilterView
        case addProtectedRange
        case deleteProtectedRange
        case updateBorders
        case mergeCells
        case unmergeCells
        case sortRange
        case autoResizeDimensions
        case addNamedRange
        case deleteNamedRange
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
        case .repeatCell(let request):
            try container.encode(request, forKey: .repeatCell)
        case .deleteEmbeddedObject(let request):
            try container.encode(request, forKey: .deleteEmbeddedObject)
        case .updateChartSpec(let request):
            try container.encode(request, forKey: .updateChartSpec)
        case .addConditionalFormatRule(let request):
            try container.encode(request, forKey: .addConditionalFormatRule)
        case .deleteConditionalFormatRule(let request):
            try container.encode(request, forKey: .deleteConditionalFormatRule)
        case .setDataValidation(let request):
            try container.encode(request, forKey: .setDataValidation)
        case .setBasicFilter(let request):
            try container.encode(request, forKey: .setBasicFilter)
        case .clearBasicFilter(let request):
            try container.encode(request, forKey: .clearBasicFilter)
        case .addFilterView(let request):
            try container.encode(request, forKey: .addFilterView)
        case .addProtectedRange(let request):
            try container.encode(request, forKey: .addProtectedRange)
        case .deleteProtectedRange(let request):
            try container.encode(request, forKey: .deleteProtectedRange)
        case .updateBorders(let request):
            try container.encode(request, forKey: .updateBorders)
        case .mergeCells(let request):
            try container.encode(request, forKey: .mergeCells)
        case .unmergeCells(let request):
            try container.encode(request, forKey: .unmergeCells)
        case .sortRange(let request):
            try container.encode(request, forKey: .sortRange)
        case .autoResizeDimensions(let request):
            try container.encode(request, forKey: .autoResizeDimensions)
        case .addNamedRange(let request):
            try container.encode(request, forKey: .addNamedRange)
        case .deleteNamedRange(let request):
            try container.encode(request, forKey: .deleteNamedRange)
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

/// The `deleteEmbeddedObject` operation. `objectId` is the numeric chart id.
public struct DeleteEmbeddedObjectRequest: Codable, Sendable, Equatable {
    public let objectId: Int

    public init(objectId: Int) {
        self.objectId = objectId
    }
}

/// The `updateChartSpec` operation: replaces the whole spec of chart `chartId`.
public struct UpdateChartSpecRequest: Codable, Sendable, Equatable {
    public let chartId: Int
    public let spec: ChartSpec

    public init(chartId: Int, spec: ChartSpec) {
        self.chartId = chartId
        self.spec = spec
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

/// A cell coordinate an overlay chart anchors to (all zero-based).
public struct GridCoordinate: Codable, Sendable, Equatable {
    public let sheetId: Int
    public let rowIndex: Int
    public let columnIndex: Int

    public init(sheetId: Int, rowIndex: Int, columnIndex: Int) {
        self.sheetId = sheetId
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
    }
}

/// A CLI-friendly overlay request for `SheetsClient.addChart`. The `anchor` is a
/// single A1 cell (optionally sheet-qualified) the chart's top-left pins to; the
/// client resolves the sheet id and translates the cell to a ``GridCoordinate``.
public struct ChartOverlay: Sendable, Equatable {
    public let anchor: String
    public let widthPixels: Int?
    public let heightPixels: Int?

    public init(anchor: String, widthPixels: Int? = nil, heightPixels: Int? = nil) {
        self.anchor = anchor
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
    }
}

/// An overlay placement: the object floats over a sheet, anchored to a cell,
/// sized in pixels.
public struct OverlayPosition: Codable, Sendable, Equatable {
    public let anchorCell: GridCoordinate
    public let widthPixels: Int?
    public let heightPixels: Int?

    public init(anchorCell: GridCoordinate, widthPixels: Int? = nil, heightPixels: Int? = nil) {
        self.anchorCell = anchorCell
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
    }
}

/// Where an embedded object is placed: either on its own new sheet, or as an
/// overlay anchored to a cell on an existing sheet.
public struct EmbeddedObjectPosition: Codable, Sendable, Equatable {
    /// When true, Google creates a new sheet containing only the object.
    public let newSheet: Bool?
    public let overlayPosition: OverlayPosition?

    public init(newSheet: Bool? = nil, overlayPosition: OverlayPosition? = nil) {
        self.newSheet = newSheet
        self.overlayPosition = overlayPosition
    }
}

/// The visible configuration of a chart: exactly one of `basicChart` (bar,
/// line, area, column, scatter, combo) or `pieChart` is set.
public struct ChartSpec: Codable, Sendable, Equatable {
    public let title: String?
    public let basicChart: BasicChartSpec?
    public let pieChart: PieChartSpec?

    public init(
        title: String? = nil,
        basicChart: BasicChartSpec? = nil,
        pieChart: PieChartSpec? = nil
    ) {
        self.title = title
        self.basicChart = basicChart
        self.pieChart = pieChart
    }
}

/// A pie chart: one domain column and one series column.
public struct PieChartSpec: Codable, Sendable, Equatable {
    public let legendPosition: String?
    public let domain: ChartData
    public let series: ChartData

    public init(legendPosition: String? = nil, domain: ChartData, series: ChartData) {
        self.legendPosition = legendPosition
        self.domain = domain
        self.series = series
    }
}

/// Basic chart types supported by graham's Sheets chart command.
public enum BasicChartType: String, Codable, Sendable, CaseIterable, Equatable {
    case bar = "BAR"
    case line = "LINE"
    case area = "AREA"
    case column = "COLUMN"
    case scatter = "SCATTER"
    case combo = "COMBO"
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

// MARK: - Cell formatting (repeatCell)

/// An RGB color, each channel a float from 0 to 1. Sheets' `Color` also carries
/// an optional alpha, which graham leaves at the opaque default.
public struct SheetsColor: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses a hex color, with an optional leading `#`, in either `RRGGBB` or
    /// the short `RGB` form (each nibble doubled). Throws
    /// ``GrahamError/invalidArgument(_:)`` naming the input on any other form.
    public static func parse(_ input: String) throws -> SheetsColor {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let normalized: String
        switch hex.count {
        case 3:
            normalized = hex.map { "\($0)\($0)" }.joined()
        case 6:
            normalized = hex
        default:
            throw Self.parseError(input)
        }
        let digits = Array(normalized)
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw Self.parseError(input)
        }
        func channel(_ start: Int) -> Double {
            Double(Int(String(digits[start..<start + 2]), radix: 16) ?? 0) / 255
        }
        return SheetsColor(red: channel(0), green: channel(2), blue: channel(4))
    }

    private static func parseError(_ input: String) -> GrahamError {
        GrahamError.invalidArgument(
            "could not parse \"\(input)\" as a hex color; use #RRGGBB or #RGB")
    }
}

/// A non-deprecated `ColorStyle`. Sheets' `ColorStyle` is a union of a themed
/// color and an explicit `rgbColor`; graham always uses the `rgbColor` arm.
///
/// Prefer this over the deprecated `color`/`backgroundColor`/`foregroundColor`
/// fields for every writable color.
public struct SheetsColorStyle: Codable, Sendable, Equatable {
    public let rgbColor: SheetsColor

    public init(rgbColor: SheetsColor) {
        self.rgbColor = rgbColor
    }
}

/// Horizontal cell alignment.
public enum SheetsHorizontalAlignment: String, Sendable, CaseIterable, Equatable {
    case left = "LEFT"
    case center = "CENTER"
    case right = "RIGHT"
}

/// The writable text format of a cell.
///
/// `foregroundColorStyle` is the non-deprecated text color; `fontFamily` and
/// `fontSize` (in points) set the typeface. Every field is optional so the
/// caller sets only what it changes.
public struct SheetsTextFormat: Codable, Sendable, Equatable {
    public let bold: Bool?
    public let foregroundColorStyle: SheetsColorStyle?
    public let fontFamily: String?
    public let fontSize: Int?

    public init(
        bold: Bool? = nil,
        foregroundColorStyle: SheetsColorStyle? = nil,
        fontFamily: String? = nil,
        fontSize: Int? = nil
    ) {
        self.bold = bold
        self.foregroundColorStyle = foregroundColorStyle
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }
}

/// The kind of a cell number format. The default is `number`; the other kinds
/// map to Sheets' `NumberFormatType` values.
public enum SheetsNumberFormatType: String, Sendable, CaseIterable, Equatable {
    case text = "TEXT"
    case number = "NUMBER"
    case percent = "PERCENT"
    case currency = "CURRENCY"
    case date = "DATE"
    case time = "TIME"
    case dateTime = "DATE_TIME"
    case scientific = "SCIENTIFIC"
}

/// A cell number format: a required `type` and an optional `pattern`. Some
/// types (for example `PERCENT`) render with a Sheets default when no pattern
/// is given.
public struct SheetsNumberFormat: Codable, Sendable, Equatable {
    public let type: String
    public let pattern: String?

    public init(type: String, pattern: String? = nil) {
        self.type = type
        self.pattern = pattern
    }
}

/// The writable subset of a cell's format that `sheets format` sets.
///
/// `backgroundColorStyle` is the non-deprecated background color that
/// `sheets format` writes; the deprecated `backgroundColor` remains for
/// conditional-format rules that still take a bare `Color`. Set at most one of
/// the two. A field left `nil` while its path is named in the `repeatCell` mask
/// clears that aspect back to the cell default.
public struct SheetsCellFormat: Codable, Sendable, Equatable {
    public let backgroundColor: SheetsColor?
    public let backgroundColorStyle: SheetsColorStyle?
    public let textFormat: SheetsTextFormat?
    public let numberFormat: SheetsNumberFormat?
    public let horizontalAlignment: String?

    public init(
        backgroundColor: SheetsColor? = nil,
        backgroundColorStyle: SheetsColorStyle? = nil,
        textFormat: SheetsTextFormat? = nil,
        numberFormat: SheetsNumberFormat? = nil,
        horizontalAlignment: String? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.backgroundColorStyle = backgroundColorStyle
        self.textFormat = textFormat
        self.numberFormat = numberFormat
        self.horizontalAlignment = horizontalAlignment
    }
}

/// The `cell` payload of a `repeatCell`: the format to stamp across the range.
public struct SheetsCellData: Codable, Sendable, Equatable {
    public let userEnteredFormat: SheetsCellFormat

    public init(userEnteredFormat: SheetsCellFormat) {
        self.userEnteredFormat = userEnteredFormat
    }
}

/// The `repeatCell` operation. `fields` is a mask of the cell paths to write
/// (for example `userEnteredFormat.textFormat.bold`).
public struct RepeatCellRequest: Codable, Sendable, Equatable {
    public let range: GridRange
    public let cell: SheetsCellData
    public let fields: String

    public init(range: GridRange, cell: SheetsCellData, fields: String) {
        self.range = range
        self.cell = cell
        self.fields = fields
    }
}

// MARK: - Cell borders (updateBorders)

/// A line style for one cell border edge. `none` clears an edge.
public enum SheetsBorderStyle: String, Sendable, CaseIterable, Equatable {
    case solid = "SOLID"
    case solidMedium = "SOLID_MEDIUM"
    case solidThick = "SOLID_THICK"
    case dashed = "DASHED"
    case dotted = "DOTTED"
    case double = "DOUBLE"
    case none = "NONE"
}

/// One cell border edge: a line `style` plus an optional non-deprecated
/// `colorStyle`. Google defaults an omitted color to black.
public struct SheetsBorder: Codable, Sendable, Equatable {
    public let style: String
    public let colorStyle: SheetsColorStyle?

    public init(style: String, colorStyle: SheetsColorStyle? = nil) {
        self.style = style
        self.colorStyle = colorStyle
    }
}

/// The `updateBorders` operation.
///
/// Unlike `repeatCell`, this operation has NO `fields` mask: only the sides
/// present in the request are changed, and a side sent with the `NONE` style
/// clears that border. Every side is optional so the caller sets only the ones
/// it names.
public struct UpdateBordersRequest: Codable, Sendable, Equatable {
    public let range: GridRange
    public let top: SheetsBorder?
    public let bottom: SheetsBorder?
    public let left: SheetsBorder?
    public let right: SheetsBorder?
    public let innerHorizontal: SheetsBorder?
    public let innerVertical: SheetsBorder?

    public init(
        range: GridRange,
        top: SheetsBorder? = nil,
        bottom: SheetsBorder? = nil,
        left: SheetsBorder? = nil,
        right: SheetsBorder? = nil,
        innerHorizontal: SheetsBorder? = nil,
        innerVertical: SheetsBorder? = nil
    ) {
        self.range = range
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.innerHorizontal = innerHorizontal
        self.innerVertical = innerVertical
    }
}

// MARK: - Merge cells

/// How a `mergeCells` operation combines the cells in its range.
public enum SheetsMergeType: String, Sendable, CaseIterable, Equatable {
    /// Merge the whole range into one cell.
    case mergeAll = "MERGE_ALL"
    /// Merge each column of the range into one cell per column.
    case mergeColumns = "MERGE_COLUMNS"
    /// Merge each row of the range into one cell per row.
    case mergeRows = "MERGE_ROWS"
}

/// The `mergeCells` operation. `mergeType` is a ``SheetsMergeType`` raw value.
public struct MergeCellsRequest: Codable, Sendable, Equatable {
    public let range: GridRange
    public let mergeType: String

    public init(range: GridRange, mergeType: String) {
        self.range = range
        self.mergeType = mergeType
    }
}

/// The `unmergeCells` operation. Splits any merged cells overlapping the range.
public struct UnmergeCellsRequest: Codable, Sendable, Equatable {
    public let range: GridRange

    public init(range: GridRange) {
        self.range = range
    }
}

// MARK: - Sort range

/// The direction a sort spec orders its column.
public enum SheetsSortOrder: String, Sendable, CaseIterable, Equatable {
    case ascending = "ASCENDING"
    case descending = "DESCENDING"
}

/// One sort key of a `sortRange`. `dimensionIndex` is the ZERO-BASED column
/// index of the sort key within the sheet (not within the range).
public struct SortSpec: Codable, Sendable, Equatable {
    public let dimensionIndex: Int
    public let sortOrder: String

    public init(dimensionIndex: Int, sortOrder: String) {
        self.dimensionIndex = dimensionIndex
        self.sortOrder = sortOrder
    }
}

/// The `sortRange` operation: sorts the rows of `range` by `sortSpecs`, in
/// order (the first spec is the primary key).
public struct SortRangeRequest: Codable, Sendable, Equatable {
    public let range: GridRange
    public let sortSpecs: [SortSpec]

    public init(range: GridRange, sortSpecs: [SortSpec]) {
        self.range = range
        self.sortSpecs = sortSpecs
    }
}

/// A CLI-friendly sort key for ``SheetsClient/sortRange(spreadsheetId:range:specs:)``.
/// `column` is a ONE-BASED column position within the sorted range; the client
/// translates it to an absolute zero-based sheet ``SortSpec/dimensionIndex``.
public struct SheetsSortKey: Sendable, Equatable {
    public let column: Int
    public let order: SheetsSortOrder

    public init(column: Int, order: SheetsSortOrder) {
        self.column = column
        self.order = order
    }

    /// Parses a `--by` token of the form `col` or `col:asc` / `col:desc` (case
    /// insensitive), where `col` is a one-based column within the range. A bare
    /// column defaults to ascending. Throws ``GrahamError/invalidArgument(_:)``
    /// on any other form.
    public static func parse(_ input: String) throws -> SheetsSortKey {
        let parts = input.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else {
            throw GrahamError.invalidArgument(
                "invalid --by \"\(input)\"; use <col> or <col>:asc / <col>:desc")
        }
        guard let column = Int(parts[0]), column >= 1 else {
            throw GrahamError.invalidArgument(
                "invalid --by \"\(input)\"; the column must be a one-based number")
        }
        let order: SheetsSortOrder
        if parts.count == 2 {
            switch parts[1].lowercased() {
            case "asc", "ascending":
                order = .ascending
            case "desc", "descending":
                order = .descending
            default:
                throw GrahamError.invalidArgument(
                    "invalid --by \"\(input)\"; the order must be asc or desc")
            }
        } else {
            order = .ascending
        }
        return SheetsSortKey(column: column, order: order)
    }
}

// MARK: - Auto-resize dimensions

/// The `autoResizeDimensions` operation: sizes each row or column in
/// `dimensions` to fit its contents.
public struct AutoResizeDimensionsRequest: Codable, Sendable, Equatable {
    public let dimensions: DimensionRange

    public init(dimensions: DimensionRange) {
        self.dimensions = dimensions
    }
}

// MARK: - Named ranges

/// The `namedRange` payload of an `addNamedRange`: a name and the rectangle it
/// covers. `namedRangeId` is deliberately absent — Google assigns it and
/// reports it in the batch-update reply.
public struct NamedRangeRequest: Codable, Sendable, Equatable {
    public let name: String
    public let range: GridRange

    public init(name: String, range: GridRange) {
        self.name = name
        self.range = range
    }
}

/// The `addNamedRange` operation.
public struct AddNamedRangeRequest: Codable, Sendable, Equatable {
    public let namedRange: NamedRangeRequest

    public init(namedRange: NamedRangeRequest) {
        self.namedRange = namedRange
    }
}

/// The `deleteNamedRange` operation.
public struct DeleteNamedRangeRequest: Codable, Sendable, Equatable {
    public let namedRangeId: String

    public init(namedRangeId: String) {
        self.namedRangeId = namedRangeId
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
    public let addFilterView: AddFilterViewReply?
    public let addProtectedRange: AddProtectedRangeReply?
    public let addNamedRange: AddNamedRangeReply?
}

/// The reply of an `addNamedRange` operation, carrying the new range's id.
public struct AddNamedRangeReply: Codable, Sendable {
    public let namedRange: AddedNamedRange?
}

/// The server-assigned identity of a newly added named range.
public struct AddedNamedRange: Codable, Sendable {
    public let namedRangeId: String?
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

// MARK: - Boolean condition (shared)

/// One value in a ``SheetsBooleanCondition``. Every value is a user-entered
/// string, matching how a person would type it into the Sheets UI; Sheets
/// interprets numbers, dates, and formulas from the text.
public struct SheetsConditionValue: Codable, Sendable, Equatable {
    public let userEnteredValue: String

    public init(userEnteredValue: String) {
        self.userEnteredValue = userEnteredValue
    }
}

/// A boolean condition shared by conditional formatting and data validation.
/// `type` is a ``SheetsConditionType`` raw value; `values` supplies the operands
/// the type needs (none for BLANK/NOT_BLANK, two for the *_BETWEEN types).
public struct SheetsBooleanCondition: Codable, Sendable, Equatable {
    public let type: String
    public let values: [SheetsConditionValue]

    public init(type: String, values: [SheetsConditionValue]) {
        self.type = type
        self.values = values
    }
}

/// The boolean-condition types graham exposes on the CLI. The raw values are the
/// Sheets `ConditionType` enum names.
public enum SheetsConditionType: String, Sendable, CaseIterable, Equatable {
    case numberGreater = "NUMBER_GREATER"
    case numberGreaterThanEq = "NUMBER_GREATER_THAN_EQ"
    case numberLess = "NUMBER_LESS"
    case numberLessThanEq = "NUMBER_LESS_THAN_EQ"
    case numberEq = "NUMBER_EQ"
    case numberNotEq = "NUMBER_NOT_EQ"
    case numberBetween = "NUMBER_BETWEEN"
    case numberNotBetween = "NUMBER_NOT_BETWEEN"
    case textContains = "TEXT_CONTAINS"
    case textNotContains = "TEXT_NOT_CONTAINS"
    case textStartsWith = "TEXT_STARTS_WITH"
    case textEndsWith = "TEXT_ENDS_WITH"
    case textEq = "TEXT_EQ"
    case textIsEmail = "TEXT_IS_EMAIL"
    case textIsUrl = "TEXT_IS_URL"
    case dateBefore = "DATE_BEFORE"
    case dateAfter = "DATE_AFTER"
    case dateOnOrBefore = "DATE_ON_OR_BEFORE"
    case dateOnOrAfter = "DATE_ON_OR_AFTER"
    case blank = "BLANK"
    case notBlank = "NOT_BLANK"
    case oneOfList = "ONE_OF_LIST"
    case boolean = "BOOLEAN"
    case customFormula = "CUSTOM_FORMULA"

    /// How many `--value` arguments a condition type needs, where the type makes
    /// the count unambiguous.
    public enum ValueArity: Sendable, Equatable {
        /// Exactly zero values.
        case none
        /// Exactly two values.
        case pair
        /// At least one value.
        case oneOrMore
    }

    /// The value count graham validates: zero for BLANK/NOT_BLANK, two for the
    /// *_BETWEEN types, otherwise one or more.
    public var valueArity: ValueArity {
        switch self {
        case .blank, .notBlank:
            return .none
        case .numberBetween, .numberNotBetween:
            return .pair
        default:
            return .oneOrMore
        }
    }
}

extension SheetsBooleanCondition {
    /// Builds a boolean condition from a type and its user-entered values,
    /// validating the number of values against the type where the count is
    /// unambiguous. Throws ``GrahamError/invalidArgument(_:)`` on a bad count so
    /// no request is ever sent.
    public static func make(
        type: SheetsConditionType,
        values: [String]
    ) throws -> SheetsBooleanCondition {
        switch type.valueArity {
        case .none:
            guard values.isEmpty else {
                throw GrahamError.invalidArgument(
                    "the \(type.rawValue) condition takes no --value arguments")
            }
        case .pair:
            guard values.count == 2 else {
                throw GrahamError.invalidArgument(
                    "the \(type.rawValue) condition needs exactly two --value arguments")
            }
        case .oneOrMore:
            guard !values.isEmpty else {
                throw GrahamError.invalidArgument(
                    "the \(type.rawValue) condition needs at least one --value argument")
            }
        }
        return SheetsBooleanCondition(
            type: type.rawValue,
            values: values.map { SheetsConditionValue(userEnteredValue: $0) })
    }
}

// MARK: - Conditional formatting

/// A gradient (color-scale) rule. graham does not yet build one from the CLI,
/// but the field is modeled so a ``ConditionalFormatRule`` decodes and re-encodes
/// faithfully; a future slice can populate its interpolation points.
public struct GradientRule: Codable, Sendable, Equatable {
    public let minpoint: InterpolationPoint?
    public let midpoint: InterpolationPoint?
    public let maxpoint: InterpolationPoint?

    public init(
        minpoint: InterpolationPoint? = nil,
        midpoint: InterpolationPoint? = nil,
        maxpoint: InterpolationPoint? = nil
    ) {
        self.minpoint = minpoint
        self.midpoint = midpoint
        self.maxpoint = maxpoint
    }
}

/// One stop in a ``GradientRule``: a color, a `type` (such as `MIN`, `MAX`,
/// `NUMBER`, `PERCENT`), and the `value` the type reads.
public struct InterpolationPoint: Codable, Sendable, Equatable {
    public let color: SheetsColor?
    public let type: String?
    public let value: String?

    public init(color: SheetsColor? = nil, type: String? = nil, value: String? = nil) {
        self.color = color
        self.type = type
        self.value = value
    }
}

/// A boolean conditional-format rule: when `condition` matches a cell, `format`
/// is stamped over it.
public struct BooleanRule: Codable, Sendable, Equatable {
    public let condition: SheetsBooleanCondition
    public let format: SheetsCellFormat

    public init(condition: SheetsBooleanCondition, format: SheetsCellFormat) {
        self.condition = condition
        self.format = format
    }
}

/// A conditional-format rule over one or more ranges: exactly one of
/// `booleanRule` or `gradientRule` is set.
public struct ConditionalFormatRule: Codable, Sendable, Equatable {
    public let ranges: [GridRange]
    public let booleanRule: BooleanRule?
    public let gradientRule: GradientRule?

    public init(
        ranges: [GridRange],
        booleanRule: BooleanRule? = nil,
        gradientRule: GradientRule? = nil
    ) {
        self.ranges = ranges
        self.booleanRule = booleanRule
        self.gradientRule = gradientRule
    }
}

/// The `addConditionalFormatRule` operation. `index` is the zero-based position
/// the rule is inserted at within the sheet's rule list.
public struct AddConditionalFormatRuleRequest: Codable, Sendable, Equatable {
    public let rule: ConditionalFormatRule
    public let index: Int

    public init(rule: ConditionalFormatRule, index: Int) {
        self.rule = rule
        self.index = index
    }
}

/// The `deleteConditionalFormatRule` operation: removes the rule at `index` on
/// `sheetId`.
public struct DeleteConditionalFormatRuleRequest: Codable, Sendable, Equatable {
    public let sheetId: Int
    public let index: Int

    public init(sheetId: Int, index: Int) {
        self.sheetId = sheetId
        self.index = index
    }
}

// MARK: - Data validation

/// A data-validation rule for a range. A `nil` rule on a `setDataValidation`
/// request clears validation instead of setting it.
public struct DataValidationRule: Codable, Sendable, Equatable {
    public let condition: SheetsBooleanCondition
    public let inputMessage: String?
    public let strict: Bool?
    public let showCustomUi: Bool?

    public init(
        condition: SheetsBooleanCondition,
        inputMessage: String? = nil,
        strict: Bool? = nil,
        showCustomUi: Bool? = nil
    ) {
        self.condition = condition
        self.inputMessage = inputMessage
        self.strict = strict
        self.showCustomUi = showCustomUi
    }
}

/// The `setDataValidation` operation. A `nil` `rule` clears validation on
/// `range`.
public struct SetDataValidationRequest: Codable, Sendable, Equatable {
    public let range: GridRange
    public let rule: DataValidationRule?

    public init(range: GridRange, rule: DataValidationRule? = nil) {
        self.range = range
        self.rule = rule
    }
}

// MARK: - Basic filter and filter views

/// A basic filter over a range. graham keeps it to the range for now; sort and
/// per-column filter criteria can join later.
public struct BasicFilter: Codable, Sendable, Equatable {
    public let range: GridRange

    public init(range: GridRange) {
        self.range = range
    }
}

/// The `setBasicFilter` operation.
public struct SetBasicFilterRequest: Codable, Sendable, Equatable {
    public let filter: BasicFilter

    public init(filter: BasicFilter) {
        self.filter = filter
    }
}

/// The `clearBasicFilter` operation: removes the basic filter from `sheetId`.
public struct ClearBasicFilterRequest: Codable, Sendable, Equatable {
    public let sheetId: Int

    public init(sheetId: Int) {
        self.sheetId = sheetId
    }
}

/// A filter view to add: a titled, saved view over a range.
///
/// `filterViewId` is deliberately absent: Google assigns it and reports it in
/// the batch-update reply.
public struct FilterViewRequest: Codable, Sendable, Equatable {
    public let title: String
    public let range: GridRange

    public init(title: String, range: GridRange) {
        self.title = title
        self.range = range
    }
}

/// The `addFilterView` operation.
public struct AddFilterViewRequest: Codable, Sendable, Equatable {
    public let filter: FilterViewRequest

    public init(filter: FilterViewRequest) {
        self.filter = filter
    }
}

// MARK: - Protected ranges

/// A protected range to add. `warningOnly` makes the protection advisory (edits
/// are warned about, not blocked). `protectedRangeId` is absent: Google assigns
/// it and reports it in the reply.
public struct ProtectedRangeRequest: Codable, Sendable, Equatable {
    public let range: GridRange
    public let description: String?
    public let warningOnly: Bool?

    public init(range: GridRange, description: String? = nil, warningOnly: Bool? = nil) {
        self.range = range
        self.description = description
        self.warningOnly = warningOnly
    }
}

/// The `addProtectedRange` operation.
public struct AddProtectedRangeRequest: Codable, Sendable, Equatable {
    public let protectedRange: ProtectedRangeRequest

    public init(protectedRange: ProtectedRangeRequest) {
        self.protectedRange = protectedRange
    }
}

/// The `deleteProtectedRange` operation: removes the protected range with id
/// `protectedRangeId`.
public struct DeleteProtectedRangeRequest: Codable, Sendable, Equatable {
    public let protectedRangeId: Int

    public init(protectedRangeId: Int) {
        self.protectedRangeId = protectedRangeId
    }
}

// MARK: - Data-tooling replies

/// The reply of an `addFilterView` operation, carrying the new view's id.
public struct AddFilterViewReply: Codable, Sendable {
    public let filter: AddedFilterView?
}

/// The server-assigned identity of a newly added filter view.
public struct AddedFilterView: Codable, Sendable {
    public let filterViewId: Int?
}

/// The reply of an `addProtectedRange` operation, carrying the new range's id.
public struct AddProtectedRangeReply: Codable, Sendable {
    public let protectedRange: AddedProtectedRange?
}

/// The server-assigned identity of a newly added protected range.
public struct AddedProtectedRange: Codable, Sendable {
    public let protectedRangeId: Int?
}
