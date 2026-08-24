import ArgumentParser
import Foundation
import GrahamKit

struct Drive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Drive files.",
        subcommands: [List.self, Get.self, Export.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List files in Drive, or navigate drives and folders."
        )

        @Argument(help: "A folder or shared-drive ID to list the contents of. Omit to show the top-level drives.")
        var id: String?

        @Option(help: "Filter by type: docs, sheets, slides, folders, or all.")
        var type: DriveFileType = .all

        @Option(help: "A Drive search query, for example: name contains 'report'")
        var query: String?

        @Option(help: "A sort order, for example: modifiedTime desc")
        var orderBy: String?

        @Option(help: "The maximum number of files to return.")
        var limit: Int = 100

        @Option(help: "The output format: table, json, jsonl, or id.")
        var format: OutputFormat = .table

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let files: [DriveFile]
            if let id {
                // List the contents of one folder or shared drive.
                files = try await client.list(
                    parentID: id, type: type, query: query, orderBy: orderBy, limit: limit
                )
            } else if query == nil, type == .all || type == .folders {
                // The top-level roots: My Drive plus every shared drive.
                files = try await topLevel(client: client, limit: limit)
            } else {
                // A global search across all drives.
                files = try await client.list(
                    type: type, query: query, orderBy: orderBy, limit: limit
                )
            }
            print(try OutputFormatter.render(files, format: format))
        }

        /// Fetches "My Drive" and the shared drives as one list of rows. Each
        /// shared drive is mapped to a ``DriveFile`` row with a synthetic drive
        /// MIME, so the table shows a sensible type.
        private func topLevel(client: DriveClient, limit: Int) async throws -> [DriveFile] {
            guard limit > 0 else { return [] }
            var rows: [DriveFile] = [try await client.root()]
            if rows.count < limit {
                let drives = try await client.drives(limit: limit - rows.count)
                rows.append(contentsOf: drives.map { $0.asDriveFile() })
            }
            return rows
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the metadata of one file.")

        @Argument(help: "The Drive file ID.")
        var fileID: String

        @Option(help: "The output format: table, json, jsonl, or id.")
        var format: OutputFormat = .json

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.file(id: fileID)
            print(try OutputFormatter.render([file], format: format))
        }
    }

    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export a Google Workspace file to another format."
        )

        @Argument(help: "The Drive file ID.")
        var fileID: String

        @Option(help: "The target MIME type, for example text/plain, text/csv, or application/pdf.")
        var mime: String = "text/plain"

        @Option(name: [.short, .long], help: "Write the export to this file instead of stdout.")
        var output: String?

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let data = try await client.export(id: fileID, mimeType: mime)
            if let output {
                try data.write(to: URL(fileURLWithPath: output))
            } else {
                FileHandle.standardOutput.write(data)
            }
        }
    }
}
