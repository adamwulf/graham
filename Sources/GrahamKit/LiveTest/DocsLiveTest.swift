import Foundation

/// The outcome of one named live-test step.
public enum DocsLiveTestOutcome: Sendable, Equatable {
    case pass
    case fail(reason: String)
    case skip(reason: String)
}

/// One completed step in a ``DocsLiveTest`` run.
public struct DocsLiveTestStep: Sendable, Equatable {
    public let name: String
    public let outcome: DocsLiveTestOutcome
    public let createdIDs: [String]

    public init(name: String, outcome: DocsLiveTestOutcome, createdIDs: [String] = []) {
        self.name = name
        self.outcome = outcome
        self.createdIDs = createdIDs
    }
}

/// The complete result of a ``DocsLiveTest`` run.
public struct DocsLiveTestSummary: Sendable, Equatable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let steps: [DocsLiveTestStep]

    public init(steps: [DocsLiveTestStep]) {
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

/// Runs graham's full Docs command surface against a disposable document.
///
/// The runner owns sequencing, dependency skips, read-back verification, and
/// cleanup. It never prints: each completed step is delivered through
/// `onStep`, and the full ordered result is returned to the caller. This is the
/// Docs analog of ``SlidesLiveTest``.
///
/// Docs indices shift after every write, so the runner never hardcodes an index
/// across a chain of edits. Between steps it re-fetches the ``Document`` and
/// reads the live model — a paragraph's block range, a table's start index — to
/// target the next operation, exactly as a user would read them from
/// `docs structure`. Each write is verified by reading back where practical.
public struct DocsLiveTest: Sendable {
    public static let defaultImageURL =
        "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png"

    /// A second public image, used by `image-replace`.
    public static let replacementImageURL =
        "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png"

    private let drive: DriveClient
    private let docs: DocsClient
    private let folderName: String
    private let imageURL: String
    private let keep: Bool
    private let label: String
    private let onStep: @Sendable (DocsLiveTestStep) -> Void

    public init(
        drive: DriveClient,
        docs: DocsClient,
        folderName: String = "graham test",
        imageURL: String = DocsLiveTest.defaultImageURL,
        keep: Bool = false,
        label: String,
        onStep: @escaping @Sendable (DocsLiveTestStep) -> Void = { _ in }
    ) {
        self.drive = drive
        self.docs = docs
        self.folderName = folderName
        self.imageURL = imageURL
        self.keep = keep
        self.label = label
        self.onStep = onStep
    }

    // The paragraph markers inserted at body index 1 as one multi-line block.
    // The runner locates each paragraph by its trimmed one-line preview, which
    // is exactly its marker text, so it can target the next op by that
    // paragraph's current range no matter how earlier edits shifted it.
    private static let headingText = "graham heading"
    private static let styledText = "graham styled"
    private static let linkedText = "graham linked"
    private static let paraText = "graham para"
    private static let listAText = "graham list a"
    private static let listBText = "graham list b"
    private static let replaceText = "graham replace me"
    private static let replacedText = "graham replaced"
    private static let deleteText = "graham delete me"
    private static let appendedText = "graham appended"

    /// Runs every live-test step in its stable order.
    public func run() async -> DocsLiveTestSummary {
        let recorder = Recorder(onStep: onStep)

        // The only hard prerequisites. If either fails, there is no safe target
        // for the remainder of the run.
        guard let folder = await valueStep("folder", recorder: recorder, createdIDs: {
            $0.created ? [$0.file.id] : []
        }, operation: findOrCreateFolder) else {
            return recorder.summary
        }
        // The document is created through Drive so it lands inside the test
        // folder, exactly as SlidesLiveTest parents its presentation there. The
        // Drive file id is the document id the Docs client then addresses.
        guard let documentFile = await valueStep(
            "create-doc",
            recorder: recorder,
            createdIDs: { [$0.id] },
            operation: {
                try await drive.create(
                    name: "graham test doc \(label)", type: .docs, parent: folder.file.id)
            }
        ) else {
            return recorder.summary
        }

        let documentID = documentFile.id

        // Reads. Each fetches the document and exercises one read facade.
        _ = await actionStep("doc-fetch", recorder: recorder) {
            let read = try await docs.document(id: documentID)
            guard read.documentId == documentID else {
                throw GrahamError.invalidResponse("document id did not round-trip")
            }
        }
        _ = await actionStep("structure-read", recorder: recorder) {
            let read = try await docs.document(id: documentID)
            guard !read.blockRows.isEmpty else {
                throw GrahamError.invalidResponse("the new document has no structural blocks")
            }
        }
        _ = await actionStep("plaintext-read", recorder: recorder) {
            _ = try await docs.document(id: documentID).plainText
        }
        _ = await actionStep("markdown-read", recorder: recorder) {
            _ = try await docs.document(id: documentID).markdown
        }
        _ = await actionStep("images-read", recorder: recorder) {
            _ = try await docs.document(id: documentID).imageRows
        }

        // documents.create: a second, throwaway document created directly through
        // DocsClient (not Drive), verified by its id and — through a read-back —
        // its title, then trashed in cleanup. The main disposable document above
        // stays folder-parented; this one lands in My Drive.
        let createdDocID = await valueStep(
            "docs-create", recorder: recorder, createdIDs: { [$0] }
        ) {
            let title = "graham docs-create \(label)"
            let created = try await docs.create(title: title)
            guard let id = created.documentId, !id.isEmpty else {
                throw GrahamError.invalidResponse("docs.create returned no document id")
            }
            let read = try await docs.document(id: id)
            guard read.documentId == id, read.title == title else {
                throw GrahamError.invalidResponse("the created document did not round-trip")
            }
            return id
        }

        // Text. One explicit-index insert seeds the body with several marker
        // paragraphs; the rest read those paragraphs back to target the edit.
        let insertedText = await actionStep("text-insert", recorder: recorder) {
            let block = [
                Self.headingText, Self.styledText, Self.linkedText, Self.paraText,
                Self.listAText, Self.listBText, Self.replaceText, Self.deleteText,
            ].map { $0 + "\n" }.joined()
            // Index 1 is the first editable body index (index 0 lands inside the
            // initial section break the body cannot edit).
            _ = try await docs.insertText(documentId: documentID, text: block, index: 1)
            let after = try await docs.document(id: documentID)
            guard self.blockRange(after, preview: Self.headingText) != nil else {
                throw GrahamError.invalidResponse("the inserted text did not round-trip")
            }
        }
        let insertedSkip = insertedText ? nil : "text-insert failed"

        // End-of-body insert: append a paragraph without computing an index.
        _ = await actionStep("text-append-end", recorder: recorder) {
            _ = try await docs.insertText(
                documentId: documentID, text: Self.appendedText + "\n",
                index: 0, endOfSegment: true)
            let after = try await docs.document(id: documentID)
            guard self.blockRange(after, preview: Self.appendedText) != nil else {
                throw GrahamError.invalidResponse("the appended text did not round-trip")
            }
        }
        _ = await actionStep("text-replace", recorder: recorder, skipReason: insertedSkip) {
            let count = try await docs.replaceAllText(
                documentId: documentID, find: Self.replaceText, replace: Self.replacedText)
            guard count == 1 else {
                throw GrahamError.invalidResponse(
                    "replaceAllText changed \(count) occurrences, expected 1")
            }
            let after = try await docs.document(id: documentID)
            guard self.blockRange(after, preview: Self.replacedText) != nil,
                  self.blockRange(after, preview: Self.replaceText) == nil else {
                throw GrahamError.invalidResponse("the replacement did not round-trip")
            }
        }
        _ = await actionStep("text-delete", recorder: recorder, skipReason: insertedSkip) {
            let before = try await docs.document(id: documentID)
            let range = try self.requireRange(before, preview: Self.deleteText)
            _ = try await docs.deleteContentRange(
                documentId: documentID, startIndex: range.start, endIndex: range.end)
            let after = try await docs.document(id: documentID)
            guard self.blockRange(after, preview: Self.deleteText) == nil else {
                throw GrahamError.invalidResponse("the deleted paragraph is still present")
            }
        }
        let red = DocsOptionalColor(rgb: DocsRgbColor(red: 0.85, green: 0.12, blue: 0.12))
        let yellow = DocsOptionalColor(rgb: DocsRgbColor(red: 1, green: 1, blue: 0.6))
        let black = DocsOptionalColor(rgb: DocsRgbColor(red: 0, green: 0, blue: 0))
        let gray = DocsOptionalColor(rgb: DocsRgbColor(red: 0.5, green: 0.5, blue: 0.5))
        let white = DocsOptionalColor(rgb: DocsRgbColor(red: 1, green: 1, blue: 1))
        _ = await actionStep("text-style", recorder: recorder, skipReason: insertedSkip) {
            let document = try await docs.document(id: documentID)
            let range = try self.requireRange(document, preview: Self.styledText)
            _ = try await docs.styleText(
                documentId: documentID,
                startIndex: range.start, endIndex: self.innerEnd(range),
                bold: true, foregroundColor: red, fontSize: 12)
        }
        _ = await actionStep("text-link", recorder: recorder, skipReason: insertedSkip) {
            let document = try await docs.document(id: documentID)
            let range = try self.requireRange(document, preview: Self.linkedText)
            _ = try await docs.styleText(
                documentId: documentID,
                startIndex: range.start, endIndex: self.innerEnd(range),
                linkURL: "https://example.com/graham-doc-live-test")
        }

        // Paragraph styling: named style, alignment, spacing, indents, a
        // pagination flag, shading, and paragraph borders in one call.
        _ = await actionStep("paragraph-style", recorder: recorder, skipReason: insertedSkip) {
            let document = try await docs.document(id: documentID)
            let range = try self.requireRange(document, preview: Self.paraText)
            _ = try await docs.styleParagraphs(
                documentId: documentID,
                startIndex: range.start, endIndex: range.end,
                namedStyleType: "NORMAL_TEXT",
                alignment: .center,
                lineSpacing: 150,
                spaceAbove: 6, spaceBelow: 6,
                indentStart: 18, indentEnd: 18, indentFirstLine: 12,
                keepLinesTogether: true,
                shadingBackgroundColor: yellow,
                spacingMode: .neverCollapse,
                outerBorderColor: black, betweenBorderColor: gray,
                borderWidth: 1, borderDash: .solid, borderPadding: 2)
        }
        // The Docs heading convenience: styleParagraphs with only a named style.
        _ = await actionStep("heading", recorder: recorder, skipReason: insertedSkip) {
            let document = try await docs.document(id: documentID)
            let range = try self.requireRange(document, preview: Self.headingText)
            _ = try await docs.styleParagraphs(
                documentId: documentID,
                startIndex: range.start, endIndex: range.end,
                namedStyleType: "HEADING_1")
            let after = try await docs.document(id: documentID)
            guard let row = after.blockRows.first(where: { $0.preview == Self.headingText }),
                  row.kind == .heading, row.namedStyleType == "HEADING_1" else {
                throw GrahamError.invalidResponse("the heading style did not round-trip")
            }
        }

        // Lists.
        let bulleted = await actionStep(
            "bullets-create", recorder: recorder, skipReason: insertedSkip
        ) {
            let document = try await docs.document(id: documentID)
            let a = try self.requireRange(document, preview: Self.listAText)
            let b = try self.requireRange(document, preview: Self.listBText)
            _ = try await docs.createParagraphBullets(
                documentId: documentID, startIndex: a.start, endIndex: b.end,
                preset: DocsBulletPreset.bulletDiscCircleSquare.rawValue)
            let after = try await docs.document(id: documentID)
            let items = after.blockRows.filter {
                $0.preview == Self.listAText || $0.preview == Self.listBText
            }
            guard items.count == 2, items.allSatisfy({ $0.kind == .listItem }) else {
                throw GrahamError.invalidResponse("the paragraphs did not become list items")
            }
        }
        _ = await actionStep(
            "bullets-delete", recorder: recorder,
            skipReason: bulleted ? nil : "bullets-create failed"
        ) {
            let document = try await docs.document(id: documentID)
            let a = try self.requireRange(document, preview: Self.listAText)
            let b = try self.requireRange(document, preview: Self.listBText)
            _ = try await docs.deleteParagraphBullets(
                documentId: documentID, startIndex: a.start, endIndex: b.end)
            let after = try await docs.document(id: documentID)
            let items = after.blockRows.filter {
                $0.preview == Self.listAText || $0.preview == Self.listBText
            }
            guard items.allSatisfy({ $0.kind != .listItem }) else {
                throw GrahamError.invalidResponse("the list items kept their bullets")
            }
        }

        // Tables. The table is appended at the end of the body, so its start
        // index is read back from the live model rather than computed.
        let tableCreated = await actionStep("table-insert", recorder: recorder) {
            _ = try await docs.insertTable(
                documentId: documentID, rows: 3, columns: 3, endOfSegment: true)
            let after = try await docs.document(id: documentID)
            guard let table = self.firstTable(after), table.rows == 3, table.columns == 3 else {
                throw GrahamError.invalidResponse("the inserted 3x3 table was not found")
            }
        }
        let tableSkip = tableCreated ? nil : "table-insert failed"
        let addedRow = await actionStep(
            "table-add-row", recorder: recorder, skipReason: tableSkip
        ) {
            let before = try await docs.document(id: documentID)
            let start = try self.requireTableStart(before)
            let priorRows = self.firstTable(before)?.rows ?? 0
            _ = try await docs.insertTableRow(
                documentId: documentID, tableStartIndex: start, row: 1, column: 1, below: true)
            let after = try await docs.document(id: documentID)
            guard (self.firstTable(after)?.rows ?? 0) == priorRows + 1 else {
                throw GrahamError.invalidResponse("the table row count did not increase")
            }
        }
        let addedColumn = await actionStep(
            "table-add-column", recorder: recorder, skipReason: tableSkip
        ) {
            let before = try await docs.document(id: documentID)
            let start = try self.requireTableStart(before)
            let priorColumns = self.firstTable(before)?.columns ?? 0
            _ = try await docs.insertTableColumn(
                documentId: documentID, tableStartIndex: start, row: 1, column: 1, right: true)
            let after = try await docs.document(id: documentID)
            guard (self.firstTable(after)?.columns ?? 0) == priorColumns + 1 else {
                throw GrahamError.invalidResponse("the table column count did not increase")
            }
        }
        _ = await actionStep("table-style-cells", recorder: recorder, skipReason: tableSkip) {
            let start = try self.requireTableStart(try await docs.document(id: documentID))
            _ = try await docs.styleTableCells(
                documentId: documentID, tableStartIndex: start,
                row: 1, column: 1,
                backgroundColor: yellow, borderColor: black,
                borderWidth: 1, borderDash: .solid, padding: 3, contentAlignment: .middle)
        }
        _ = await actionStep("table-row-style", recorder: recorder, skipReason: tableSkip) {
            let start = try self.requireTableStart(try await docs.document(id: documentID))
            _ = try await docs.styleTableRow(
                documentId: documentID, tableStartIndex: start, rows: [1],
                minRowHeight: 24, tableHeader: true, preventOverflow: true)
        }
        _ = await actionStep("table-column-width", recorder: recorder, skipReason: tableSkip) {
            let start = try self.requireTableStart(try await docs.document(id: documentID))
            _ = try await docs.styleTableColumnWidth(
                documentId: documentID, tableStartIndex: start, columns: [1], width: 90)
        }
        let merged = await actionStep("table-merge", recorder: recorder, skipReason: tableSkip) {
            let start = try self.requireTableStart(try await docs.document(id: documentID))
            _ = try await docs.mergeTableCells(
                documentId: documentID, tableStartIndex: start,
                row: 1, column: 1, rowSpan: 2, columnSpan: 2)
        }
        _ = await actionStep(
            "table-unmerge", recorder: recorder,
            skipReason: merged ? nil : "table-merge failed"
        ) {
            let start = try self.requireTableStart(try await docs.document(id: documentID))
            _ = try await docs.unmergeTableCells(
                documentId: documentID, tableStartIndex: start,
                row: 1, column: 1, rowSpan: 2, columnSpan: 2)
        }
        _ = await actionStep("table-pin-headers", recorder: recorder, skipReason: tableSkip) {
            let start = try self.requireTableStart(try await docs.document(id: documentID))
            _ = try await docs.pinTableHeaderRows(
                documentId: documentID, tableStartIndex: start, pinnedHeaderRowsCount: 1)
        }
        _ = await actionStep(
            "table-delete-row", recorder: recorder,
            skipReason: addedRow ? nil : "table-add-row failed"
        ) {
            let before = try await docs.document(id: documentID)
            let start = try self.requireTableStart(before)
            let priorRows = self.firstTable(before)?.rows ?? 0
            _ = try await docs.deleteTableRow(
                documentId: documentID, tableStartIndex: start, row: 2, column: 1)
            let after = try await docs.document(id: documentID)
            guard (self.firstTable(after)?.rows ?? 0) == priorRows - 1 else {
                throw GrahamError.invalidResponse("the table row count did not decrease")
            }
        }
        _ = await actionStep(
            "table-delete-column", recorder: recorder,
            skipReason: addedColumn ? nil : "table-add-column failed"
        ) {
            let before = try await docs.document(id: documentID)
            let start = try self.requireTableStart(before)
            let priorColumns = self.firstTable(before)?.columns ?? 0
            _ = try await docs.deleteTableColumn(
                documentId: documentID, tableStartIndex: start, row: 1, column: 2)
            let after = try await docs.document(id: documentID)
            guard (self.firstTable(after)?.columns ?? 0) == priorColumns - 1 else {
                throw GrahamError.invalidResponse("the table column count did not decrease")
            }
        }

        // Structure and images.
        _ = await actionStep("page-break", recorder: recorder) {
            _ = try await docs.insertPageBreak(documentId: documentID, endOfSegment: true)
        }
        _ = await actionStep("section-break", recorder: recorder) {
            _ = try await docs.insertSectionBreak(
                documentId: documentID, sectionType: "CONTINUOUS", endOfSegment: true)
        }
        let imageID = await valueStep(
            "image-insert", recorder: recorder, createdIDs: { [$0] }
        ) {
            let result = try await docs.insertInlineImage(
                documentId: documentID, uri: imageURL, endOfSegment: true)
            guard let id = result.objectId, !id.isEmpty else {
                throw GrahamError.invalidResponse("insertInlineImage returned no object id")
            }
            let after = try await docs.document(id: documentID)
            guard after.imageRows.contains(where: { $0.objectId == id }) else {
                throw GrahamError.invalidResponse("the image list is missing \(id)")
            }
            return id
        }
        _ = await actionStep(
            "image-replace", recorder: recorder,
            skipReason: dependencyReason("image-insert", value: imageID)
        ) {
            _ = try await docs.replaceImage(
                documentId: documentID, imageObjectId: imageID!, uri: Self.replacementImageURL)
        }
        // deletePositionedObject: positioned objects cannot be created through
        // the Docs API, so a freshly created test document never has one. Skip
        // gracefully when none exists; delete it when a document happens to
        // carry one already.
        await positionedDeleteStep(documentID: documentID, recorder: recorder)

        // Headers, footers, footnotes.
        let headerID = await valueStep(
            "header-create", recorder: recorder, createdIDs: { [$0] }
        ) {
            let result = try await docs.createHeader(documentId: documentID)
            guard let id = result.headerId, !id.isEmpty else {
                throw GrahamError.invalidResponse("createHeader returned no header id")
            }
            return id
        }
        // A segment-aware insert (index 0 inside the header segment).
        _ = await actionStep(
            "header-insert", recorder: recorder,
            skipReason: dependencyReason("header-create", value: headerID)
        ) {
            _ = try await docs.insertText(
                documentId: documentID, text: "graham header text", index: 0, segmentId: headerID!)
            let after = try await docs.document(id: documentID)
            guard after.headers?[headerID!]?.plainText.contains("graham header text") == true else {
                throw GrahamError.invalidResponse("the header text did not round-trip")
            }
        }
        let footerID = await valueStep(
            "footer-create", recorder: recorder, createdIDs: { [$0] }
        ) {
            let result = try await docs.createFooter(documentId: documentID)
            guard let id = result.footerId, !id.isEmpty else {
                throw GrahamError.invalidResponse("createFooter returned no footer id")
            }
            return id
        }
        // An end-of-segment insert into the footer segment.
        _ = await actionStep(
            "footer-insert", recorder: recorder,
            skipReason: dependencyReason("footer-create", value: footerID)
        ) {
            _ = try await docs.insertText(
                documentId: documentID, text: "graham footer text",
                index: 0, segmentId: footerID!, endOfSegment: true)
            let after = try await docs.document(id: documentID)
            guard after.footers?[footerID!]?.plainText.contains("graham footer text") == true else {
                throw GrahamError.invalidResponse("the footer text did not round-trip")
            }
        }
        // The footnote id is recorded through createdIDs; the API has no
        // deleteFootnote op, so the footnote is left for cleanup to trash.
        _ = await valueStep(
            "footnote-create", recorder: recorder, createdIDs: { [$0] }
        ) {
            let result = try await docs.createFootnote(
                documentId: documentID, endOfBody: true, text: "graham footnote text")
            guard let id = result.footnoteId, !id.isEmpty else {
                throw GrahamError.invalidResponse("createFootnote returned no footnote id")
            }
            let after = try await docs.document(id: documentID)
            guard after.footnotes?[id]?.plainText.contains("graham footnote text") == true else {
                throw GrahamError.invalidResponse("the footnote text did not round-trip")
            }
            return id
        }
        _ = await actionStep(
            "header-delete", recorder: recorder,
            skipReason: dependencyReason("header-create", value: headerID)
        ) {
            _ = try await docs.deleteHeader(documentId: documentID, headerId: headerID!)
            let after = try await docs.document(id: documentID)
            guard after.headers?[headerID!] == nil else {
                throw GrahamError.invalidResponse("the header is still present after delete")
            }
        }
        _ = await actionStep(
            "footer-delete", recorder: recorder,
            skipReason: dependencyReason("footer-create", value: footerID)
        ) {
            _ = try await docs.deleteFooter(documentId: documentID, footerId: footerID!)
            let after = try await docs.document(id: documentID)
            guard after.footers?[footerID!] == nil else {
                throw GrahamError.invalidResponse("the footer is still present after delete")
            }
        }

        // Named ranges (the template-filling primitive).
        let namedRangeID = await valueStep(
            "range-create", recorder: recorder, skipReason: insertedSkip, createdIDs: { [$0] }
        ) {
            let document = try await docs.document(id: documentID)
            let range = try self.requireRange(document, preview: Self.styledText)
            let result = try await docs.createNamedRange(
                documentId: documentID, name: "graham-range",
                startIndex: range.start, endIndex: self.innerEnd(range))
            guard let id = result.namedRangeId, !id.isEmpty else {
                throw GrahamError.invalidResponse("createNamedRange returned no id")
            }
            return id
        }
        _ = await actionStep(
            "range-list", recorder: recorder,
            skipReason: dependencyReason("range-create", value: namedRangeID)
        ) {
            let document = try await docs.document(id: documentID)
            guard document.namedRangeRows.contains(where: { $0.namedRangeId == namedRangeID! }) else {
                throw GrahamError.invalidResponse("the named range list is missing \(namedRangeID!)")
            }
        }
        _ = await actionStep(
            "range-fill", recorder: recorder,
            skipReason: dependencyReason("range-create", value: namedRangeID)
        ) {
            // The named range covers the "graham styled" run; filling it replaces
            // that run's content, which a read-back observes.
            _ = try await docs.replaceNamedRangeContent(
                documentId: documentID, text: "graham filled", namedRangeId: namedRangeID!)
            let after = try await docs.document(id: documentID)
            guard self.blockRange(after, preview: "graham filled") != nil,
                  self.blockRange(after, preview: Self.styledText) == nil else {
                throw GrahamError.invalidResponse("the named range fill did not round-trip")
            }
        }
        _ = await actionStep(
            "range-delete", recorder: recorder,
            skipReason: dependencyReason("range-create", value: namedRangeID)
        ) {
            _ = try await docs.deleteNamedRange(documentId: documentID, namedRangeId: namedRangeID!)
            let after = try await docs.document(id: documentID)
            guard !after.namedRangeRows.contains(where: { $0.namedRangeId == namedRangeID! }) else {
                throw GrahamError.invalidResponse("the named range is still present after delete")
            }
        }

        // Document-wide style. This masks the page-oriented DocumentStyle fields
        // in one call: page size, margins, the header/footer flags, background,
        // the starting page number, custom header/footer margins, and the
        // orientation flip. The document mode is set on its own below, because
        // pageless is incompatible with an explicit page size.
        _ = await actionStep("page-setup", recorder: recorder) {
            _ = try await docs.updateDocumentStyle(
                documentId: documentID,
                pageWidth: 612, pageHeight: 792,
                marginTop: 72, marginBottom: 72, marginLeft: 72, marginRight: 72,
                useFirstPageHeaderFooter: true, useEvenPageHeaderFooter: true,
                background: white, pageNumberStart: 1,
                marginHeader: 36, marginFooter: 36, flipPageOrientation: true)
            let after = try await docs.document(id: documentID)
            guard after.documentStyle?.useFirstPageHeaderFooter == true else {
                throw GrahamError.invalidResponse("the document style did not round-trip")
            }
        }
        // Pageless mode, set alone: it is incompatible with the explicit page
        // size set above, so it must ride in its own updateDocumentStyle call.
        _ = await actionStep("page-mode-pageless", recorder: recorder) {
            _ = try await docs.updateDocumentStyle(
                documentId: documentID, documentMode: .pageless)
        }

        // WriteControl: one write that requires the document's current revision.
        _ = await actionStep("write-control", recorder: recorder) {
            let document = try await docs.document(id: documentID)
            guard let revision = document.revisionId, !revision.isEmpty else {
                throw GrahamError.invalidResponse("the document reported no revision id")
            }
            _ = try await docs.insertText(
                documentId: documentID, text: "graham revlocked\n",
                index: 0, endOfSegment: true, requiredRevisionId: revision)
            let after = try await docs.document(id: documentID)
            guard after.plainText.contains("graham revlocked") else {
                throw GrahamError.invalidResponse("the write-control insert did not round-trip")
            }
        }

        await cleanupStep(
            "trash-created-doc", fileID: createdDocID,
            recorder: recorder, prerequisite: createdDocID != nil,
            dependency: "docs-create")
        await cleanupStep(
            "trash-doc", fileID: documentID, recorder: recorder, prerequisite: true)

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

    /// The `deletePositionedObject` step. It is not a value/action step because
    /// a graceful skip (no positioned object exists) is the normal outcome, not
    /// a dependency skip. This mirrors the special-cased `group` step in
    /// ``SlidesLiveTest``.
    private func positionedDeleteStep(documentID: String, recorder: Recorder) async {
        do {
            let document = try await docs.document(id: documentID)
            if let positioned = document.imageRows.first(where: { $0.origin == .positioned }),
               let objectId = positioned.objectId {
                _ = try await docs.deletePositionedObject(
                    documentId: documentID, objectId: objectId)
                // The object was deleted, not created, so nothing is recorded as
                // a created id.
                recorder.record(name: "positioned-delete", outcome: .pass)
            } else {
                recorder.record(
                    name: "positioned-delete",
                    outcome: .skip(reason: "no positioned object exists"))
            }
        } catch {
            recorder.record(
                name: "positioned-delete", outcome: .fail(reason: Self.reason(for: error)))
        }
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

    // MARK: - Live-model locators
    //
    // The runner never hardcodes an index. It reads a paragraph or table back
    // from the live document (exactly the values `docs structure` prints) and
    // targets the next op by that current range.

    /// The zero-based UTF-16 range of the first body paragraph whose one-line
    /// preview equals `preview`, or nil if none matches. Tables are skipped so a
    /// cell's text never masquerades as a body paragraph.
    private func blockRange(_ document: Document, preview: String) -> (start: Int, end: Int)? {
        guard let row = document.blockRows.first(where: {
            $0.kind != .table && $0.preview == preview
        }), let end = row.endIndex else { return nil }
        return (row.startIndex ?? 0, end)
    }

    /// Like ``blockRange(_:preview:)`` but throws when the paragraph is absent.
    private func requireRange(
        _ document: Document, preview: String
    ) throws -> (start: Int, end: Int) {
        guard let range = blockRange(document, preview: preview) else {
            throw GrahamError.invalidResponse("could not find the paragraph \"\(preview)\"")
        }
        return range
    }

    /// A style range that excludes a paragraph's trailing newline where it can,
    /// so styling lands on the visible text.
    private func innerEnd(_ range: (start: Int, end: Int)) -> Int {
        max(range.start + 1, range.end - 1)
    }

    /// The start index of the first table block, exactly as `docs structure`
    /// reports it — the value the table ops consume.
    private func tableStart(_ document: Document) -> Int? {
        document.blockRows.first(where: { $0.kind == .table })?.startIndex
    }

    private func requireTableStart(_ document: Document) throws -> Int {
        guard let start = tableStart(document) else {
            throw GrahamError.invalidResponse("the table was not found in the document")
        }
        return start
    }

    /// The first table's decoded model, for a row/column-count read-back.
    private func firstTable(_ document: Document) -> DocTable? {
        for element in document.body?.content ?? [] where element.table != nil {
            return element.table
        }
        return nil
    }

    // MARK: - Step primitives (mirror SlidesLiveTest)

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

    private static func reason(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description.replacingOccurrences(of: "\n", with: " ")
        }
        return String(describing: error).replacingOccurrences(of: "\n", with: " ")
    }
}

private extension DocsLiveTest {
    struct FolderResult: Sendable {
        let file: DriveFile
        let created: Bool
    }

    final class Recorder: @unchecked Sendable {
        private(set) var steps: [DocsLiveTestStep] = []
        private let onStep: @Sendable (DocsLiveTestStep) -> Void

        init(onStep: @escaping @Sendable (DocsLiveTestStep) -> Void) {
            self.onStep = onStep
        }

        func record(
            name: String,
            outcome: DocsLiveTestOutcome,
            createdIDs: [String] = []
        ) {
            let step = DocsLiveTestStep(
                name: name, outcome: outcome, createdIDs: createdIDs)
            steps.append(step)
            onStep(step)
        }

        var summary: DocsLiveTestSummary {
            DocsLiveTestSummary(steps: steps)
        }
    }
}
