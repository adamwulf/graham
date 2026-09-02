import ArgumentParser
import Foundation
import GrahamKit

struct Drive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Google Drive files.",
        subcommands: [
            List.self, Get.self, Create.self, Copy.self, Move.self, Rename.self,
            Star.self, Trash.self, Untrash.self, Delete.self, Download.self, Export.self,
            Test.self,
        ]
    )

    struct Test: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the live end-to-end Drive smoke test.",
            discussion: """
                Creates disposable folders and files inside a folder in My Drive, \
                exercises graham's Drive metadata and file-management operations, \
                and removes the created files afterward. Download is excluded \
                because it requires an existing binary file. The root-level test \
                folder remains. Use --keep to retain the disposable files for \
                inspection. The command exits nonzero when any step fails.
                """
        )

        @Flag(help: "Keep the disposable folders and files after the run.")
        var keep = false

        @Option(help: "The root-level My Drive folder to find or create.")
        var folder = "graham test"

        func run() async throws {
            let api = try CLI.makeAPI()
            let runner = DriveLiveTest(
                drive: DriveClient(api: api),
                folderName: folder,
                keep: keep,
                label: CLI.iso8601Label(),
                onStep: CLI.liveTestStepHandler(for: DriveLiveTestStep.self)
            )
            let summary = await runner.run()
            try CLI.printLiveTestSummary(summary)
        }
    }

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
            let files = try await client.browse(
                id: id, type: type, query: query, orderBy: orderBy, limit: limit
            )
            print(try OutputFormatter.render(files, format: format))
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

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new, empty Doc, Sheet, Slides file, folder, or shortcut.",
            subcommands: [Doc.self, Sheet.self, Slides.self, Folder.self, Shortcut.self]
        )

        /// The name, parent, and format shared by every `drive create` subcommand.
        /// Each subcommand supplies only the `DriveCreateType` these options build.
        struct Options: ParsableArguments {
            @Argument(help: "The name of the new file.")
            var name: String

            @Option(help: "The ID of the folder to create the file in. Without it, the file lands in My Drive.")
            var parent: String?

            @Option(help: "The output format: table, json, jsonl, or id.")
            var format: OutputFormat = .id
        }

        /// The one create path all four subcommands route through, so the
        /// endpoint, parenting, and rendering live in a single place.
        static func create(type: DriveCreateType, options: Options) async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.create(name: options.name, type: type, parent: options.parent)
            print(try OutputFormatter.render([file], format: options.format))
        }

        struct Doc: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "doc", abstract: "Create a new, empty Google Doc.")

            @OptionGroup var options: Options

            func run() async throws { try await Create.create(type: .docs, options: options) }
        }

        struct Sheet: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "sheet", abstract: "Create a new, empty Google Sheet.")

            @OptionGroup var options: Options

            func run() async throws { try await Create.create(type: .sheets, options: options) }
        }

        struct Slides: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "slides", abstract: "Create a new, empty Google Slides presentation.")

            @OptionGroup var options: Options

            func run() async throws { try await Create.create(type: .slides, options: options) }
        }

        struct Folder: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "folder", abstract: "Create a new folder.")

            @OptionGroup var options: Options

            func run() async throws { try await Create.create(type: .folder, options: options) }
        }

        /// Shortcut creation takes a target id and a `--name` instead of the
        /// shared `Options`, so it does not join the name-first group above.
        struct Shortcut: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "shortcut",
                abstract: "Create a shortcut that points to an existing file.")

            @Argument(help: "The Drive file ID the shortcut points to.")
            var targetID: String

            @Option(help: "The name of the new shortcut.")
            var name: String

            @Option(help: "The ID of the folder to create the shortcut in. Without it, it lands in My Drive.")
            var parent: String?

            @Option(help: "The output format: table, json, jsonl, or id.")
            var format: OutputFormat = .id

            func run() async throws {
                let client = DriveClient(api: try CLI.makeAPI())
                let file = try await client.createShortcut(
                    name: name, targetId: targetID, parent: parent)
                print(try OutputFormatter.render([file], format: format))
            }
        }
    }

    struct Copy: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Copy a file, optionally giving the copy a new name."
        )

        @Argument(help: "The Drive file ID to copy.")
        var fileID: String

        @Option(help: "A name for the copy. Without it, Drive names it \"Copy of <original>\".")
        var name: String?

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.copy(fileId: fileID, name: name)
            print(file.id)
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a file into another folder."
        )

        @Argument(help: "The Drive file ID to move.")
        var fileID: String

        @Option(help: "The ID of the destination folder.")
        var to: String

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.move(fileId: fileID, to: to)
            print(file.id)
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a file."
        )

        @Argument(help: "The Drive file ID to rename.")
        var fileID: String

        @Argument(help: "The new name.")
        var name: String

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.rename(fileId: fileID, name: name)
            print(file.id)
        }
    }

    struct Star: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Star a file (mark it a favorite), or unstar it with --off."
        )

        @Argument(help: "The Drive file ID to star.")
        var fileID: String

        @Flag(help: "Remove the star instead of adding it.")
        var off = false

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.setStarred(fileId: fileID, starred: !off)
            print(file.id)
        }
    }

    struct Trash: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a file to the trash. Reversible in the Drive UI."
        )

        @Argument(help: "The Drive file ID to trash.")
        var fileID: String

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.trash(fileId: fileID)
            print(file.id)
        }
    }

    struct Untrash: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Restore a file from the trash."
        )

        @Argument(help: "The Drive file ID to restore.")
        var fileID: String

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let file = try await client.untrash(fileId: fileID)
            print(file.id)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Permanently delete a file. This bypasses the trash and cannot be undone."
        )

        @Argument(help: "The Drive file ID to delete.")
        var fileID: String

        @Flag(help: "Confirm the permanent deletion. Required, because it cannot be undone.")
        var force = false

        func validate() throws {
            guard force else {
                throw ValidationError(
                    "Deleting is permanent and bypasses the trash. Pass --force to confirm, "
                    + "or use \"graham drive trash\" for a reversible move to the trash."
                )
            }
        }

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            try await client.delete(fileId: fileID)
            print(fileID)
        }
    }

    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export a Google Workspace file to another format."
        )

        @Argument(help: "The Drive file ID.")
        var fileID: String

        @Option(help: "A common export format that maps to the correct MIME type.")
        var type: DriveExportFormat?

        @Option(help: """
            A raw target MIME type, for a format --type does not list \
            (for example application/rtf). Cannot be used with --type. \
            The default, when neither is given, is text/plain.
            """)
        var mime: String?

        @Option(name: [.short, .long], help: "Write the export to this file instead of stdout.")
        var output: String?

        /// The MIME type sent to Drive: an explicit `--mime` wins, else the
        /// `--type` mapping, else plain text. `validate()` rejects both at once,
        /// so at most one of the first two is set here.
        var resolvedMimeType: String {
            mime ?? type?.mimeType ?? DriveExportFormat.txt.mimeType
        }

        func validate() throws {
            if type != nil, mime != nil {
                throw ValidationError(
                    "Pass either --type (a common format) or --mime (a raw MIME type), not both."
                )
            }
        }

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let data = try await client.export(id: fileID, mimeType: resolvedMimeType)
            if let output {
                try data.write(to: URL(fileURLWithPath: output))
            } else {
                FileHandle.standardOutput.write(data)
            }
        }
    }

    struct Download: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download the raw content of a binary file.",
            discussion: """
                Downloads the file's bytes as stored. For Google Workspace files \
                (Docs, Sheets, Slides), which have no binary content, use \
                `graham drive export` to convert them to another format instead.
                """
        )

        @Argument(help: "The Drive file ID.")
        var fileID: String

        @Option(name: [.short, .long], help: "Write the content to this file instead of stdout.")
        var output: String?

        func run() async throws {
            let client = DriveClient(api: try CLI.makeAPI())
            let data = try await client.download(id: fileID)
            if let output {
                try data.write(to: URL(fileURLWithPath: output))
            } else {
                FileHandle.standardOutput.write(data)
            }
        }
    }
}
