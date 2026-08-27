import ArgumentParser
import Foundation
import GrahamKit

struct Sheets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Sheets spreadsheets.",
        subcommands: [
            Get.self, Values.self, Set.self, Append.self, Clear.self, Tab.self,
            Freeze.self, Resize.self, Format.self, Chart.self, Test.self,
            ConditionalFormat.self, Validation.self, Filter.self, FilterView.self,
            Protect.self,
            Border.self,
            Merge.self, Unmerge.self, Sort.self, Autoresize.self, NamedRange.self,
        ]
    )

    /// Resolves the sheet a grid command targets: an explicit id, a title, or —
    /// when neither is given — the spreadsheet's first sheet.
    enum SheetTarget {
        static func validate(sheetId: Int?, sheet: String?) throws {
            guard !(sheetId != nil && sheet != nil) else {
                throw ValidationError(
                    "Select the sheet with at most one of --sheet-id or --sheet.")
            }
        }

        static func resolve(
            _ client: SheetsClient,
            spreadsheetID: String,
            sheetId: Int?,
            sheet: String?
        ) async throws -> Int {
            if let sheetId { return sheetId }
            if let sheet {
                return try await client.sheetId(spreadsheetId: spreadsheetID, title: sheet)
            }
            return try await client.firstSheetId(spreadsheetId: spreadsheetID)
        }
    }

    /// Resolves the rows a `set` / `append` command writes from its chosen input
    /// mode. The parsing lives in `SheetsRowInput`; only the stdin read is a CLI
    /// concern. The command's `validate()` guarantees exactly one mode is set.
    static func rowsInput(row: [String], jsonRows: String?, tsv: Bool) throws -> [[String]] {
        if let jsonRows {
            return try SheetsRowInput.fromJSON(jsonRows)
        }
        if tsv {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return try SheetsRowInput.fromTSV(String(decoding: data, as: UTF8.self))
        }
        return try SheetsRowInput.fromCommaRows(row)
    }

    struct Test: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the live end-to-end Sheets smoke test.",
            discussion: """
                Creates a spreadsheet inside a folder in My Drive, exercises \
                graham's Sheets API surface (a values write and read-back, the \
                spreadsheet metadata, and a chart add), and trashes the \
                spreadsheet afterward. The folder remains. Use --keep to retain \
                the spreadsheet for inspection. The command exits nonzero when \
                any step fails.
                """
        )

        @Flag(help: "Keep the spreadsheet after the run.")
        var keep = false

        @Option(help: "The root-level My Drive folder to find or create.")
        var folder = "graham test"

        func run() async throws {
            let api = try CLI.makeAPI()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let label = formatter.string(from: Date())
            let runner = SheetsLiveTest(
                drive: DriveClient(api: api),
                sheets: SheetsClient(api: api),
                folderName: folder,
                keep: keep,
                label: label,
                onStep: { step in
                    let ids = step.createdIDs.isEmpty
                        ? ""
                        : " [\(step.createdIDs.joined(separator: ", "))]"
                    switch step.outcome {
                    case .pass:
                        print("\(StatusColor.green.wrap("PASS")) \(step.name)\(ids)")
                    case .fail(let reason):
                        print("\(StatusColor.red.wrap("FAIL")) \(step.name): \(reason)\(ids)")
                    case .skip(let reason):
                        print("\(StatusColor.yellow.wrap("SKIP")) \(step.name): \(reason)\(ids)")
                    }
                }
            )
            let summary = await runner.run()
            print(
                "Summary: \(summary.passed) passed, \(summary.failed) failed, "
                    + "\(summary.skipped) skipped"
            )
            if summary.failed > 0 {
                throw ExitCode.failure
            }
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show a spreadsheet's title, its sheets, and any charts."
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Option(help: "The output format: table, json, jsonl, or id.")
        var format: OutputFormat = .table

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let spreadsheet = try await client.spreadsheet(id: spreadsheetID)
            if format == .json {
                try CLI.printJSON(spreadsheet)
                return
            }
            if format == .table, let title = spreadsheet.properties?.title {
                print(title)
            }
            print(try OutputFormatter.render(spreadsheet.sheets ?? [], format: format))

            // In table format, list any embedded charts under the sheets.
            let charts = (spreadsheet.sheets ?? []).flatMap { $0.charts ?? [] }
            if format == .table, !charts.isEmpty {
                print("")
                print("Charts:")
                print(try OutputFormatter.render(charts, format: format))
            }
        }
    }

    struct Values: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read cell values from one or more ranges, as tab-separated lines.",
            discussion: """
                Pass one range for a single read, or several ranges for a
                batchGet. With more than one range, each block is preceded by a
                '# <range>' header line and separated by a blank line. Use --raw
                for unformatted values or --formulas for cell formulas.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "One or more ranges in A1 notation, e.g. 'Sheet1!A1:C10' or 'Sheet1'.")
        var ranges: [String]

        @Flag(help: "Return raw unformatted values instead of formatted text.")
        var raw = false

        @Flag(help: "Return cell formulas instead of computed values.")
        var formulas = false

        @Flag(help: "Print the raw ValueRange(s) as JSON instead of tab-separated lines.")
        var json = false

        func validate() throws {
            guard !ranges.isEmpty else {
                throw ValidationError("Provide at least one range to read.")
            }
            guard !(raw && formulas) else {
                throw ValidationError(
                    "Pass either --raw or --formulas, not both: --raw returns "
                    + "unformatted values and --formulas returns cell formulas.")
            }
        }

        func run() async throws {
            let renderOption: SheetsValueRenderOption? =
                raw ? .unformatted : (formulas ? .formula : nil)
            let client = SheetsClient(api: try CLI.makeAPI())
            if ranges.count == 1 {
                let valueRange = try await client.values(
                    spreadsheetId: spreadsheetID, range: ranges[0], renderOption: renderOption)
                if json {
                    try CLI.printJSON(valueRange)
                    return
                }
                Self.printRows(valueRange)
                return
            }
            let response = try await client.batchGetValues(
                spreadsheetId: spreadsheetID, ranges: ranges, renderOption: renderOption)
            if json {
                try CLI.printJSON(response)
                return
            }
            for (index, valueRange) in (response.valueRanges ?? []).enumerated() {
                if index > 0 { print("") }
                print("# \(valueRange.range ?? ranges[index])")
                Self.printRows(valueRange)
            }
        }

        private static func printRows(_ valueRange: ValueRange) {
            for row in valueRange.values ?? [] {
                print(row.map(\.display).joined(separator: "\t"))
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write rows of cell values to a range.",
            discussion: """
                Provide exactly one input form:
                  --row       a comma-separated row of cells, repeated per row.
                              This form has no escaping: every comma starts the
                              next cell.
                  --json-rows a JSON array of arrays of strings, e.g.
                              '[["Label","Value"],["A, B","10"]]'. Cells may
                              contain commas.
                  --tsv       read tab-separated rows from stdin (one row per
                              line), so a `graham sheets values` read pipes
                              straight back in. Cells may contain commas.
                Values use Sheets' USER_ENTERED mode, so numeric strings become
                numbers.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The destination range in A1 notation, for example 'Sheet1!A1:B3'.")
        var range: String

        @Option(help: "One comma-separated row of cells. Repeat for more rows.")
        var row: [String] = []

        @Option(help: "Rows as a JSON array of arrays of strings. Cells may contain commas.")
        var jsonRows: String?

        @Flag(help: "Read tab-separated rows from stdin (one row per line).")
        var tsv = false

        func validate() throws {
            let modes = [!row.isEmpty, jsonRows != nil, tsv].filter { $0 }.count
            guard modes == 1 else {
                throw ValidationError(
                    "Provide exactly one input: one or more --row, a --json-rows "
                    + "array, or --tsv on stdin.")
            }
        }

        func run() async throws {
            let rows = try Sheets.rowsInput(row: row, jsonRows: jsonRows, tsv: tsv)
            let client = SheetsClient(api: try CLI.makeAPI())
            let response = try await client.setValues(
                spreadsheetId: spreadsheetID,
                range: range,
                values: rows
            )
            print(response.updatedCells ?? 0)
        }
    }

    struct Append: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Append rows after the table found within a range.",
            discussion: """
                Sheets locates the table that overlaps the range and inserts the
                rows just below it, so you do not compute the next free row. The
                input forms match `sheets set`: --row, --json-rows, or --tsv.
                Prints the number of updated cells.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "A range that overlaps the target table, e.g. 'Sheet1!A1'.")
        var range: String

        @Option(help: "One comma-separated row of cells. Repeat for more rows.")
        var row: [String] = []

        @Option(help: "Rows as a JSON array of arrays of strings. Cells may contain commas.")
        var jsonRows: String?

        @Flag(help: "Read tab-separated rows from stdin (one row per line).")
        var tsv = false

        func validate() throws {
            let modes = [!row.isEmpty, jsonRows != nil, tsv].filter { $0 }.count
            guard modes == 1 else {
                throw ValidationError(
                    "Provide exactly one input: one or more --row, a --json-rows "
                    + "array, or --tsv on stdin.")
            }
        }

        func run() async throws {
            let rows = try Sheets.rowsInput(row: row, jsonRows: jsonRows, tsv: tsv)
            let client = SheetsClient(api: try CLI.makeAPI())
            let response = try await client.appendValues(
                spreadsheetId: spreadsheetID,
                range: range,
                values: rows
            )
            print(response.updates?.updatedCells ?? 0)
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Clear the cell values in a range, leaving formatting intact.",
            discussion: "Prints the range that was cleared."
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The range to clear, in A1 notation, for example 'Sheet1!A1:B10'.")
        var range: String

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let response = try await client.clearValues(
                spreadsheetId: spreadsheetID, range: range)
            print(response.clearedRange ?? "")
        }
    }

    struct Tab: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage the sheets (tabs) within a spreadsheet.",
            subcommands: [Add.self, Delete.self, Rename.self]
        )

        /// Resolves a tab either from an explicit numeric id or from its current
        /// title. The subcommands validate that exactly one selector is set.
        static func resolveSheetId(
            _ client: SheetsClient,
            spreadsheetID: String,
            sheetId: Int?,
            sheet: String?
        ) async throws -> Int {
            if let sheetId { return sheetId }
            return try await client.sheetId(spreadsheetId: spreadsheetID, title: sheet ?? "")
        }

        static func validateSelector(sheetId: Int?, sheet: String?) throws {
            let selectors = [sheetId != nil, sheet != nil].filter { $0 }.count
            guard selectors == 1 else {
                throw ValidationError(
                    "Select the tab with exactly one of --sheet-id or --sheet.")
            }
        }

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Add a new tab and print its numeric sheet id."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The title of the new tab.")
            var title: String

            @Option(help: "One-based position for the new tab. Omit to append it at the end.")
            var index: Int?

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let properties = try await client.addSheet(
                    spreadsheetId: spreadsheetID, title: title, position: index)
                print(properties.sheetId.map(String.init) ?? "")
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a tab by its id or current title."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The numeric sheet id of the tab to delete.")
            var sheetId: Int?

            @Option(help: "The current title of the tab to delete.")
            var sheet: String?

            func validate() throws {
                try Tab.validateSelector(sheetId: sheetId, sheet: sheet)
            }

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await Tab.resolveSheetId(
                    client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
                try await client.deleteSheet(spreadsheetId: spreadsheetID, sheetId: id)
            }
        }

        struct Rename: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Rename a tab, selected by its id or current title."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The numeric sheet id of the tab to rename.")
            var sheetId: Int?

            @Option(help: "The current title of the tab to rename.")
            var sheet: String?

            @Option(help: "The new title.")
            var to: String

            func validate() throws {
                try Tab.validateSelector(sheetId: sheetId, sheet: sheet)
            }

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await Tab.resolveSheetId(
                    client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
                try await client.renameSheet(
                    spreadsheetId: spreadsheetID, sheetId: id, title: to)
            }
        }
    }

    struct Freeze: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Freeze rows and/or columns on a sheet.",
            discussion: """
                Give a row count, a column count, or both. Counts are inclusive
                (--rows 1 freezes the header row). Target a sheet with --sheet-id
                or --sheet; omit both to use the first sheet.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Option(help: "The number of rows to freeze from the top.")
        var rows: Int?

        @Option(help: "The number of columns to freeze from the left.")
        var columns: Int?

        @Option(help: "The numeric sheet id to target.")
        var sheetId: Int?

        @Option(help: "The title of the sheet to target.")
        var sheet: String?

        func validate() throws {
            try SheetTarget.validate(sheetId: sheetId, sheet: sheet)
            guard rows != nil || columns != nil else {
                throw ValidationError("Provide --rows and/or --columns to freeze.")
            }
        }

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let id = try await SheetTarget.resolve(
                client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
            try await client.freeze(
                spreadsheetId: spreadsheetID, sheetId: id, rows: rows, columns: columns)
        }
    }

    struct Resize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resize a span of rows or columns to a pixel size.",
            discussion: """
                --from and --to are one-based, inclusive positions; omit --to to
                resize a single row or column. Target a sheet with --sheet-id or
                --sheet; omit both to use the first sheet.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Option(help: "The dimension to resize: rows or columns.")
        var dimension: SheetsDimension

        @Option(help: "The first (one-based) row or column to resize.")
        var from: Int

        @Option(help: "The last (one-based) row or column to resize. Defaults to --from.")
        var to: Int?

        @Option(help: "The new size in pixels.")
        var pixels: Int

        @Option(help: "The numeric sheet id to target.")
        var sheetId: Int?

        @Option(help: "The title of the sheet to target.")
        var sheet: String?

        func validate() throws {
            try SheetTarget.validate(sheetId: sheetId, sheet: sheet)
        }

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let id = try await SheetTarget.resolve(
                client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
            try await client.resizeDimension(
                spreadsheetId: spreadsheetID,
                sheetId: id,
                dimension: dimension,
                start: from,
                end: to ?? from,
                pixelSize: pixels
            )
        }
    }

    struct Format: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Apply a cell format across a range.",
            discussion: """
                Set at least one aspect: --bold/--no-bold, --background,
                --text-color, --font, --font-size, --number-format,
                --number-type, or --align. Only the aspects you name are changed.

                To reset an aspect to the cell default, use --no-bold,
                --clear-background, --clear-number-format, or --clear-align; a
                set and a clear of the same aspect together are rejected. Colors
                are hex values (#RRGGBB or #RGB). The number format type defaults
                to NUMBER, so an existing --number-format pattern keeps its old
                behavior. The sheet comes from the range's tab name, or the first
                sheet when the range names none.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The range to format, for example 'Sheet1!A1:B1'.")
        var range: String

        @Flag(inversion: .prefixedNo, help: "Make the cells bold; --no-bold clears bold.")
        var bold: Bool?

        @Option(help: "Background color as a hex value, e.g. #FFCC00 or #FC0.")
        var background: String?

        @Flag(name: .customLong("clear-background"), help: "Clear the background to the cell default.")
        var clearBackground = false

        @Option(name: .customLong("text-color"), help: "Text color as a hex value, e.g. #202124.")
        var textColor: String?

        @Option(help: "The font family, e.g. 'Roboto' or 'Arial'.")
        var font: String?

        @Option(name: .customLong("font-size"), help: "The font size in points.")
        var fontSize: Int?

        @Option(name: .customLong("number-format"), help: "A number format pattern, e.g. '#,##0.00'.")
        var numberFormat: String?

        @Option(
            name: .customLong("number-type"),
            help: "The number format type: number, percent, currency, date, time, date_time, scientific, or text (default number).")
        var numberType: SheetsNumberFormatType?

        @Flag(
            name: .customLong("clear-number-format"),
            help: "Clear the number format to the cell default.")
        var clearNumberFormat = false

        @Option(help: "Horizontal alignment: left, center, or right.")
        var align: SheetsHorizontalAlignment?

        @Flag(name: .customLong("clear-align"), help: "Clear the horizontal alignment to the cell default.")
        var clearAlign = false

        func validate() throws {
            let touchesSomething = bold != nil
                || background != nil || clearBackground
                || textColor != nil || font != nil || fontSize != nil
                || numberFormat != nil || numberType != nil || clearNumberFormat
                || align != nil || clearAlign
            guard touchesSomething else {
                throw ValidationError(
                    "Provide at least one of --bold/--no-bold, --background, --text-color, "
                    + "--font, --font-size, --number-format, --number-type, or --align "
                    + "(or a --clear-* flag).")
            }
            if background != nil, clearBackground {
                throw ValidationError("Set --background or --clear-background, not both.")
            }
            if numberFormat != nil || numberType != nil, clearNumberFormat {
                throw ValidationError(
                    "Set --number-format/--number-type or --clear-number-format, not both.")
            }
            if align != nil, clearAlign {
                throw ValidationError("Set --align or --clear-align, not both.")
            }
        }

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let background = try self.background.map { try SheetsColor.parse($0) }
            let textColor = try self.textColor.map { try SheetsColor.parse($0) }
            try await client.formatCells(
                spreadsheetId: spreadsheetID,
                range: range,
                bold: bold,
                backgroundColor: background,
                clearBackground: clearBackground,
                numberFormat: numberFormat,
                numberFormatType: numberType,
                clearNumberFormat: clearNumberFormat,
                horizontalAlignment: align,
                clearAlignment: clearAlign,
                textColor: textColor,
                fontFamily: font,
                fontSize: fontSize
            )
        }
    }

    struct Border: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set or clear cell borders across a range.",
            discussion: """
                Choose the sides with --all, or any of --top, --bottom, --left,
                --right, and --inner (--inner draws the interior horizontal and
                vertical lines). Every chosen side gets the same --style and
                optional --color. Use --style none to clear the chosen sides. The
                sheet comes from the range's tab name, or the first sheet when the
                range names none.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The range to border, for example 'Sheet1!A1:B4'.")
        var range: String

        @Flag(help: "Apply to all four edges and the interior lines.")
        var all = false

        @Flag(help: "Apply to the top edge.")
        var top = false

        @Flag(help: "Apply to the bottom edge.")
        var bottom = false

        @Flag(help: "Apply to the left edge.")
        var left = false

        @Flag(help: "Apply to the right edge.")
        var right = false

        @Flag(help: "Apply to the interior horizontal and vertical lines.")
        var inner = false

        @Option(
            help: "The line style: solid, solid_medium, solid_thick, dashed, dotted, double, or none.")
        var style: SheetsBorderStyle

        @Option(help: "The border color as a hex value, e.g. #000000. Defaults to black.")
        var color: String?

        func validate() throws {
            guard all || top || bottom || left || right || inner else {
                throw ValidationError(
                    "Choose at least one side: --all, --top, --bottom, --left, --right, or --inner.")
            }
        }

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let color = try self.color.map { try SheetsColor.parse($0) }
            try await client.setBorders(
                spreadsheetId: spreadsheetID,
                range: range,
                style: style,
                color: color,
                top: all || top,
                bottom: all || bottom,
                left: all || left,
                right: all || right,
                innerHorizontal: all || inner,
                innerVertical: all || inner
            )
        }
    }

    struct Chart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Work with embedded spreadsheet charts.",
            subcommands: [Add.self, Update.self, Move.self, Delete.self]
        )

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Add a chart and print its chart id.",
                discussion: """
                    --kind selects the chart shape (default column). For column,
                    bar, line, area, scatter, and combo the first range column is
                    the domain and each remaining column is a series; pie uses the
                    first two columns; histogram turns every column into a series;
                    scorecard reads a key value (and optional baseline) from the
                    first one or two columns; candlestick reads exactly five
                    columns as domain, open, high, low, close. The first row
                    supplies headers. --type and --pie still work as aliases for
                    the matching --kind (a set --kind wins). --bucket-size and
                    --outlier-percentile tune a histogram; --aggregate sets a
                    scorecard aggregation. By default the chart lands on its own
                    new sheet; pass --anchor to overlay it on an existing sheet.
                    The printed numeric chart id can be passed to
                    `graham slides create chart --chart-id`.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The source range in bounded A1 notation.")
            var range: String

            @Option(help: "The chart title.")
            var title: String?

            @Option(help: """
                The chart kind: column, bar, line, area, scatter, combo, pie, \
                histogram, scorecard, or candlestick. Overrides --type/--pie.
                """)
            var kind: SheetsChartKind?

            @Option(help: "The basic chart type: column, bar, line, area, scatter, or combo.")
            var type: BasicChartType = .column

            @Flag(help: "Make a pie chart (uses the first two columns; ignores --type).")
            var pie = false

            @Option(name: .customLong("bucket-size"), help: "Histogram bucket size.")
            var bucketSize: Double?

            @Option(name: .customLong("outlier-percentile"),
                    help: "Histogram outlier percentile (0-1).")
            var outlierPercentile: Double?

            @Option(help: "Scorecard aggregation: average, count, max, median, min, or sum.")
            var aggregate: SheetsChartAggregateType?

            @Option(help: "Overlay the chart anchored to this A1 cell, e.g. 'Sheet2!D2'.")
            var anchor: String?

            @Option(help: "Overlay width in pixels (requires --anchor).")
            var width: Int?

            @Option(help: "Overlay height in pixels (requires --anchor).")
            var height: Int?

            func validate() throws {
                if anchor == nil, width != nil || height != nil {
                    throw ValidationError("--width and --height require --anchor.")
                }
            }

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let overlay = anchor.map {
                    ChartOverlay(anchor: $0, widthPixels: width, heightPixels: height)
                }
                let chartId = try await client.addChart(
                    spreadsheetId: spreadsheetID,
                    title: title,
                    type: type,
                    range: range,
                    pie: pie,
                    kind: kind,
                    bucketSize: bucketSize,
                    outlierPercentile: outlierPercentile,
                    aggregate: aggregate,
                    overlay: overlay
                )
                print(chartId)
            }
        }

        struct Update: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Replace a chart's spec, rebuilt from a range and kind.",
                discussion: """
                    --kind selects the chart shape, exactly as `chart add`;
                    --type and --pie remain aliases (a set --kind wins).
                    --bucket-size/--outlier-percentile tune a histogram and
                    --aggregate sets a scorecard aggregation.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The numeric chart id to update.")
            var chartId: Int

            @Option(help: "The source range in bounded A1 notation.")
            var range: String

            @Option(help: "The chart title.")
            var title: String?

            @Option(help: """
                The chart kind: column, bar, line, area, scatter, combo, pie, \
                histogram, scorecard, or candlestick. Overrides --type/--pie.
                """)
            var kind: SheetsChartKind?

            @Option(help: "The basic chart type: column, bar, line, area, scatter, or combo.")
            var type: BasicChartType = .column

            @Flag(help: "Make a pie chart (uses the first two columns; ignores --type).")
            var pie = false

            @Option(name: .customLong("bucket-size"), help: "Histogram bucket size.")
            var bucketSize: Double?

            @Option(name: .customLong("outlier-percentile"),
                    help: "Histogram outlier percentile (0-1).")
            var outlierPercentile: Double?

            @Option(help: "Scorecard aggregation: average, count, max, median, min, or sum.")
            var aggregate: SheetsChartAggregateType?

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.updateChart(
                    spreadsheetId: spreadsheetID,
                    chartId: chartId,
                    title: title,
                    type: type,
                    range: range,
                    pie: pie,
                    kind: kind,
                    bucketSize: bucketSize,
                    outlierPercentile: outlierPercentile,
                    aggregate: aggregate
                )
            }
        }

        struct Move: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Move or resize an embedded chart.",
                discussion: """
                    Choose exactly one placement: --anchor overlays the chart on
                    an existing sheet at an A1 cell (optionally sized with --width
                    and --height), or --new-sheet moves it onto its own new sheet.
                    The anchor's sheet comes from its tab name, or the first sheet
                    when it names none.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The numeric chart id to move.")
            var chartId: Int

            @Option(help: "Overlay the chart anchored to this A1 cell, e.g. 'Sheet2!D2'.")
            var anchor: String?

            @Option(help: "Overlay width in pixels (requires --anchor).")
            var width: Int?

            @Option(help: "Overlay height in pixels (requires --anchor).")
            var height: Int?

            @Flag(help: "Move the chart onto its own new sheet.")
            var newSheet = false

            func validate() throws {
                let placements = [anchor != nil, newSheet].filter { $0 }.count
                guard placements == 1 else {
                    throw ValidationError(
                        "Choose exactly one placement: --anchor or --new-sheet.")
                }
                if newSheet, width != nil || height != nil {
                    throw ValidationError("--width and --height require --anchor.")
                }
            }

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.moveChart(
                    spreadsheetId: spreadsheetID,
                    chartId: chartId,
                    anchor: anchor,
                    width: width,
                    height: height,
                    newSheet: newSheet
                )
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete an embedded chart by its numeric id."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The numeric chart id to delete.")
            var chartId: Int

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.deleteChart(spreadsheetId: spreadsheetID, chartId: chartId)
            }
        }
    }

    struct ConditionalFormat: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "conditional-format",
            abstract: "Add or remove conditional-format rules on a sheet.",
            subcommands: [Add.self, Delete.self]
        )

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Add a rule that colors cells matching a condition.",
                discussion: """
                    The rule covers the range and colors any cell that satisfies
                    the condition. Give the condition operands with --value: none
                    for BLANK/NOT_BLANK, two for the *_BETWEEN types, otherwise
                    one or more. The sheet comes from the range's tab name, or the
                    first sheet when the range names none.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The range the rule covers, e.g. 'Sheet1!A2:A100'.")
            var range: String

            @Option(help: "The condition type, e.g. NUMBER_GREATER or TEXT_CONTAINS.")
            var type: SheetsConditionType

            @Option(help: "A condition value. Repeat for the *_BETWEEN types (two values).")
            var value: [String] = []

            @Option(help: "The background color for a matched cell, as hex, e.g. #FFCC00.")
            var background: String

            @Option(help: "Zero-based insertion index within the sheet's rule list.")
            var index: Int = 0

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let color = try SheetsColor.parse(background)
                try await client.addConditionalFormatRule(
                    spreadsheetId: spreadsheetID,
                    range: range,
                    type: type,
                    values: value,
                    backgroundColor: color,
                    index: index
                )
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a conditional-format rule by its index."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The zero-based index of the rule to delete.")
            var index: Int

            @Option(help: "The numeric sheet id to target.")
            var sheetId: Int?

            @Option(help: "The title of the sheet to target.")
            var sheet: String?

            func validate() throws {
                try SheetTarget.validate(sheetId: sheetId, sheet: sheet)
            }

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await SheetTarget.resolve(
                    client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
                try await client.deleteConditionalFormatRule(
                    spreadsheetId: spreadsheetID, sheetId: id, index: index)
            }
        }
    }

    struct Validation: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set or clear data validation on a range.",
            subcommands: [Set.self, Clear.self]
        )

        struct Set: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Set a data-validation rule on a range.",
                discussion: """
                    Give the condition operands with --value: none for
                    BLANK/NOT_BLANK, two for the *_BETWEEN types, otherwise one or
                    more (ONE_OF_LIST takes each allowed value). --strict rejects
                    invalid input; --dropdown draws the in-cell chooser.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The range to validate, e.g. 'Sheet1!B2:B100'.")
            var range: String

            @Option(help: "The condition type, e.g. ONE_OF_LIST or NUMBER_BETWEEN.")
            var type: SheetsConditionType

            @Option(help: "A condition value. Repeat for a list or the *_BETWEEN types.")
            var value: [String] = []

            @Flag(help: "Reject input that fails the condition.")
            var strict = false

            @Flag(help: "Show the in-cell dropdown of allowed values.")
            var dropdown = false

            @Option(help: "The input hint shown when the cell is selected.")
            var message: String?

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.setDataValidation(
                    spreadsheetId: spreadsheetID,
                    range: range,
                    type: type,
                    values: value,
                    strict: strict ? true : nil,
                    showCustomUi: dropdown ? true : nil,
                    inputMessage: message
                )
            }
        }

        struct Clear: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Clear data validation from a range."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The range to clear, e.g. 'Sheet1!B2:B100'.")
            var range: String

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.clearDataValidation(spreadsheetId: spreadsheetID, range: range)
            }
        }
    }

    struct Filter: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set or clear a sheet's basic filter.",
            subcommands: [Set.self, Clear.self]
        )

        struct Set: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Set the basic filter over a range."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The range the filter covers, e.g. 'Sheet1!A1:D100'.")
            var range: String

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.setBasicFilter(spreadsheetId: spreadsheetID, range: range)
            }
        }

        struct Clear: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Clear the basic filter from a sheet."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The numeric sheet id to target.")
            var sheetId: Int?

            @Option(help: "The title of the sheet to target.")
            var sheet: String?

            func validate() throws {
                try SheetTarget.validate(sheetId: sheetId, sheet: sheet)
            }

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await SheetTarget.resolve(
                    client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
                try await client.clearBasicFilter(spreadsheetId: spreadsheetID, sheetId: id)
            }
        }
    }

    struct FilterView: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "filter-view",
            abstract: "Manage saved filter views.",
            subcommands: [Add.self]
        )

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Add a titled filter view and print its id."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The range the view covers, e.g. 'Sheet1!A1:D100'.")
            var range: String

            @Option(help: "The title of the filter view.")
            var title: String

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await client.addFilterView(
                    spreadsheetId: spreadsheetID, range: range, title: title)
                print(id)
            }
        }
    }

    struct Protect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add or remove protected ranges.",
            subcommands: [Add.self, Delete.self]
        )

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Protect a range and print its protected-range id.",
                discussion: """
                    By default edits to the range are blocked for everyone but the
                    owner; pass --warning-only to warn on edits instead of blocking
                    them.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The range to protect, e.g. 'Sheet1!A1:D10'.")
            var range: String

            @Option(help: "A description of the protection.")
            var description: String?

            @Flag(name: .customLong("warning-only"),
                  help: "Warn on edits instead of blocking them.")
            var warningOnly = false

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await client.addProtectedRange(
                    spreadsheetId: spreadsheetID,
                    range: range,
                    description: description,
                    warningOnly: warningOnly ? true : nil
                )
                print(id)
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a protected range by its id."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(name: .customLong("protected-range-id"),
                    help: "The numeric protected-range id to delete.")
            var protectedRangeId: Int

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.deleteProtectedRange(
                    spreadsheetId: spreadsheetID, protectedRangeId: protectedRangeId)
            }
        }
    }

    struct Merge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Merge the cells in a range into one.",
            discussion: """
                --type chooses how to merge: merge_all (the whole range into one
                cell, the default), merge_columns (one cell per column), or
                merge_rows (one cell per row). The sheet comes from the range's
                tab name, or the first sheet when the range names none.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The range to merge, for example 'Sheet1!A1:C1'.")
        var range: String

        @Option(help: "How to merge: merge_all, merge_columns, or merge_rows.")
        var type: SheetsMergeType = .mergeAll

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            try await client.mergeCells(
                spreadsheetId: spreadsheetID, range: range, mergeType: type)
        }
    }

    struct Unmerge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Split any merged cells within a range back into single cells.",
            discussion: """
                The sheet comes from the range's tab name, or the first sheet
                when the range names none.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The range to unmerge, for example 'Sheet1!A1:C1'.")
        var range: String

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            try await client.unmergeCells(spreadsheetId: spreadsheetID, range: range)
        }
    }

    struct Sort: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sort a range's rows by one or more of its columns.",
            discussion: """
                Repeat --by for each sort key, in priority order. Each value is a
                one-based column within the range, optionally suffixed with :asc
                or :desc (ascending by default), for example --by 2:desc --by 1.
                The sheet comes from the range's tab name, or the first sheet
                when the range names none.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The range to sort, for example 'Sheet1!A2:D20'.")
        var range: String

        @Option(help: "A one-based column within the range, e.g. '2:desc'. Repeatable.")
        var by: [String] = []

        func validate() throws {
            guard !by.isEmpty else {
                throw ValidationError("Provide at least one --by sort column.")
            }
        }

        func run() async throws {
            let specs = try by.map { try SheetsSortKey.parse($0) }
            let client = SheetsClient(api: try CLI.makeAPI())
            try await client.sortRange(
                spreadsheetId: spreadsheetID, range: range, specs: specs)
        }
    }

    struct Autoresize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Auto-size a span of rows or columns to fit their contents.",
            discussion: """
                --from and --to are one-based, inclusive positions; omit --to to
                size a single row or column. Target a sheet with --sheet-id or
                --sheet; omit both to use the first sheet.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Option(help: "The dimension to size: rows or columns.")
        var dimension: SheetsDimension

        @Option(help: "The first (one-based) row or column to size.")
        var from: Int

        @Option(help: "The last (one-based) row or column to size. Defaults to --from.")
        var to: Int?

        @Option(help: "The numeric sheet id to target.")
        var sheetId: Int?

        @Option(help: "The title of the sheet to target.")
        var sheet: String?

        func validate() throws {
            try SheetTarget.validate(sheetId: sheetId, sheet: sheet)
        }

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let id = try await SheetTarget.resolve(
                client, spreadsheetID: spreadsheetID, sheetId: sheetId, sheet: sheet)
            try await client.autoResizeDimension(
                spreadsheetId: spreadsheetID,
                sheetId: id,
                dimension: dimension,
                start: from,
                end: to ?? from
            )
        }
    }

    struct NamedRange: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "named-range",
            abstract: "Manage the named ranges defined on a spreadsheet.",
            subcommands: [Add.self, Delete.self, List.self]
        )

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Define a named range and print its new id.",
                discussion: """
                    The sheet comes from the range's tab name, or the first sheet
                    when the range names none.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Argument(help: "The name of the range.")
            var name: String

            @Argument(help: "The range to name, for example 'Sheet1!A1:B10'.")
            var range: String

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let id = try await client.addNamedRange(
                    spreadsheetId: spreadsheetID, name: name, range: range)
                print(id)
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a named range by its id."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(name: .customLong("named-range-id"),
                    help: "The id of the named range to delete.")
            var namedRangeId: String

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                try await client.deleteNamedRange(
                    spreadsheetId: spreadsheetID, namedRangeId: namedRangeId)
            }
        }

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List the named ranges defined on a spreadsheet."
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The output format: table, json, jsonl, or id.")
            var format: OutputFormat = .table

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let ranges = try await client.namedRanges(spreadsheetId: spreadsheetID)
                print(try OutputFormatter.render(ranges, format: format))
            }
        }
    }
}

extension BasicChartType: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsChartKind: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsChartAggregateType: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsDimension: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsHorizontalAlignment: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsConditionType: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsNumberFormatType: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsBorderStyle: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}

extension SheetsMergeType: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}
