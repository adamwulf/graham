import Foundation

/// The outcome of one named live-test step.
public enum DriveLiveTestOutcome: Sendable, Equatable {
    case pass
    case fail(reason: String)
    case skip(reason: String)
}

/// One completed step in a ``DriveLiveTest`` run.
public struct DriveLiveTestStep: Sendable, Equatable {
    public let name: String
    public let outcome: DriveLiveTestOutcome
    public let createdIDs: [String]

    public init(name: String, outcome: DriveLiveTestOutcome, createdIDs: [String] = []) {
        self.name = name
        self.outcome = outcome
        self.createdIDs = createdIDs
    }
}

/// The complete result of a ``DriveLiveTest`` run.
public struct DriveLiveTestSummary: Sendable, Equatable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let steps: [DriveLiveTestStep]

    public init(steps: [DriveLiveTestStep]) {
        self.steps = steps
        passed = steps.count { $0.outcome == .pass }
        failed = steps.count {
            if case .fail = $0.outcome { return true }
            return false
        }
        skipped = steps.count {
            if case .skip = $0.outcome { return true }
            return false
        }
    }
}

/// Runs graham's Drive command surface against disposable files in My Drive.
///
/// The runner owns sequencing, dependency skips, read-back verification, and
/// cleanup. It never prints: each completed step is delivered through
/// `onStep`, and the full ordered result is returned to the caller.
///
/// `download` is intentionally absent because graham cannot upload a binary
/// fixture for the runner to download. Shared-drive discovery is exercised by
/// ``DriveClient/roots(limit:)``; mutations stay in My Drive so the test works
/// for accounts that do not belong to a shared drive.
public struct DriveLiveTest: Sendable {
    private let drive: DriveClient
    private let folderName: String
    private let keep: Bool
    private let label: String
    private let onStep: @Sendable (DriveLiveTestStep) -> Void

    public init(
        drive: DriveClient,
        folderName: String = "graham test",
        keep: Bool = false,
        label: String,
        onStep: @escaping @Sendable (DriveLiveTestStep) -> Void = { _ in }
    ) {
        self.drive = drive
        self.folderName = folderName
        self.keep = keep
        self.label = label
        self.onStep = onStep
    }

    /// Runs every live-test step in its stable order.
    public func run() async -> DriveLiveTestSummary {
        let recorder = Recorder(onStep: onStep)

        // The root-level test folder is the only hard prerequisite. Like the
        // other service runners, it remains after the run for reuse.
        guard let testFolder = await valueStep(
            "folder", recorder: recorder,
            createdIDs: { $0.created ? [$0.file.id] : [] },
            operation: findOrCreateFolder
        ) else {
            return recorder.summary
        }

        _ = await actionStep("roots", recorder: recorder) {
            let roots = try await drive.roots(limit: 100)
            guard let root = roots.first, !root.id.isEmpty else {
                throw GrahamError.invalidResponse("Drive returned no My Drive root")
            }
        }

        let sourceFolder = await valueStep(
            "create-source-folder", recorder: recorder, createdIDs: { [$0.id] }
        ) {
            try await drive.create(
                name: "graham drive source \(label)",
                type: .folder,
                parent: testFolder.file.id)
        }
        let destinationFolder = await valueStep(
            "create-destination-folder", recorder: recorder, createdIDs: { [$0.id] }
        ) {
            try await drive.create(
                name: "graham drive destination \(label)",
                type: .folder,
                parent: testFolder.file.id)
        }

        let originalName = "graham drive document \(label)"
        let renamedName = "graham drive renamed \(label)"
        let document = await valueStep(
            "create-document", recorder: recorder,
            skipReason: dependencyReason("create-source-folder", value: sourceFolder),
            createdIDs: { [$0.id] }
        ) {
            try await drive.create(
                name: originalName, type: .docs, parent: sourceFolder!.id)
        }

        _ = await actionStep(
            "get-document", recorder: recorder,
            skipReason: dependencyReason("create-document", value: document)
        ) {
            let read = try await drive.file(id: document!.id)
            guard read.id == document!.id, read.name == originalName else {
                throw GrahamError.invalidResponse("the created document did not round-trip")
            }
        }
        _ = await actionStep(
            "list-source", recorder: recorder,
            skipReason: firstFailed([
                ("create-source-folder", sourceFolder != nil),
                ("create-document", document != nil),
            ])
        ) {
            let files = try await drive.browse(id: sourceFolder!.id, limit: 100)
            guard files.contains(where: { $0.id == document!.id }) else {
                throw GrahamError.invalidResponse("the source folder did not list the document")
            }
        }
        _ = await actionStep(
            "global-search", recorder: recorder,
            skipReason: dependencyReason("create-document", value: document)
        ) {
            let escapedName = DriveClient.escapeQueryValue(originalName)
            let files = try await drive.browse(
                type: .docs,
                query: "name = '\(escapedName)'",
                limit: 100)
            guard files.contains(where: { $0.id == document!.id }) else {
                throw GrahamError.invalidResponse("global search did not find the document")
            }
        }

        _ = await valueStep(
            "rename-document", recorder: recorder,
            skipReason: dependencyReason("create-document", value: document)
        ) {
            let file = try await drive.rename(fileId: document!.id, name: renamedName)
            guard file.id == document!.id, file.name == renamedName else {
                throw GrahamError.invalidResponse("the document rename did not round-trip")
            }
            return file
        }
        let starred = await actionStep(
            "star-document", recorder: recorder,
            skipReason: dependencyReason("create-document", value: document)
        ) {
            let file = try await drive.setStarred(fileId: document!.id, starred: true)
            guard file.id == document!.id else {
                throw GrahamError.invalidResponse("starring returned the wrong file")
            }
        }
        _ = await actionStep(
            "unstar-document", recorder: recorder,
            skipReason: starred ? nil : "star-document failed"
        ) {
            let file = try await drive.setStarred(fileId: document!.id, starred: false)
            guard file.id == document!.id else {
                throw GrahamError.invalidResponse("unstarring returned the wrong file")
            }
        }

        let moved = await valueStep(
            "move-document", recorder: recorder,
            skipReason: firstFailed([
                ("create-document", document != nil),
                ("create-destination-folder", destinationFolder != nil),
            ])
        ) {
            let file = try await drive.move(fileId: document!.id, to: destinationFolder!.id)
            guard file.parents?.contains(destinationFolder!.id) == true else {
                throw GrahamError.invalidResponse("the destination parent did not round-trip")
            }
            return file
        }
        _ = await actionStep(
            "list-destination", recorder: recorder,
            skipReason: dependencyReason("move-document", value: moved)
        ) {
            let files = try await drive.browse(id: destinationFolder!.id, limit: 100)
            guard files.contains(where: { $0.id == document!.id }) else {
                throw GrahamError.invalidResponse("the destination folder did not list the document")
            }
        }

        let shortcut = await valueStep(
            "create-shortcut", recorder: recorder,
            skipReason: firstFailed([
                ("create-document", document != nil),
                ("create-destination-folder", destinationFolder != nil),
            ]),
            createdIDs: { [$0.id] }
        ) {
            let file = try await drive.createShortcut(
                name: "graham drive shortcut \(label)",
                targetId: document!.id,
                parent: destinationFolder!.id)
            guard file.mimeType == DriveShortcutCreateRequest.mimeType else {
                throw GrahamError.invalidResponse("shortcut creation returned the wrong MIME type")
            }
            return file
        }

        let copy = await valueStep(
            "copy-document", recorder: recorder,
            skipReason: firstFailed([
                ("create-document", document != nil),
                ("create-source-folder", sourceFolder != nil),
            ]),
            createdIDs: { [$0.id] }
        ) {
            let file = try await drive.copy(
                fileId: document!.id,
                name: "graham drive copy \(label)",
                parent: sourceFolder!.id)
            guard file.id != document!.id, file.parents?.contains(sourceFolder!.id) == true else {
                throw GrahamError.invalidResponse("the document copy did not round-trip")
            }
            return file
        }

        _ = await actionStep(
            "export-document", recorder: recorder,
            skipReason: dependencyReason("create-document", value: document)
        ) {
            _ = try await drive.export(id: document!.id, mimeType: "text/plain")
        }

        let trashedCopy = await actionStep(
            "trash-copy", recorder: recorder,
            skipReason: dependencyReason("copy-document", value: copy)
        ) {
            let file = try await drive.trash(fileId: copy!.id)
            guard file.id == copy!.id else {
                throw GrahamError.invalidResponse("trashing returned the wrong file")
            }
        }
        let untrashedCopy = await actionStep(
            "untrash-copy", recorder: recorder,
            skipReason: trashedCopy ? nil : "trash-copy failed"
        ) {
            let file = try await drive.untrash(fileId: copy!.id)
            guard file.id == copy!.id else {
                throw GrahamError.invalidResponse("untrashing returned the wrong file")
            }
        }
        if keep {
            recorder.record(name: "delete-copy", outcome: .skip(reason: "kept"))
        } else {
            _ = await actionStep(
                "delete-copy", recorder: recorder,
                skipReason: untrashedCopy ? nil : "untrash-copy failed"
            ) {
                try await drive.delete(fileId: copy!.id)
            }
        }

        await cleanupStep(
            "drive-trash-shortcut", fileID: shortcut?.id,
            recorder: recorder, dependency: "create-shortcut")
        await cleanupStep(
            "drive-trash-document", fileID: document?.id,
            recorder: recorder, dependency: "create-document")
        await cleanupStep(
            "drive-trash-source-folder", fileID: sourceFolder?.id,
            recorder: recorder, dependency: "create-source-folder")
        await cleanupStep(
            "drive-trash-destination-folder", fileID: destinationFolder?.id,
            recorder: recorder, dependency: "create-destination-folder")

        return recorder.summary
    }

    // MARK: - Setup and recording

    private func findOrCreateFolder() async throws -> FolderResult {
        let escapedName = DriveClient.escapeQueryValue(folderName)
        let matches = try await drive.list(
            parentID: "root",
            type: .folders,
            query: "name = '\(escapedName)'",
            limit: 1
        )
        if let existing = matches.first {
            return FolderResult(file: existing, created: false)
        }
        let folder = try await drive.create(name: folderName, type: .folder, parent: "root")
        return FolderResult(file: folder, created: true)
    }

    private func cleanupStep(
        _ name: String,
        fileID: String?,
        recorder: Recorder,
        dependency: String
    ) async {
        if keep {
            recorder.record(name: name, outcome: .skip(reason: "kept"))
            return
        }
        _ = await actionStep(
            name,
            recorder: recorder,
            skipReason: fileID == nil ? "\(dependency) failed" : nil
        ) {
            _ = try await drive.trash(fileId: fileID!)
        }
    }

    // MARK: - Step primitives

    private func valueStep<T: Sendable>(
        _ name: String,
        recorder: Recorder,
        skipReason: String? = nil,
        createdIDs: (T) -> [String] = { _ in [] },
        operation: () async throws -> T
    ) async -> T? {
        if let skipReason {
            recorder.record(name: name, outcome: .skip(reason: skipReason))
            return nil
        }
        do {
            let value = try await operation()
            recorder.record(name: name, outcome: .pass, createdIDs: createdIDs(value))
            return value
        } catch {
            recorder.record(name: name, outcome: .fail(reason: Self.reason(for: error)))
            return nil
        }
    }

    private func actionStep(
        _ name: String,
        recorder: Recorder,
        skipReason: String? = nil,
        operation: () async throws -> Void
    ) async -> Bool {
        let result: Bool? = await valueStep(
            name, recorder: recorder, skipReason: skipReason
        ) {
            try await operation()
            return true
        }
        return result == true
    }

    private func dependencyReason<T>(_ name: String, value: T?) -> String? {
        value == nil ? "\(name) failed" : nil
    }

    private func firstFailed(_ dependencies: [(String, Bool)]) -> String? {
        dependencies.first(where: { !$0.1 }).map { "\($0.0) failed" }
    }

    private static func reason(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description.replacingOccurrences(of: "\n", with: " ")
        }
        return String(describing: error).replacingOccurrences(of: "\n", with: " ")
    }
}

private extension DriveLiveTest {
    struct FolderResult: Sendable {
        let file: DriveFile
        let created: Bool
    }

    final class Recorder: @unchecked Sendable {
        private(set) var steps: [DriveLiveTestStep] = []
        private let onStep: @Sendable (DriveLiveTestStep) -> Void

        init(onStep: @escaping @Sendable (DriveLiveTestStep) -> Void) {
            self.onStep = onStep
        }

        func record(
            name: String,
            outcome: DriveLiveTestOutcome,
            createdIDs: [String] = []
        ) {
            let step = DriveLiveTestStep(
                name: name, outcome: outcome, createdIDs: createdIDs)
            steps.append(step)
            onStep(step)
        }

        var summary: DriveLiveTestSummary {
            DriveLiveTestSummary(steps: steps)
        }
    }
}
