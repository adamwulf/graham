import ArgumentParser
import Foundation
import GrahamKit

struct Sheets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Sheets spreadsheets.",
        subcommands: [Get.self, Values.self]
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
}
