import Foundation

/// The outcome of one named live-test step.
public enum SlidesLiveTestOutcome: Sendable, Equatable {
    case pass
    case fail(reason: String)
    case skip(reason: String)
}

/// One completed step in a ``SlidesLiveTest`` run.
public struct SlidesLiveTestStep: Sendable, Equatable {
    public let name: String
    public let outcome: SlidesLiveTestOutcome
    public let createdIDs: [String]

    public init(name: String, outcome: SlidesLiveTestOutcome, createdIDs: [String] = []) {
        self.name = name
        self.outcome = outcome
        self.createdIDs = createdIDs
    }
}

/// The complete result of a ``SlidesLiveTest`` run.
public struct SlidesLiveTestSummary: Sendable, Equatable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let steps: [SlidesLiveTestStep]

    public init(steps: [SlidesLiveTestStep]) {
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

/// Runs graham's full command surface against a disposable presentation.
///
/// The runner owns sequencing, dependency skips, read-back verification, and
/// cleanup. It never prints: each completed step is delivered through
/// `onStep`, and the full ordered result is returned to the caller.
public struct SlidesLiveTest: Sendable {
    public static let defaultImageURL =
        "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png"

    private let drive: DriveClient
    private let slides: SlidesClient
    private let sheets: SheetsClient
    private let docs: DocsClient
    private let folderName: String
    private let imageURL: String
    private let keep: Bool
    private let label: String
    private let onStep: @Sendable (SlidesLiveTestStep) -> Void

    public init(
        drive: DriveClient,
        slides: SlidesClient,
        sheets: SheetsClient,
        docs: DocsClient,
        folderName: String = "graham test",
        imageURL: String = SlidesLiveTest.defaultImageURL,
        keep: Bool = false,
        label: String,
        onStep: @escaping @Sendable (SlidesLiveTestStep) -> Void = { _ in }
    ) {
        self.drive = drive
        self.slides = slides
        self.sheets = sheets
        self.docs = docs
        self.folderName = folderName
        self.imageURL = imageURL
        self.keep = keep
        self.label = label
        self.onStep = onStep
    }

    /// Runs every live-test step in its stable order.
    public func run() async -> SlidesLiveTestSummary {
        let recorder = Recorder(onStep: onStep)

        // The only hard prerequisites. If either fails, there is no safe target
        // for the remainder of the run.
        guard let folder = await valueStep("folder", recorder: recorder, createdIDs: {
            $0.created ? [$0.file.id] : []
        }, operation: findOrCreateFolder) else {
            return recorder.summary
        }
        guard let presentation = await valueStep(
            "create-presentation",
            recorder: recorder,
            createdIDs: { [$0.id] },
            operation: {
                try await drive.create(
                    name: "graham test \(label)", type: .slides, parent: folder.file.id)
            }
        ) else {
            return recorder.summary
        }

        let folderID = folder.file.id
        let presentationID = presentation.id

        // Slides lifecycle.
        let primarySlide = await valueStep(
            "slides-add", recorder: recorder, createdIDs: { [$0] },
            operation: {
                try await slides.createSlide(presentationId: presentationID)
            }
        )
        let layoutSlide = await valueStep(
            "slides-add-at-layout", recorder: recorder, createdIDs: { [$0] },
            operation: {
                try await slides.createSlide(
                    presentationId: presentationID, at: 2, layout: "TITLE_AND_BODY")
            }
        )
        let layoutID = await valueStep("layouts-read", recorder: recorder) {
            let deck = try await slides.presentation(id: presentationID)
            guard let id = deck.layoutRows.compactMap(\.objectId).first else {
                throw GrahamError.invalidResponse("the presentation has no layout id")
            }
            return id
        }
        let exactLayoutSlide = await valueStep(
            "slides-add-layout-id",
            recorder: recorder,
            skipReason: dependencyReason("layouts-read", value: layoutID),
            createdIDs: { [$0] },
            operation: {
                try await slides.createSlide(
                    presentationId: presentationID, layoutId: layoutID!)
            }
        )
        _ = await actionStep(
            "slides-move",
            recorder: recorder,
            skipReason: dependencyReason("slides-add-layout-id", value: exactLayoutSlide)
        ) {
            try await slides.moveSlide(
                presentationId: presentationID, slideId: exactLayoutSlide!, to: 1)
        }
        _ = await actionStep(
            "slides-delete",
            recorder: recorder,
            skipReason: dependencyReason("slides-add-at-layout", value: layoutSlide)
        ) {
            let before = try await slides.presentation(
                id: presentationID, fields: "slides.objectId")
            try await slides.deleteObject(presentationId: presentationID, objectId: layoutSlide!)
            let after = try await slides.presentation(
                id: presentationID, fields: "slides.objectId")
            let beforeIDs = (before.slides ?? []).compactMap(\.objectId)
            let afterIDs = (after.slides ?? []).compactMap(\.objectId)
            guard beforeIDs.count == afterIDs.count + 1, !afterIDs.contains(layoutSlide!) else {
                throw GrahamError.invalidResponse("slide count did not decrease by one")
            }
        }

        // Elements.
        let textBox = await valueStep(
            "create-textbox",
            recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide),
            createdIDs: { [$0] }
        ) {
            try await slides.createTextBox(
                presentationId: presentationID,
                slideId: primarySlide!,
                text: "Graham live test",
                x: 40, y: 30, width: 240, height: 50
            )
        }
        let image = await valueStep(
            "create-image",
            recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide),
            createdIDs: { [$0] }
        ) {
            try await slides.createImage(
                presentationId: presentationID,
                slideId: primarySlide!,
                url: imageURL,
                x: 40, y: 100, width: 180, height: 61
            )
        }
        let video = await valueStep(
            "create-video",
            recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide),
            createdIDs: { [$0] }
        ) {
            try await slides.createVideo(
                presentationId: presentationID,
                slideId: primarySlide!,
                videoId: "dQw4w9WgXcQ",
                x: 250, y: 100, width: 240, height: 135
            )
        }
        let line = await valueStep(
            "create-line",
            recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide),
            createdIDs: { [$0] }
        ) {
            try await slides.createLine(
                presentationId: presentationID,
                slideId: primarySlide!,
                x: 40, y: 260, width: 220, height: 1
            )
        }
        let table = await valueStep(
            "create-table",
            recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide),
            createdIDs: { [$0] }
        ) {
            try await slides.createTable(
                presentationId: presentationID,
                slideId: primarySlide!,
                rows: 3, columns: 3,
                x: 300, y: 280, width: 360, height: 150
            )
        }
        recorder.record(
            name: "create-chart",
            outcome: .skip(reason: "graham cannot create an embedded Sheets chart to link yet")
        )
        recorder.record(
            name: "chart-refresh",
            outcome: .skip(reason: "graham cannot create an embedded Sheets chart to link yet")
        )

        let createdElementIDs = [textBox, image, video, line, table].compactMap { $0 }
        _ = await actionStep(
            "elements-list",
            recorder: recorder,
            skipReason: createdElementIDs.isEmpty ? "no elements were created" : nil
        ) {
            let rows = try await slides.presentation(id: presentationID).elementRows
            let found = Set(rows.compactMap(\.objectId))
            let missing = createdElementIDs.filter { !found.contains($0) }
            guard missing.isEmpty else {
                throw GrahamError.invalidResponse(
                    "element list is missing id(s): \(missing.joined(separator: ", "))")
            }
        }
        _ = await actionStep(
            "images-list",
            recorder: recorder,
            skipReason: dependencyReason("create-image", value: image)
        ) {
            let rows = try await slides.presentation(id: presentationID).imageRows
            guard rows.contains(where: { $0.objectId == image! }) else {
                throw GrahamError.invalidResponse("image list is missing \(image!)")
            }
        }

        // Geometry.
        _ = await actionStep(
            "element-move", recorder: recorder,
            skipReason: dependencyReason("create-textbox", value: textBox)
        ) {
            try await slides.moveElement(
                presentationId: presentationID, objectId: textBox!, toX: 60, toY: 40)
        }
        _ = await actionStep(
            "element-scale", recorder: recorder,
            skipReason: dependencyReason("create-textbox", value: textBox)
        ) {
            try await slides.scaleElement(
                presentationId: presentationID, objectId: textBox!, by: 1.05)
        }
        _ = await actionStep(
            "element-rotate", recorder: recorder,
            skipReason: dependencyReason("create-textbox", value: textBox)
        ) {
            try await slides.rotateElement(
                presentationId: presentationID, objectId: textBox!, byDegrees: 2)
        }
        _ = await actionStep(
            "element-transform", recorder: recorder,
            skipReason: dependencyReason("create-textbox", value: textBox)
        ) {
            try await slides.transformElement(
                presentationId: presentationID,
                objectId: textBox!,
                transform: ElementTransform(
                    translateX: 70, translateY: 45, unit: .pt),
                mode: .absolute
            )
        }
        let reorderReason = firstFailed([
            ("create-textbox", textBox != nil),
            ("create-image", image != nil),
        ])
        _ = await actionStep(
            "element-reorder", recorder: recorder, skipReason: reorderReason
        ) {
            try await slides.reorderElements(
                presentationId: presentationID,
                objectIds: [textBox!, image!],
                operation: .bringToFront
            )
        }

        // Group two shapes created solely for this operation.
        let group: GroupResult?
        if primarySlide == nil {
            recorder.record(name: "group", outcome: .skip(reason: "slides-add failed"))
            group = nil
        } else {
            var childIDs: [String] = []
            do {
                let first = try await slides.createTextBox(
                    presentationId: presentationID, slideId: primarySlide!, text: "",
                    x: 40, y: 350, width: 80, height: 40)
                childIDs.append(first)
                let second = try await slides.createTextBox(
                    presentationId: presentationID, slideId: primarySlide!, text: "",
                    x: 140, y: 350, width: 80, height: 40)
                childIDs.append(second)
                let groupID = try await slides.groupElements(
                    presentationId: presentationID, childIds: childIDs)
                let result = GroupResult(groupID: groupID, childIDs: childIDs)
                recorder.record(name: "group", outcome: .pass, createdIDs: result.allIDs)
                group = result
            } catch {
                recorder.record(
                    name: "group",
                    outcome: .fail(reason: Self.reason(for: error)),
                    createdIDs: childIDs
                )
                group = nil
            }
        }
        _ = await actionStep(
            "ungroup", recorder: recorder,
            skipReason: dependencyReason("group", value: group)
        ) {
            try await slides.ungroupElements(
                presentationId: presentationID, objectIds: [group!.groupID])
        }

        // Styles.
        let red = OpaqueColor(red: 0.85, green: 0.12, blue: 0.12)
        let blue = OpaqueColor(red: 0.12, green: 0.32, blue: 0.85)
        _ = await actionStep(
            "style-shape", recorder: recorder,
            skipReason: dependencyReason("create-textbox", value: textBox)
        ) {
            try await slides.styleShape(
                presentationId: presentationID,
                objectId: textBox!,
                fillColor: blue,
                outlineColor: red,
                outlineWeight: 1,
                shadowColor: OpaqueColor(red: 0, green: 0, blue: 0),
                shadowAlpha: 0.3,
                shadowBlur: 2,
                shadowOffsetX: 1,
                shadowOffsetY: 1,
                contentAlignment: .middle
            )
        }
        _ = await actionStep(
            "style-image", recorder: recorder,
            skipReason: dependencyReason("create-image", value: image)
        ) {
            try await slides.styleImage(
                presentationId: presentationID,
                objectId: image!,
                outlineColor: blue,
                outlineWeight: 1
            )
        }
        _ = await actionStep(
            "style-line", recorder: recorder,
            skipReason: dependencyReason("create-line", value: line)
        ) {
            try await slides.styleLine(
                presentationId: presentationID,
                objectId: line!,
                color: red,
                weight: 2,
                dash: .dash,
                endArrow: .openArrow
            )
        }
        _ = await actionStep(
            "style-video", recorder: recorder,
            skipReason: dependencyReason("create-video", value: video)
        ) {
            try await slides.styleVideo(
                presentationId: presentationID,
                objectId: video!,
                autoPlay: true,
                mute: true,
                start: 1,
                end: 10
            )
        }

        // Table operations. Each can run against the created table; unmerge is
        // the sole operation that specifically requires the merge to succeed.
        let tableReason = dependencyReason("create-table", value: table)
        let insertedRows = await actionStep(
            "table-insert-rows", recorder: recorder, skipReason: tableReason
        ) {
            try await slides.insertTableRows(
                presentationId: presentationID, tableId: table!, row: 1, below: true)
        }
        let insertedColumns = await actionStep(
            "table-insert-columns", recorder: recorder, skipReason: tableReason
        ) {
            try await slides.insertTableColumns(
                presentationId: presentationID, tableId: table!, column: 1, right: true)
        }
        let merged = await actionStep("table-merge", recorder: recorder, skipReason: tableReason) {
            try await slides.mergeTableCells(
                presentationId: presentationID, tableId: table!,
                row: 1, column: 1, rowSpan: 2, columnSpan: 2)
        }
        _ = await actionStep(
            "table-unmerge", recorder: recorder,
            skipReason: merged ? nil : "table-merge failed"
        ) {
            try await slides.unmergeTableCells(
                presentationId: presentationID, tableId: table!,
                row: 1, column: 1, rowSpan: 2, columnSpan: 2)
        }
        _ = await actionStep("table-style-cells", recorder: recorder, skipReason: tableReason) {
            try await slides.styleTableCells(
                presentationId: presentationID, tableId: table!,
                fillColor: blue, alignment: .middle)
        }
        _ = await actionStep("table-row-height", recorder: recorder, skipReason: tableReason) {
            try await slides.setTableRowHeight(
                presentationId: presentationID, tableId: table!, rows: [1], minHeight: 24)
        }
        _ = await actionStep("table-column-width", recorder: recorder, skipReason: tableReason) {
            try await slides.setTableColumnWidth(
                presentationId: presentationID, tableId: table!, columns: [1], width: 72)
        }
        _ = await actionStep("table-borders", recorder: recorder, skipReason: tableReason) {
            try await slides.styleTableBorders(
                presentationId: presentationID, tableId: table!,
                position: .all, color: red, weight: 1, dash: .solid)
        }
        _ = await actionStep(
            "table-delete-row", recorder: recorder,
            skipReason: insertedRows ? nil : "table-insert-rows failed"
        ) {
            try await slides.deleteTableRow(
                presentationId: presentationID, tableId: table!, row: 4)
        }
        _ = await actionStep(
            "table-delete-column", recorder: recorder,
            skipReason: insertedColumns ? nil : "table-insert-columns failed"
        ) {
            try await slides.deleteTableColumn(
                presentationId: presentationID, tableId: table!, column: 4)
        }

        // Text operations on the text box, plus one table-cell insertion.
        let textReason = dependencyReason("create-textbox", value: textBox)
        _ = await actionStep("text-insert", recorder: recorder, skipReason: textReason) {
            try await slides.insertText(
                presentationId: presentationID, objectId: textBox!,
                text: "Live ", insertionIndex: 0)
        }
        _ = await actionStep("text-style", recorder: recorder, skipReason: textReason) {
            try await slides.styleText(
                presentationId: presentationID, objectId: textBox!,
                bold: true, color: red, fontSize: 18)
        }
        _ = await actionStep("text-link", recorder: recorder, skipReason: textReason) {
            try await slides.styleText(
                presentationId: presentationID, objectId: textBox!,
                link: .url("https://example.com/graham-live-test"))
        }
        _ = await actionStep("text-paragraph", recorder: recorder, skipReason: textReason) {
            try await slides.styleParagraphs(
                presentationId: presentationID, objectId: textBox!,
                alignment: .center, lineSpacing: 125)
        }
        let bulleted = await actionStep("text-bullets", recorder: recorder, skipReason: textReason) {
            try await slides.createBullets(
                presentationId: presentationID, objectId: textBox!,
                preset: .bulletDiscCircleSquare)
        }
        _ = await actionStep(
            "text-unbullet", recorder: recorder,
            skipReason: bulleted ? nil : "text-bullets failed"
        ) {
            try await slides.deleteBullets(
                presentationId: presentationID, objectId: textBox!)
        }
        _ = await actionStep("text-delete", recorder: recorder, skipReason: textReason) {
            try await slides.deleteText(
                presentationId: presentationID, objectId: textBox!, from: 0, to: 5)
        }
        _ = await actionStep("text-insert-cell", recorder: recorder, skipReason: tableReason) {
            try await slides.insertText(
                presentationId: presentationID, objectId: table!,
                text: "cell", row: 1, column: 1)
        }

        // Alt text and speaker notes.
        let altTitle = "graham live test"
        let altDescription = "verified by \(label)"
        let altSet = await actionStep("alt-text-set", recorder: recorder, skipReason: textReason) {
            try await slides.setAltText(
                presentationId: presentationID, objectId: textBox!,
                title: altTitle, description: altDescription)
        }
        _ = await actionStep(
            "alt-text-verify", recorder: recorder,
            skipReason: altSet ? nil : "alt-text-set failed"
        ) {
            let rows = try await slides.presentation(id: presentationID).elementRows
            guard let row = rows.first(where: { $0.objectId == textBox! }),
                  row.title == altTitle,
                  row.description == altDescription
            else {
                throw GrahamError.invalidResponse("alt text did not round-trip")
            }
        }
        _ = await actionStep("alt-text-clear", recorder: recorder, skipReason: textReason) {
            try await slides.setAltText(
                presentationId: presentationID, objectId: textBox!,
                title: "", description: "")
        }

        let notesText = "graham live test notes \(label)"
        let notesSet = await actionStep(
            "notes-set", recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide)
        ) {
            try await slides.setSpeakerNotes(
                presentationId: presentationID, slideId: primarySlide!, text: notesText)
        }
        _ = await actionStep(
            "notes-verify", recorder: recorder,
            skipReason: notesSet ? nil : "notes-set failed"
        ) {
            let rows = try await slides.speakerNotes(presentationId: presentationID)
            guard rows.first(where: { $0.slideId == primarySlide! })?.notes == notesText else {
                throw GrahamError.invalidResponse("speaker notes did not round-trip")
            }
        }
        _ = await actionStep(
            "notes-clear", recorder: recorder,
            skipReason: dependencyReason("slides-add", value: primarySlide)
        ) {
            try await slides.clearSpeakerNotes(
                presentationId: presentationID, slideId: primarySlide!)
        }

        _ = await actionStep(
            "element-delete", recorder: recorder,
            skipReason: dependencyReason("create-line", value: line)
        ) {
            try await slides.deleteObject(presentationId: presentationID, objectId: line!)
            let rows = try await slides.presentation(id: presentationID).elementRows
            guard !rows.contains(where: { $0.objectId == line! }) else {
                throw GrahamError.invalidResponse("deleted element still appears in the deck")
            }
        }

        // Other Google Workspace services, all created in the test folder.
        let sheet = await valueStep(
            "sheets-create", recorder: recorder, createdIDs: { [$0.id] }
        ) {
            try await drive.create(
                name: "graham test sheet \(label)", type: .sheets, parent: folderID)
        }
        _ = await actionStep(
            "sheets-get", recorder: recorder,
            skipReason: dependencyReason("sheets-create", value: sheet)
        ) {
            let read = try await sheets.spreadsheet(id: sheet!.id)
            guard read.spreadsheetId == sheet!.id else {
                throw GrahamError.invalidResponse("spreadsheet id did not round-trip")
            }
        }
        let document = await valueStep(
            "docs-create", recorder: recorder, createdIDs: { [$0.id] }
        ) {
            try await drive.create(
                name: "graham test doc \(label)", type: .docs, parent: folderID)
        }
        _ = await actionStep(
            "docs-cat", recorder: recorder,
            skipReason: dependencyReason("docs-create", value: document)
        ) {
            let read = try await docs.document(id: document!.id)
            guard read.documentId == document!.id else {
                throw GrahamError.invalidResponse("document id did not round-trip")
            }
            _ = read.plainText
        }

        // Drive lifecycle. The copy is permanently deleted immediately; it is
        // the only permanent delete in the run.
        let copy = await valueStep(
            "drive-copy", recorder: recorder, createdIDs: { [$0.id] }
        ) {
            try await drive.copy(
                fileId: presentationID,
                name: "graham test copy \(label)",
                parent: folderID
            )
        }
        _ = await actionStep(
            "drive-delete-copy", recorder: recorder,
            skipReason: dependencyReason("drive-copy", value: copy)
        ) {
            try await drive.delete(fileId: copy!.id)
        }

        await cleanupStep(
            "drive-trash-presentation", fileID: presentationID,
            recorder: recorder, prerequisite: true)
        await cleanupStep(
            "drive-trash-sheet", fileID: sheet?.id,
            recorder: recorder, prerequisite: sheet != nil,
            dependency: "sheets-create")
        await cleanupStep(
            "drive-trash-doc", fileID: document?.id,
            recorder: recorder, prerequisite: document != nil,
            dependency: "docs-create")

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
        guard let failed = dependencies.first(where: { !$0.1 }) else { return nil }
        return "\(failed.0) failed"
    }

    private static func reason(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description.replacingOccurrences(of: "\n", with: " ")
        }
        return String(describing: error).replacingOccurrences(of: "\n", with: " ")
    }
}

private extension SlidesLiveTest {
    struct FolderResult: Sendable {
        let file: DriveFile
        let created: Bool
    }

    struct GroupResult: Sendable {
        let groupID: String
        let childIDs: [String]

        var allIDs: [String] { childIDs + [groupID] }
    }

    final class Recorder: @unchecked Sendable {
        private(set) var steps: [SlidesLiveTestStep] = []
        private let onStep: @Sendable (SlidesLiveTestStep) -> Void

        init(onStep: @escaping @Sendable (SlidesLiveTestStep) -> Void) {
            self.onStep = onStep
        }

        func record(
            name: String,
            outcome: SlidesLiveTestOutcome,
            createdIDs: [String] = []
        ) {
            let step = SlidesLiveTestStep(
                name: name, outcome: outcome, createdIDs: createdIDs)
            steps.append(step)
            onStep(step)
        }

        var summary: SlidesLiveTestSummary {
            SlidesLiveTestSummary(steps: steps)
        }
    }
}
