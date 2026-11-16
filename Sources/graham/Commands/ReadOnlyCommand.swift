import ArgumentParser
import Foundation
import GrahamKit

/// A command that cannot change anything in Google and writes no local file.
///
/// Only these may appear under `graham ro`. Every `ro` group builds its
/// configuration with `CommandConfiguration.readOnlyGroup`, whose children are
/// typed `[any ReadOnlyCommand.Type]`, so the compiler rejects a write command
/// placed there. Write commands stay plain `AsyncParsableCommand` and are
/// registered only in the top-level groups.
protocol ReadOnlyCommand: AsyncParsableCommand {}

extension CommandConfiguration {
    /// A group configuration whose children must all be read-only. The type of
    /// `subcommands` is the guarantee; ArgumentParser only needs the upcast.
    static func readOnlyGroup(
        commandName: String,
        abstract: String,
        discussion: String = "",
        subcommands: [any ReadOnlyCommand.Type]
    ) -> CommandConfiguration {
        CommandConfiguration(
            commandName: commandName,
            abstract: abstract,
            discussion: discussion,
            subcommands: subcommands.map { $0 as any ParsableCommand.Type }
        )
    }
}

/// `graham ro`: the read-only commands, at the same paths they have at the top
/// level, so an agent can be allowed `graham ro` and nothing else. The rules
/// for which command goes where are in AGENTS.md, "Read-only and write
/// commands".
struct ReadOnly: AsyncParsableCommand {
    static let configuration = CommandConfiguration.readOnlyGroup(
        commandName: "ro",
        abstract: "Read-only commands: they never write to Google or to a local file.",
        discussion: """
            Each command here is the read-only form of the command at the same \
            path without `ro`: `graham ro docs cat <id>` is `graham docs cat \
            <id>`. Commands that would write a file instead print to stdout: \
            `ro drive export` and `ro drive download` have no --output, and `ro \
            docs images` and `ro slides images` only list. A read-only run \
            sends the Google APIs only GET requests (the OAuth token refresh is \
            its one POST) and writes no log file. Use --help on any command \
            here for its options.
            """,
        subcommands: [
            ReadOnlyAuth.self, ReadOnlyDrive.self, ReadOnlySheets.self,
            ReadOnlyDocs.self, ReadOnlySlides.self,
        ]
    )

    /// True when `arguments` (the full argv, program name first) runs a command
    /// under `graham ro`. The root command takes no options of its own, so a
    /// subcommand under `ro` is reached only when `ro` is the first argument.
    /// An `ro` later in the line, such as a value (`graham drive list --query
    /// ro`), does not count.
    static func isInvoked(by arguments: [String]) -> Bool {
        arguments.dropFirst().first == configuration.commandName
    }
}

// MARK: - auth

struct ReadOnlyAuth: ReadOnlyCommand {
    static let configuration = CommandConfiguration.readOnlyGroup(
        commandName: "auth",
        abstract: "Check credentials.",
        subcommands: [Auth.Status.self]
    )
}

// MARK: - drive

struct ReadOnlyDrive: ReadOnlyCommand {
    static let configuration = CommandConfiguration.readOnlyGroup(
        commandName: "drive",
        abstract: "List, read, and export Google Drive files.",
        subcommands: [Drive.List.self, Drive.Get.self, Download.self, Export.self]
    )

    /// `drive export` without `--output`: the export always goes to stdout.
    struct Export: ReadOnlyCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "Export a Google Workspace file to another format, on stdout.",
            discussion: """
                The read-only form of `graham drive export`. It has no --output: \
                the export is always written to stdout.
                """
        )

        @OptionGroup var options: Drive.Export.Options

        func run() async throws {
            try await Drive.Export.export(options, output: nil)
        }
    }

    /// `drive download` without `--output`: the bytes always go to stdout.
    struct Download: ReadOnlyCommand {
        static let configuration = CommandConfiguration(
            commandName: "download",
            abstract: "Download the raw content of a binary file, on stdout.",
            discussion: """
                The read-only form of `graham drive download`. It has no \
                --output: the content is always written to stdout. For Google \
                Workspace files (Docs, Sheets, Slides), which have no binary \
                content, use `graham ro drive export` instead.
                """
        )

        @OptionGroup var options: Drive.Download.Options

        func run() async throws {
            try await Drive.Download.download(options, output: nil)
        }
    }
}

// MARK: - sheets

struct ReadOnlySheets: ReadOnlyCommand {
    static let configuration = CommandConfiguration.readOnlyGroup(
        commandName: "sheets",
        abstract: "Read Google Sheets spreadsheets.",
        subcommands: [Sheets.Get.self, Sheets.Values.self, NamedRange.self]
    )

    struct NamedRange: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "named-range",
            abstract: "List the named ranges defined on a spreadsheet.",
            subcommands: [Sheets.NamedRange.List.self]
        )
    }
}

// MARK: - docs

struct ReadOnlyDocs: ReadOnlyCommand {
    static let configuration = CommandConfiguration.readOnlyGroup(
        commandName: "docs",
        abstract: "Read Google Docs documents.",
        subcommands: [
            Docs.Cat.self, Docs.Structure.self, Style.self, Paragraph.self,
            Images.self, NamedRange.self, Tab.self,
        ]
    )

    struct Style: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "style",
            abstract: "Show the text style of a range: bold, colors, font, link, and so on.",
            subcommands: [Docs.Style.Get.self]
        )
    }

    struct Paragraph: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "paragraph",
            abstract: "Show whole-paragraph style: named style, alignment, spacing, indents.",
            subcommands: [Docs.Paragraph.Get.self]
        )
    }

    struct NamedRange: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "range",
            abstract: "List the document's named ranges.",
            subcommands: [Docs.NamedRange.List.self]
        )
    }

    struct Tab: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "tab",
            abstract: "List the document's tabs.",
            subcommands: [Docs.Tab.List.self]
        )
    }

    /// `docs images` without `--download`: it only lists.
    struct Images: ReadOnlyCommand {
        static let configuration = CommandConfiguration(
            commandName: "images",
            abstract: "List every image in a document.",
            discussion: """
                The read-only form of `graham docs images`. It has no \
                --download: it lists each inline and positioned image with its \
                origin, object id, size, source URI, and content URI.
                """
        )

        @OptionGroup var options: Docs.Images.Options

        func run() async throws {
            try await Docs.Images.images(options, download: nil)
        }
    }
}

// MARK: - slides

struct ReadOnlySlides: ReadOnlyCommand {
    static let configuration = CommandConfiguration.readOnlyGroup(
        commandName: "slides",
        abstract: "Read Google Slides presentations.",
        subcommands: [
            Slides.Cat.self, Slides.List.self, Slides.Layouts.self, Images.self,
            Notes.self, Slide.self,
        ]
    )

    struct Notes: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "notes",
            abstract: "Show slide speaker notes.",
            subcommands: [Slides.Notes.Get.self]
        )
    }

    struct Slide: ReadOnlyCommand {
        static let configuration = CommandConfiguration.readOnlyGroup(
            commandName: "slide",
            abstract: "Show whether slides are skipped and their backgrounds.",
            subcommands: [Slides.Slide.Get.self]
        )
    }

    /// `slides images` without `--download`: it only lists.
    struct Images: ReadOnlyCommand {
        static let configuration = CommandConfiguration(
            commandName: "images",
            abstract: "List every image in a presentation.",
            discussion: """
                The read-only form of `graham slides images`. It has no \
                --download: it lists each image (including images nested in \
                groups) with its slide, object id, alt text, source URL, and \
                content URL.
                """
        )

        @OptionGroup var options: Slides.Images.Options

        func run() async throws {
            try await Slides.Images.images(options, download: nil)
        }
    }
}
