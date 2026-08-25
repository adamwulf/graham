import ArgumentParser
import Foundation
import GrahamKit

struct Sheets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Sheets spreadsheets.",
        subcommands: [Get.self, Values.self, Set.self, Chart.self]
    )

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
            abstract: "Read cell values from a range, as tab-separated lines."
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "A range in A1 notation, for example 'Sheet1!A1:C10' or 'Sheet1'.")
        var range: String

        @Flag(help: "Print the raw ValueRange as JSON instead of tab-separated lines.")
        var json = false

        func run() async throws {
            let client = SheetsClient(api: try CLI.makeAPI())
            let valueRange = try await client.values(spreadsheetId: spreadsheetID, range: range)
            if json {
                try CLI.printJSON(valueRange)
                return
            }
            for row in valueRange.values ?? [] {
                print(row.map(\.display).joined(separator: "\t"))
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write rows of cell values to a range.",
            discussion: """
                Repeat --row once for each row to write. Each value is a
                comma-separated list of cells. This first version has no
                escaping: every comma starts the next cell. Values use Sheets'
                USER_ENTERED mode, so numeric strings become numbers.
                """
        )

        @Argument(help: "The spreadsheet ID.")
        var spreadsheetID: String

        @Argument(help: "The destination range in A1 notation, for example 'Sheet1!A1:B3'.")
        var range: String

        @Option(help: "One comma-separated row of cells. Repeat for more rows.")
        var row: [String] = []

        func validate() throws {
            guard !row.isEmpty else {
                throw ValidationError("Provide at least one --row to write.")
            }
        }

        func run() async throws {
            let rows = row.map { encodedRow in
                encodedRow.split(separator: ",", omittingEmptySubsequences: false)
                    .map(String.init)
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
