import Foundation

/// The outcome of one named live-test step.
public enum SheetsLiveTestOutcome: Sendable, Equatable {
    case pass
    case fail(reason: String)
    case skip(reason: String)
}

/// One completed step in a ``SheetsLiveTest`` run.
public struct SheetsLiveTestStep: Sendable, Equatable {
    public let name: String
    public let outcome: SheetsLiveTestOutcome
    public let createdIDs: [String]

    public init(name: String, outcome: SheetsLiveTestOutcome, createdIDs: [String] = []) {
        self.name = name
        self.outcome = outcome
        self.createdIDs = createdIDs
    }
}

/// The complete result of a ``SheetsLiveTest`` run.
public struct SheetsLiveTestSummary: Sendable, Equatable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let steps: [SheetsLiveTestStep]

    public init(steps: [SheetsLiveTestStep]) {
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

/// Runs graham's full Sheets command surface against a disposable spreadsheet.
///
/// The runner owns sequencing, dependency skips, read-back verification, and
/// cleanup. It never prints: each completed step is delivered through
/// `onStep`, and the full ordered result is returned to the caller. This is the
/// Sheets analog of ``DocsLiveTest`` and ``SlidesLiveTest``.
///
/// Each write is verified by reading it back where practical: the value write is
/// confirmed by a values read of the same range, and the chart add returns a
/// numeric chart id.
public struct SheetsLiveTest: Sendable {
    private let drive: DriveClient
    private let sheets: SheetsClient
    private let folderName: String
    private let keep: Bool
    private let label: String
    private let onStep: @Sendable (SheetsLiveTestStep) -> Void

    public init(
        drive: DriveClient,
        sheets: SheetsClient,
        folderName: String = "graham test",
        keep: Bool = false,
        label: String,
        onStep: @escaping @Sendable (SheetsLiveTestStep) -> Void = { _ in }
    ) {
        self.drive = drive
        self.sheets = sheets
        self.folderName = folderName
        self.keep = keep
        self.label = label
        self.onStep = onStep
    }

    // The seed grid written to A1:B4, then read back to prove the round-trip.
    private static let headerRow = ["Label", "Value"]
    private static let seedValues: [[String]] = [
        headerRow,
        ["Alpha", "10"],
        ["Beta", "20"],
        ["Gamma", "30"],
    ]
    // Two more rows appended below the seed, growing the table to A1:B6.
    private static let appendedValues: [[String]] = [["Delta", "40"], ["Epsilon", "50"]]

    /// Runs every live-test step in its stable order.
    public func run() async -> SheetsLiveTestSummary {
        let recorder = Recorder(onStep: onStep)

        // The only hard prerequisites. If either fails, there is no safe target
        // for the remainder of the run.
        guard let folder = await valueStep("folder", recorder: recorder, createdIDs: {
            $0.created ? [$0.file.id] : []
        }, operation: findOrCreateFolder) else {
            return recorder.summary
        }
        // The spreadsheet is created through Drive so it lands inside the test
        // folder, exactly as the Docs and Slides runners parent their files
        // there. The Drive file id is the spreadsheet id the Sheets client then
        // addresses.
        guard let spreadsheetFile = await valueStep(
            "create-spreadsheet",
            recorder: recorder,
            createdIDs: { [$0.id] },
            operation: {
                try await drive.create(
                    name: "graham test sheet \(label)", type: .sheets, parent: folder.file.id)
            }
        ) else {
            return recorder.summary
        }

        let spreadsheetID = spreadsheetFile.id

        // Write, then read the same range back to prove the values round-trip.
        let valuesSet = await actionStep("set-values", recorder: recorder) {
            let response = try await sheets.setValues(
                spreadsheetId: spreadsheetID, range: "A1:B4", values: Self.seedValues)
            guard let updatedCells = response.updatedCells, updatedCells > 0 else {
                throw GrahamError.invalidResponse("setting values updated no cells")
            }
        }
        _ = await actionStep(
            "values-read", recorder: recorder,
            skipReason: valuesSet ? nil : "set-values failed"
        ) {
            let range = try await sheets.values(spreadsheetId: spreadsheetID, range: "A1:B4")
            let rows = (range.values ?? []).map { $0.map(\.display) }
            guard rows.count == Self.seedValues.count, rows.first == Self.headerRow else {
                throw GrahamError.invalidResponse("the written values did not round-trip")
            }
        }
        // Append two rows below the table, then read the grown range back.
        let appended = await actionStep(
            "append", recorder: recorder,
            skipReason: valuesSet ? nil : "set-values failed"
        ) {
            let response = try await sheets.appendValues(
                spreadsheetId: spreadsheetID, range: "A1:B4", values: Self.appendedValues)
            guard let updatedCells = response.updates?.updatedCells, updatedCells > 0 else {
                throw GrahamError.invalidResponse("appending rows updated no cells")
            }
        }
        _ = await actionStep(
            "append-read", recorder: recorder,
            skipReason: appended ? nil : "append failed"
        ) {
            let range = try await sheets.values(spreadsheetId: spreadsheetID, range: "A1:B6")
            let rows = (range.values ?? []).map { $0.map(\.display) }
            let expectedCount = Self.seedValues.count + Self.appendedValues.count
            guard rows.count == expectedCount, rows.last == Self.appendedValues.last else {
                throw GrahamError.invalidResponse("the appended rows did not round-trip")
            }
        }
        // A raw (unformatted) read returns the same header row.
        _ = await actionStep(
            "raw-read", recorder: recorder,
            skipReason: valuesSet ? nil : "set-values failed"
        ) {
            let range = try await sheets.values(
                spreadsheetId: spreadsheetID, range: "A1:B1", renderOption: .unformatted)
            let first = (range.values?.first ?? []).map(\.display)
            guard first == Self.headerRow else {
                throw GrahamError.invalidResponse("the raw read did not round-trip")
            }
        }
        // A batchGet reads two ranges in one call.
        _ = await actionStep(
            "batch-get", recorder: recorder,
            skipReason: valuesSet ? nil : "set-values failed"
        ) {
            let response = try await sheets.batchGetValues(
                spreadsheetId: spreadsheetID, ranges: ["A1:B1", "A2:B2"])
            guard (response.valueRanges?.count ?? 0) == 2 else {
                throw GrahamError.invalidResponse("batchGet returned the wrong number of ranges")
            }
        }
        _ = await actionStep("get", recorder: recorder) {
            let read = try await sheets.spreadsheet(id: spreadsheetID)
            guard read.spreadsheetId == spreadsheetID else {
                throw GrahamError.invalidResponse("spreadsheet id did not round-trip")
            }
            guard !(read.sheets ?? []).isEmpty else {
                throw GrahamError.invalidResponse("the spreadsheet reported no sheets")
            }
        }
        // A chart needs the data above, so it chains off the value write.
        _ = await valueStep(
            "chart-add", recorder: recorder,
            skipReason: valuesSet ? nil : "set-values failed",
            createdIDs: { [String($0)] }
        ) {
            try await sheets.addChart(
                spreadsheetId: spreadsheetID,
                title: "Graham live test",
                type: .column,
                range: "A1:B4"
            )
        }
        // Clear the values, then confirm the read comes back empty.
        let cleared = await actionStep(
            "clear", recorder: recorder,
            skipReason: valuesSet ? nil : "set-values failed"
        ) {
            let response = try await sheets.clearValues(
                spreadsheetId: spreadsheetID, range: "A1:B6")
            guard let clearedRange = response.clearedRange, !clearedRange.isEmpty else {
                throw GrahamError.invalidResponse("clear returned no cleared range")
            }
        }
        _ = await actionStep(
            "clear-read", recorder: recorder,
            skipReason: cleared ? nil : "clear failed"
        ) {
            let range = try await sheets.values(spreadsheetId: spreadsheetID, range: "A1:B6")
            guard (range.values ?? []).isEmpty else {
                throw GrahamError.invalidResponse("the cleared range is not empty")
            }
        }

        await cleanupStep(
            "drive-trash-spreadsheet", fileID: spreadsheetID,
            recorder: recorder, prerequisite: true)

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
        prerequisite: Bool,
        dependency: String? = nil
    ) async {
        if keep {
            recorder.record(name: name, outcome: .skip(reason: "kept"))
            return
        }
        let reason: String?
        if prerequisite, fileID != nil {
            reason = nil
        } else {
            reason = "\(dependency ?? "creation") failed"
        }
        _ = await actionStep(name, recorder: recorder, skipReason: reason) {
            _ = try await drive.trash(fileId: fileID!)
        }
    }

    // MARK: - Step primitives (mirror DocsLiveTest / SlidesLiveTest)

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

    private static func reason(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description.replacingOccurrences(of: "\n", with: " ")
        }
        return String(describing: error).replacingOccurrences(of: "\n", with: " ")
    }
}

private extension SheetsLiveTest {
    struct FolderResult: Sendable {
        let file: DriveFile
        let created: Bool
    }

    final class Recorder: @unchecked Sendable {
        private(set) var steps: [SheetsLiveTestStep] = []
        private let onStep: @Sendable (SheetsLiveTestStep) -> Void

        init(onStep: @escaping @Sendable (SheetsLiveTestStep) -> Void) {
            self.onStep = onStep
        }

        func record(
            name: String,
            outcome: SheetsLiveTestOutcome,
            createdIDs: [String] = []
        ) {
            let step = SheetsLiveTestStep(
                name: name, outcome: outcome, createdIDs: createdIDs)
            steps.append(step)
            onStep(step)
        }

        var summary: SheetsLiveTestSummary {
            SheetsLiveTestSummary(steps: steps)
        }
    }
}
