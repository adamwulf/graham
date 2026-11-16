import ArgumentParser
import XCTest
@testable import graham

/// `graham ro` must hold every read-only command and nothing else, so an agent
/// can be allowed `graham ro` alone.
final class ReadOnlyCommandTests: XCTestCase {
    private typealias Command = any ParsableCommand.Type

    /// Every node under `command` (groups and leaves), with its path.
    private func nodes(under command: Command, path: [String] = []) -> [(path: String, type: Command)] {
        command.configuration.subcommands.flatMap { child -> [(path: String, type: Command)] in
            let childPath = path + [child._commandName]
            return [(childPath.joined(separator: " "), child)] + nodes(under: child, path: childPath)
        }
    }

    /// The executable leaves under `command`, with their paths.
    private func leaves(under command: Command) -> [(path: String, type: Command)] {
        nodes(under: command).filter { $0.type.configuration.subcommands.isEmpty }
    }

    /// The leaves of the top-level tree, without the `ro` subtree.
    private var topLevelLeaves: [(path: String, type: Command)] {
        leaves(under: Graham.self).filter { !$0.path.hasPrefix("ro ") }
    }

    private func isReadOnly(_ command: Command) -> Bool {
        command is any ReadOnlyCommand.Type
    }

    private func same(_ lhs: Command?, _ rhs: Command?) -> Bool {
        guard let lhs, let rhs else { return false }
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: - The tree

    func testRoIsTheLastRootSubcommand() {
        // A static lookup by type finds the first parent, so a shared leaf must
        // meet its top-level parent before `ro`.
        XCTAssertTrue(same(Graham.configuration.subcommands.last, ReadOnly.self))
    }

    func testRoListsExactlyTheseCommands() {
        // Pinned on purpose: adding a command under `ro` is a decision.
        XCTAssertEqual(leaves(under: ReadOnly.self).map(\.path), [
            "auth status",
            "drive list", "drive get", "drive download", "drive export",
            "sheets get", "sheets values", "sheets named-range list",
            "docs cat", "docs structure", "docs style get", "docs paragraph get",
            "docs images", "docs range list", "docs tab list",
            "slides cat", "slides list", "slides layouts", "slides images",
            "slides notes get", "slides slide get",
        ])
    }

    func testEveryNodeUnderRoIsReadOnly() {
        for node in nodes(under: ReadOnly.self) {
            XCTAssertTrue(isReadOnly(node.type), "`ro \(node.path)` (\(node.type)) is not a ReadOnlyCommand")
        }
    }

    func testEveryReadOnlyCommandIsAlsoUnderRoAtTheSamePath() {
        let ro = Dictionary(uniqueKeysWithValues: leaves(under: ReadOnly.self).map { ($0.path, $0.type) })
        let readOnlyLeaves = topLevelLeaves.filter { isReadOnly($0.type) }
        XCTAssertEqual(readOnlyLeaves.count, 17)
        for leaf in readOnlyLeaves {
            XCTAssertTrue(same(ro[leaf.path], leaf.type), "`\(leaf.path)` is read-only but not under `ro` as the same type")
        }
    }

    func testTheRestOfRoIsTheReadOnlyFormOfACommandThatWritesAFile() {
        let top = Dictionary(uniqueKeysWithValues: topLevelLeaves.map { ($0.path, $0.type) })
        var readOnlyForms: [String] = []
        for leaf in leaves(under: ReadOnly.self) {
            let full = top[leaf.path]
            XCTAssertNotNil(full, "`ro \(leaf.path)` has no top-level form")
            guard let full, !same(full, leaf.type) else { continue }
            readOnlyForms.append(leaf.path)
            XCTAssertFalse(isReadOnly(full), "the full form of `ro \(leaf.path)` should be a write command")
        }
        XCTAssertEqual(readOnlyForms, ["drive download", "drive export", "docs images", "slides images"])
    }

    func testCommandsThatWriteAreNotReadOnly() {
        let writes: [Command] = [
            Auth.Login.self, Drive.Create.Doc.self, Drive.Trash.self, Drive.Delete.self,
            Drive.Export.self, Drive.Download.self, Drive.Test.self, Sheets.Set.self,
            Sheets.NamedRange.Add.self, Docs.Insert.self, Docs.Style.Set.self,
            Docs.Images.self, Docs.Tab.Add.self, Slides.Notes.Set.self, Slides.Slide.Set.self,
            Slides.Images.self, Slides.Chart.Refresh.self,
        ]
        for command in writes {
            XCTAssertFalse(isReadOnly(command), "\(command) writes but is a ReadOnlyCommand")
        }
    }

    // MARK: - Parsing

    func testWriteCommandsParseAtTheTopButNotUnderRo() throws {
        let cases: [(arguments: [String], type: Command)] = [
            (["auth", "login"], Auth.Login.self),
            (["drive", "trash", "f1"], Drive.Trash.self),
            (["drive", "delete", "f1", "--force"], Drive.Delete.self),
            (["drive", "create", "doc", "Notes"], Drive.Create.Doc.self),
            (["drive", "test"], Drive.Test.self),
            (["sheets", "clear", "s1", "A1:B2"], Sheets.Clear.self),
            (["slides", "notes", "set", "p1", "s1", "--text", "hi"], Slides.Notes.Set.self),
            (["slides", "slide", "set", "p1", "s1", "--skip"], Slides.Slide.Set.self),
        ]
        for testCase in cases {
            let parsed = try Graham.parseAsRoot(testCase.arguments)
            XCTAssertTrue(same(type(of: parsed), testCase.type), "\(testCase.arguments) parsed as \(type(of: parsed))")
            XCTAssertThrowsError(try Graham.parseAsRoot(["ro"] + testCase.arguments), "`ro \(testCase.arguments)` parsed")
        }
    }

    func testSharedCommandsParseTheSameUnderRo() throws {
        let plain = try XCTUnwrap(try Graham.parseAsRoot(["docs", "cat", "d1", "--markdown"]) as? Docs.Cat)
        let readOnly = try XCTUnwrap(try Graham.parseAsRoot(["ro", "docs", "cat", "d1", "--markdown"]) as? Docs.Cat)
        for command in [plain, readOnly] {
            XCTAssertEqual(command.documentID, "d1")
            XCTAssertTrue(command.markdown)
        }
        XCTAssertTrue(try Graham.parseAsRoot(["ro", "auth", "status"]) is Auth.Status)
        XCTAssertTrue(try Graham.parseAsRoot(["ro", "docs", "style", "get", "d1", "--at", "3"]) is Docs.Style.Get)
        XCTAssertTrue(try Graham.parseAsRoot(["ro", "sheets", "values", "s1", "A1:B2", "--raw"]) is Sheets.Values)
        XCTAssertTrue(try Graham.parseAsRoot(["ro", "slides", "notes", "get", "p1"]) is Slides.Notes.Get)
    }

    func testReadOnlyFormsParseTheSharedOptions() throws {
        let export = try XCTUnwrap(
            try Graham.parseAsRoot(["ro", "drive", "export", "f1", "--type", "pdf"]) as? ReadOnlyDrive.Export)
        XCTAssertEqual(export.options.fileID, "f1")
        XCTAssertEqual(export.options.resolvedMimeType, "application/pdf")
        // The shared options keep their validation under `ro`.
        XCTAssertThrowsError(
            try Graham.parseAsRoot(["ro", "drive", "export", "f1", "--type", "pdf", "--mime", "text/csv"]))

        let download = try XCTUnwrap(
            try Graham.parseAsRoot(["ro", "drive", "download", "f1"]) as? ReadOnlyDrive.Download)
        XCTAssertEqual(download.options.fileID, "f1")

        let docsImages = try XCTUnwrap(
            try Graham.parseAsRoot(["ro", "docs", "images", "d1", "--format", "json"]) as? ReadOnlyDocs.Images)
        XCTAssertEqual(docsImages.options.documentID, "d1")
        XCTAssertEqual(docsImages.options.format, .json)

        let slidesImages = try XCTUnwrap(
            try Graham.parseAsRoot(["ro", "slides", "images", "p1", "--format", "id"]) as? ReadOnlySlides.Images)
        XCTAssertEqual(slidesImages.options.presentationID, "p1")
        XCTAssertEqual(slidesImages.options.format, .id)
    }

    func testRoDropsEveryOptionThatWritesAFile() {
        let rejected: [[String]] = [
            ["drive", "export", "f1", "-o", "out.txt"],
            ["drive", "export", "f1", "--output", "out.txt"],
            ["drive", "download", "f1", "-o", "out.bin"],
            ["drive", "download", "f1", "--output", "out.bin"],
            ["docs", "images", "d1", "-d", "dir"],
            ["docs", "images", "d1", "--download", "dir"],
            ["slides", "images", "p1", "-d", "dir"],
            ["slides", "images", "p1", "--download", "dir"],
        ]
        for arguments in rejected {
            XCTAssertNoThrow(try Graham.parseAsRoot(arguments), "\(arguments) should parse at the top")
            XCTAssertThrowsError(try Graham.parseAsRoot(["ro"] + arguments), "`ro \(arguments)` parsed")
        }
    }

    /// The whole surface of each two-form command, not only the dropped option
    /// by name: an option added later to a shared option group changes these
    /// lines, and so forces a decision on whether `ro` may have it.
    func testTheUsageOfEachTwoFormCommandIsPinned() {
        func usage(_ command: Command) -> String? {
            Graham.helpMessage(for: command, columns: 1000)
                .split(separator: "\n")
                .first { $0.hasPrefix("USAGE: ") }
                .map(String.init)
        }
        XCTAssertEqual(usage(ReadOnlyDrive.Export.self),
                       "USAGE: graham ro drive export <file-id> [--type <type>] [--mime <mime>]")
        XCTAssertEqual(usage(Drive.Export.self),
                       "USAGE: graham drive export <file-id> [--type <type>] [--mime <mime>] [--output <output>]")
        XCTAssertEqual(usage(ReadOnlyDrive.Download.self), "USAGE: graham ro drive download <file-id>")
        XCTAssertEqual(usage(Drive.Download.self), "USAGE: graham drive download <file-id> [--output <output>]")
        XCTAssertEqual(usage(ReadOnlyDocs.Images.self),
                       "USAGE: graham ro docs images <document-id> [--format <format>]")
        XCTAssertEqual(usage(Docs.Images.self),
                       "USAGE: graham docs images <document-id> [--format <format>] [--download <download>]")
        XCTAssertEqual(usage(ReadOnlySlides.Images.self),
                       "USAGE: graham ro slides images <presentation-id> [--format <format>]")
        XCTAssertEqual(usage(Slides.Images.self),
                       "USAGE: graham slides images <presentation-id> [--format <format>] [--download <download>]")
    }

    // MARK: - Detecting a read-only run

    func testIsInvokedOnlyWhenRoIsTheFirstArgument() {
        XCTAssertTrue(ReadOnly.isInvoked(by: ["graham", "ro"]))
        XCTAssertTrue(ReadOnly.isInvoked(by: ["graham", "ro", "drive", "list"]))
        XCTAssertTrue(ReadOnly.isInvoked(by: ["graham", "--", "ro", "docs", "cat", "d1"]))
        XCTAssertFalse(ReadOnly.isInvoked(by: ["graham"]))
        XCTAssertFalse(ReadOnly.isInvoked(by: ["graham", "drive", "list"]))
        XCTAssertFalse(ReadOnly.isInvoked(by: ["graham", "drive", "list", "--query", "ro"]))
        XCTAssertFalse(ReadOnly.isInvoked(by: ["ro", "drive", "list"]), "the program name comes first")
    }
}
