import ArgumentParser
import Foundation
import GrahamKit

struct Sheets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Sheets spreadsheets.",
        subcommands: [
            Get.self, Values.self, Set.self, Append.self, Clear.self, Tab.self,
            Chart.self, Test.self,
        ]
    )

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
            abstract: "Show a spreadsheet's title and its sheets."
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
            let rows: [[String]]
            if let jsonRows {
                rows = try SheetsRowInput.fromJSON(jsonRows)
            } else if tsv {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                rows = try SheetsRowInput.fromTSV(String(decoding: data, as: UTF8.self))
            } else {
                rows = row.map { encodedRow in
                    encodedRow.split(separator: ",", omittingEmptySubsequences: false)
                        .map(String.init)
                }
            }
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
            let rows: [[String]]
            if let jsonRows {
                rows = try SheetsRowInput.fromJSON(jsonRows)
            } else if tsv {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                rows = try SheetsRowInput.fromTSV(String(decoding: data, as: UTF8.self))
            } else {
                rows = row.map { encodedRow in
                    encodedRow.split(separator: ",", omittingEmptySubsequences: false)
                        .map(String.init)
                }
            }
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

    struct Chart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Work with embedded spreadsheet charts.",
            subcommands: [Add.self]
        )

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Add a basic chart on its own sheet and print its chart id.",
                discussion: """
                    The first range column is the domain and each remaining
                    column is a series. The first row supplies headers. The
                    printed numeric chart id can be passed to
                    `graham slides create chart --chart-id`.
                    """
            )

            @Argument(help: "The spreadsheet ID.")
            var spreadsheetID: String

            @Option(help: "The source range in bounded A1 notation.")
            var range: String

            @Option(help: "The chart title.")
            var title: String?

            @Option(help: "The chart type: column, bar, line, area, or scatter.")
            var type: BasicChartType = .column

            func run() async throws {
                let client = SheetsClient(api: try CLI.makeAPI())
                let chartId = try await client.addChart(
                    spreadsheetId: spreadsheetID,
                    title: title,
                    type: type,
                    range: range
                )
                print(chartId)
            }
        }
    }
}

extension BasicChartType: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}
