import Foundation
import XCTest
@testable import GrahamKit

final class DocsLiveTestTests: XCTestCase {
    func testExistingFolderIsReusedWithoutCreatingAnotherFolder() async throws {
        let fixture = DocsLiveFixture(existingFolder: true, failDocumentCreate: true)
        let runner = fixture.makeRunner(folderName: "graham test")

        let summary = await runner.run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder", "create-doc"])
        XCTAssertEqual(summary.steps.first?.outcome, .pass)
        XCTAssertEqual(summary.steps.first?.createdIDs, [])
        let folderCreates = fixture.collectionPosts.filter {
            fixture.createBody($0)?.mimeType == DriveCreateType.folder.mimeType
        }
        XCTAssertTrue(folderCreates.isEmpty)
    }

    func testMissingFolderIsCreatedAtRootAndEscapesItsNameInTheQuery() async throws {
        let fixture = DocsLiveFixture(existingFolder: false, failDocumentCreate: true)
        let folderName = "graham's \\ test"
        let runner = fixture.makeRunner(folderName: folderName)

        let summary = await runner.run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder", "create-doc"])
        XCTAssertEqual(summary.steps.first?.createdIDs, ["folder-1"])
        let request = try XCTUnwrap(fixture.driveListRequests.first)
        let q = try XCTUnwrap(URLComponents(
            url: request.url, resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "q" })?.value)
        XCTAssertTrue(q.contains("'root' in parents"))
        XCTAssertTrue(q.contains("mimeType='application/vnd.google-apps.folder'"))
        XCTAssertTrue(q.contains("name = 'graham\\'s \\\\ test'"))
        XCTAssertTrue(q.contains("trashed = false"))

        let folderRequest = try XCTUnwrap(fixture.collectionPosts.first {
            fixture.createBody($0)?.mimeType == DriveCreateType.folder.mimeType
        })
        let body = try GoogleJSON.decoder.decode(
            DriveFileCreateRequest.self, from: try XCTUnwrap(folderRequest.body))
        XCTAssertEqual(body.name, folderName)
        XCTAssertEqual(body.mimeType, DriveCreateType.folder.mimeType)
        XCTAssertEqual(body.parents, ["root"])
    }

    func testHappyPathReportsStableStepOrderAndCleansUp() async {
        let fixture = DocsLiveFixture()
        let callback = StepCapture()
        let runner = fixture.makeRunner { callback.append($0) }

        let summary = await runner.run()
        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(callback.steps, summary.steps)
        XCTAssertEqual(summary.failed, 0)
        // positioned-delete always skips: a positioned object cannot be created
        // through the Docs API, so the disposable document never carries one.
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "positioned-delete" })?.outcome,
            .skip(reason: "no positioned object exists"))
        XCTAssertEqual(summary.passed, Self.expectedStepNames.count - 1)

        // The created ids surface through their steps.
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-doc" })?.createdIDs, ["doc-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "image-insert" })?.createdIDs, ["img-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "header-create" })?.createdIDs, ["header-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "footer-create" })?.createdIDs, ["footer-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "footnote-create" })?.createdIDs, ["footnote-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "range-create" })?.createdIDs, ["range-1"])

        // The write path was exercised for real: the seed insert carried the
        // markers, the table was created, and one write carried a revision id.
        XCTAssertTrue(fixture.batchRequests.contains {
            fixture.bodyString($0).contains("graham heading")
        })
        XCTAssertTrue(fixture.batchRequests.contains {
            fixture.bodyString($0).contains(#""insertTable""#)
        })
        XCTAssertTrue(fixture.batchRequests.contains {
            let body = fixture.bodyString($0)
            return body.contains(#""writeControl""#) && body.contains(#""requiredRevisionId""#)
        })
        // The folder-parented document is trashed in cleanup.
        XCTAssertEqual(fixture.trashRequests.count, 1)
        let trashed = Set(fixture.trashRequests.map { $0.url.path })
        XCTAssertTrue(trashed.contains { $0.hasSuffix("/doc-1") })
    }

    func testSeedInsertFailureSkipsTextDependentsButContinuesAndCleansUp() async {
        let fixture = DocsLiveFixture(failSeedInsert: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "text-insert" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): seed insert rejected"))
        // Every step that depends on the seeded paragraphs is skipped in order.
        let skippedForSeed = [
            "text-replace", "text-delete", "text-style", "text-link", "paragraph-style",
            "heading", "bullets-create", "bullets-delete", "range-create", "range-list",
            "range-fill", "range-delete",
        ]
        for name in skippedForSeed {
            XCTAssertEqual(
                summary.steps.first(where: { $0.name == name })?.outcome,
                .skip(reason: name == "bullets-delete"
                    ? "bullets-create failed"
                    : (["range-list", "range-fill", "range-delete"].contains(name)
                        ? "range-create failed"
                        : "text-insert failed")),
                "unexpected outcome for \(name)")
        }
        // An independent end-of-body append still runs and passes.
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "text-append-end" })?.outcome, .pass)
        // The table chain, headers/footers, and cleanup are unaffected.
        XCTAssertEqual(summary.steps.first(where: { $0.name == "table-insert" })?.outcome, .pass)
        XCTAssertEqual(summary.steps.first(where: { $0.name == "write-control" })?.outcome, .pass)
        // The folder-parented document is still trashed.
        XCTAssertEqual(fixture.trashRequests.count, 1)
    }

    func testTableInsertFailureSkipsTableDependentsButContinuesUnrelatedSteps() async {
        let fixture = DocsLiveFixture(failTableInsert: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "table-insert" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): table rejected"))
        let tableDependents = [
            "table-add-row", "table-add-column", "table-style-cells", "table-row-style",
            "table-column-width", "table-merge", "table-pin-headers",
        ]
        for name in tableDependents {
            XCTAssertEqual(
                summary.steps.first(where: { $0.name == name })?.outcome,
                .skip(reason: "table-insert failed"), "unexpected outcome for \(name)")
        }
        // The delete steps chain off their own add step, which itself skipped.
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "table-unmerge" })?.outcome,
            .skip(reason: "table-merge failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "table-delete-row" })?.outcome,
            .skip(reason: "table-add-row failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "table-delete-column" })?.outcome,
            .skip(reason: "table-add-column failed"))
        // Text and structure steps outside the table chain still pass.
        XCTAssertEqual(summary.steps.first(where: { $0.name == "heading" })?.outcome, .pass)
        XCTAssertEqual(summary.steps.first(where: { $0.name == "image-insert" })?.outcome, .pass)
        XCTAssertEqual(summary.steps.first(where: { $0.name == "page-setup" })?.outcome, .pass)
        XCTAssertEqual(fixture.trashRequests.count, 1)
    }

    func testKeepSkipsCleanupWithoutSendingTrashRequests() async {
        let fixture = DocsLiveFixture()
        let summary = await fixture.makeRunner(keep: true).run()

        XCTAssertEqual(summary.failed, 0)
        // positioned-delete (always) plus the one kept cleanup step.
        XCTAssertEqual(summary.skipped, 2)
        XCTAssertEqual(summary.steps.last?.name, "trash-doc")
        XCTAssertEqual(summary.steps.last?.outcome, .skip(reason: "kept"))
        XCTAssertTrue(fixture.trashRequests.isEmpty)
    }

    // The next two tests prove the simulator's strictness is not a rubber stamp:
    // a stale revision and a wrong table target are rejected. That is what gives
    // the happy path teeth — it passes only because the runner reads fresh
    // revisions and current indices.

    func testSimulatorRejectsAStaleWriteControlRevision() async throws {
        let fixture = DocsLiveFixture()
        let docs = DocsClient(api: TestSupport.makeAPI(transport: fixture.transport))
        // One write advances the document to rev-1; a write that still requires
        // the stale rev-0 must be rejected.
        _ = try await docs.insertText(documentId: "doc-1", text: "seed\n", index: 1)
        do {
            _ = try await docs.insertText(
                documentId: "doc-1", text: "late\n", index: 1, requiredRevisionId: "rev-0")
            XCTFail("a stale required revision should be rejected")
        } catch {
            // Expected: the simulator rejects the mismatched revision.
        }
        // The fresh revision is accepted.
        let current = try await docs.document(id: "doc-1")
        let revision = try XCTUnwrap(current.revisionId)
        _ = try await docs.insertText(
            documentId: "doc-1", text: "ok\n", index: 1, requiredRevisionId: revision)
    }

    func testSimulatorRejectsAWrongTableStartIndex() async throws {
        let fixture = DocsLiveFixture()
        let docs = DocsClient(api: TestSupport.makeAPI(transport: fixture.transport))
        // No table exists at index 999, so a table op there must be rejected
        // rather than silently mutating some other table.
        do {
            _ = try await docs.insertTableRow(
                documentId: "doc-1", tableStartIndex: 999, row: 1, column: 1, below: true)
            XCTFail("a table op with no matching table should be rejected")
        } catch {
            // Expected: the simulator finds no table at that start index.
        }
    }

    private static let expectedStepNames = [
        "folder", "create-doc",
        "doc-fetch", "structure-read", "plaintext-read", "markdown-read", "images-read",
        "text-insert", "text-append-end", "text-replace", "text-delete",
        "text-style", "text-link", "paragraph-style", "heading",
        "bullets-create", "bullets-delete",
        "table-insert", "table-add-row", "table-add-column", "table-style-cells",
        "table-row-style", "table-column-width", "table-merge", "table-unmerge",
        "table-pin-headers", "table-delete-row", "table-delete-column",
        "page-break", "section-break", "image-insert", "image-replace", "positioned-delete",
        "header-create", "header-insert", "footer-create", "footer-insert", "footnote-create",
        "header-delete", "footer-delete",
        "range-create", "range-list", "range-fill", "range-delete",
        "page-setup", "page-mode-pageless", "write-control",
        "trash-doc",
    ]
}

private final class StepCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DocsLiveTestStep] = []

    var steps: [DocsLiveTestStep] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ step: DocsLiveTestStep) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(step)
    }
}

// MARK: - The document simulator
//
// A stateful, offline Docs "server". Every response is generated from the live
// model, which each write mutates, so the runner reads back exactly what its
// prior writes produced — and the zero-based UTF-16 indices shift after every
// edit, exactly as they do against the real API. This is what proves the
// runner's index logic offline without a network. The index layout of a table
// follows Google's documented tables guide (a 2x2 table starting at S spans
// S..S+12).

/// A paragraph in the simulated document. A reference type so a style/bullet
/// update mutates it in place wherever it is held.
private final class SimParagraph {
    var text: String
    var namedStyleType: String?
    var bulletListId: String?
    var inlineObjectId: String?

    init(
        text: String,
        namedStyleType: String? = nil,
        bulletListId: String? = nil,
        inlineObjectId: String? = nil
    ) {
        self.text = text
        self.namedStyleType = namedStyleType
        self.bulletListId = bulletListId
        self.inlineObjectId = inlineObjectId
    }
}

/// A table in the simulated document. A reference type so a row/column insert
/// or delete mutates it in place.
private final class SimTable {
    var rows: Int
    var columns: Int

    init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
    }
}

/// An embedded image. A reference type so replaceImage can update its source.
private final class SimImage {
    var sourceUri: String
    let contentUri: String

    init(sourceUri: String, contentUri: String) {
        self.sourceUri = sourceUri
        self.contentUri = contentUri
    }
}

/// A named range over a body span. A reference type so replaceNamedRangeContent
/// can update the span end after it rewrites the content.
private final class SimNamedRange {
    let id: String
    let name: String
    let start: Int
    var end: Int

    init(id: String, name: String, start: Int, end: Int) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
    }
}

/// A rejection raised by the simulator when a write targets a stale index, a
/// wrong table/cell, a missing named range, or a mismatched revision. It becomes
/// a Google 400 the runner surfaces as a failed step.
private struct SimReject: Error {
    let message: String
}

/// One structural block: a paragraph, a section break, or a table.
private enum SimBlock {
    case paragraph(SimParagraph)
    case sectionBreak
    case table(SimTable)
}

/// Which segment an edit targets.
private enum SegmentRef {
    case body
    case header(String)
    case footer(String)
    case footnote(String)
}

private final class DocsLiveFixture: @unchecked Sendable {
    let transport = StubTransport()
    let existingFolder: Bool
    let failDocumentCreate: Bool
    let failSeedInsert: Bool
    let failTableInsert: Bool

    // A new document body: the initial section break, then one empty paragraph.
    private var body: [SimBlock] = [.sectionBreak, .paragraph(SimParagraph(text: ""))]
    private var headers: [String: [SimBlock]] = [:]
    private var footers: [String: [SimBlock]] = [:]
    private var footnotes: [String: [SimBlock]] = [:]
    private var inlineObjects: [String: SimImage] = [:]
    private var namedRanges: [SimNamedRange] = []
    private var useFirstPageHeaderFooter: Bool?
    private var useEvenPageHeaderFooter: Bool?
    private var documentMode: String?

    private var headerCounter = 0
    private var footerCounter = 0
    private var footnoteCounter = 0
    private var imageCounter = 0
    private var namedRangeCounter = 0
    private var revision = 0

    init(
        existingFolder: Bool = true,
        failDocumentCreate: Bool = false,
        failSeedInsert: Bool = false,
        failTableInsert: Bool = false
    ) {
        self.existingFolder = existingFolder
        self.failDocumentCreate = failDocumentCreate
        self.failSeedInsert = failSeedInsert
        self.failTableInsert = failTableInsert
        transport.stubTokenEndpoint()
        transport.stub(matching: { _ in true }, responding: { [self] request in
            response(to: request)
        })
    }

    // MARK: Request views

    var driveListRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "GET" && $0.url.path == "/drive/v3/files"
        }
    }

    var collectionPosts: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "POST" && $0.url.path == "/drive/v3/files"
        }
    }

    var trashRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "PATCH" && $0.url.path.hasPrefix("/drive/v3/files/")
        }
    }

    var batchRequests: [HTTPRequest] {
        transport.requests.filter { $0.url.path.hasSuffix(":batchUpdate") }
    }

    func makeRunner(
        folderName: String = "graham test",
        keep: Bool = false,
        onStep: @escaping @Sendable (DocsLiveTestStep) -> Void = { _ in }
    ) -> DocsLiveTest {
        let api = TestSupport.makeAPI(transport: transport)
        return DocsLiveTest(
            drive: DriveClient(api: api),
            docs: DocsClient(api: api),
            folderName: folderName,
            keep: keep,
            label: "run-1",
            onStep: onStep
        )
    }

    func bodyString(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func createBody(_ request: HTTPRequest) -> DriveFileCreateRequest? {
        request.body.flatMap {
            try? GoogleJSON.decoder.decode(DriveFileCreateRequest.self, from: $0)
        }
    }

    // MARK: Routing

    private func response(to request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path
        if path == "/drive/v3/files", request.method == "GET" {
            let files: [[String: Any]] = existingFolder
                ? [[
                    "id": "folder-1",
                    "name": "graham test",
                    "mimeType": "application/vnd.google-apps.folder",
                    "parents": ["root"],
                ]]
                : []
            return json(["files": files])
        }
        if path == "/drive/v3/files", request.method == "POST" {
            let mime = createBody(request)?.mimeType
            if mime == DriveCreateType.folder.mimeType {
                return driveFile(
                    id: "folder-1", name: "graham test", mime: DriveCreateType.folder.mimeType)
            }
            if mime == DriveCreateType.docs.mimeType {
                if failDocumentCreate {
                    return googleError(message: "document rejected")
                }
                return driveFile(
                    id: "doc-1", name: "graham test doc run-1", mime: DriveCreateType.docs.mimeType)
            }
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "PATCH" {
            let id = path.split(separator: "/").last.map(String.init) ?? "file"
            return driveFile(id: id, name: id, mime: nil)
        }
        if path == "/v1/documents/doc-1", request.method == "GET" {
            return json(documentJSON())
        }
        if path == "/v1/documents/doc-1:batchUpdate", request.method == "POST" {
            return batchResponse(request)
        }
        return HTTPResponse(
            statusCode: 599, body: Data("unmatched \(request.method) \(request.url)".utf8))
    }

    // MARK: Batch dispatch

    private func batchResponse(_ request: HTTPRequest) -> HTTPResponse {
        guard let data = request.body,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requests = object["requests"] as? [[String: Any]],
              let first = requests.first,
              let key = first.keys.first,
              let op = first[key] as? [String: Any] else {
            return googleError(message: "malformed batch request")
        }

        do {
            // WriteControl: a batch that requires a revision applies only if the
            // document is still at that revision; a stale one is rejected, exactly
            // as the API rejects a mismatched requiredRevisionId.
            if let writeControl = object["writeControl"] as? [String: Any],
               let required = writeControl["requiredRevisionId"] as? String,
               required != "rev-\(revision)" {
                throw SimReject(
                    message: "required revision \(required) is stale (current rev-\(revision))")
            }
            let reply = try applyBatch(key: key, op: op)
            // Only a write that actually applied advances the revision.
            revision += 1
            return json(["documentId": "doc-1", "replies": [reply]])
        } catch let reject as SimReject {
            return googleError(message: reject.message)
        } catch {
            return googleError(message: "\(error)")
        }
    }

    /// Applies one batch operation, mutating state, and returns its reply — or
    /// throws ``SimReject`` when the write targets a stale index, a wrong
    /// table/cell, a missing named range, or an out-of-range span, so the runner
    /// surfaces a failed step instead of a rubber-stamped write.
    private func applyBatch(key: String, op: [String: Any]) throws -> [String: Any] {
        switch key {
        case "insertText":
            if failSeedInsert, (op["text"] as? String)?.contains("graham heading") == true {
                throw SimReject(message: "seed insert rejected")
            }
            try applyInsertText(op)
            return [:]
        case "deleteContentRange":
            try applyDeleteContentRange(op)
            return [:]
        case "replaceAllText":
            return ["replaceAllText": ["occurrencesChanged": applyReplaceAllText(op)]]
        case "updateTextStyle":
            try requireRangeOp(op)
            return [:]
        case "updateParagraphStyle":
            try requireRangeOp(op)
            applyParagraphStyle(op)
            return [:]
        case "createParagraphBullets":
            try requireRangeOp(op)
            applyBullets(op, listId: "list-1")
            return [:]
        case "deleteParagraphBullets":
            try requireRangeOp(op)
            applyBullets(op, listId: nil)
            return [:]
        case "insertTable":
            if failTableInsert { throw SimReject(message: "table rejected") }
            let rows = op["rows"] as? Int ?? 1
            let columns = op["columns"] as? Int ?? 1
            appendToBody(.table(SimTable(rows: rows, columns: columns)))
            return [:]
        case "insertTableRow":
            let (table, _, _) = try locateCell(op["tableCellLocation"])
            table.rows += 1
            return [:]
        case "insertTableColumn":
            let (table, _, _) = try locateCell(op["tableCellLocation"])
            table.columns += 1
            return [:]
        case "deleteTableRow":
            let (table, _, _) = try locateCell(op["tableCellLocation"])
            guard table.rows > 1 else { throw SimReject(message: "cannot delete the last row") }
            table.rows -= 1
            return [:]
        case "deleteTableColumn":
            let (table, _, _) = try locateCell(op["tableCellLocation"])
            guard table.columns > 1 else {
                throw SimReject(message: "cannot delete the last column")
            }
            table.columns -= 1
            return [:]
        case "mergeTableCells":
            try requireTableRange(op["tableRange"])
            return [:]
        case "unmergeTableCells":
            try requireTableRange(op["tableRange"])
            return [:]
        case "pinTableHeaderRows":
            let table = try locateTableStart(op["tableStartLocation"])
            let count = op["pinnedHeaderRowsCount"] as? Int ?? 0
            guard count >= 0, count <= table.rows else {
                throw SimReject(message: "pinned header rows \(count) exceeds the table")
            }
            return [:]
        case "updateTableCellStyle":
            if let range = op["tableRange"] {
                try requireTableRange(range)
            } else {
                _ = try locateTableStart(op["tableStartLocation"])
            }
            return [:]
        case "updateTableRowStyle":
            let table = try locateTableStart(op["tableStartLocation"])
            try requireIndices(op["rowIndices"], within: table.rows, label: "row")
            return [:]
        case "updateTableColumnProperties":
            let table = try locateTableStart(op["tableStartLocation"])
            try requireIndices(op["columnIndices"], within: table.columns, label: "column")
            return [:]
        case "insertPageBreak":
            appendToBody(.paragraph(SimParagraph(text: "")))
            return [:]
        case "insertSectionBreak":
            appendToBody(.sectionBreak)
            return [:]
        case "insertInlineImage":
            imageCounter += 1
            let id = "img-\(imageCounter)"
            inlineObjects[id] = SimImage(
                sourceUri: op["uri"] as? String ?? "",
                contentUri: "https://usercontent.example/doc-image-\(imageCounter)")
            appendToBody(.paragraph(SimParagraph(text: "", inlineObjectId: id)))
            return ["insertInlineImage": ["objectId": id]]
        case "replaceImage":
            guard let id = op["imageObjectId"] as? String, let image = inlineObjects[id] else {
                throw SimReject(message: "unknown image object id to replace")
            }
            image.sourceUri = op["uri"] as? String ?? image.sourceUri
            return [:]
        case "deletePositionedObject":
            return [:]
        case "createHeader":
            headerCounter += 1
            let id = "header-\(headerCounter)"
            headers[id] = [.paragraph(SimParagraph(text: ""))]
            return ["createHeader": ["headerId": id]]
        case "createFooter":
            footerCounter += 1
            let id = "footer-\(footerCounter)"
            footers[id] = [.paragraph(SimParagraph(text: ""))]
            return ["createFooter": ["footerId": id]]
        case "deleteHeader":
            guard let id = op["headerId"] as? String, headers[id] != nil else {
                throw SimReject(message: "unknown header id to delete")
            }
            headers[id] = nil
            return [:]
        case "deleteFooter":
            guard let id = op["footerId"] as? String, footers[id] != nil else {
                throw SimReject(message: "unknown footer id to delete")
            }
            footers[id] = nil
            return [:]
        case "createFootnote":
            footnoteCounter += 1
            let id = "footnote-\(footnoteCounter)"
            // A new footnote segment starts with an auto-inserted space + newline.
            footnotes[id] = [.paragraph(SimParagraph(text: " "))]
            return ["createFootnote": ["footnoteId": id]]
        case "createNamedRange":
            let range = op["range"] as? [String: Any] ?? [:]
            let start = range["startIndex"] as? Int ?? 0
            let end = range["endIndex"] as? Int ?? 0
            try requireRange(start: start, end: end, segmentId: range["segmentId"] as? String)
            namedRangeCounter += 1
            let id = "range-\(namedRangeCounter)"
            namedRanges.append(SimNamedRange(
                id: id, name: op["name"] as? String ?? "", start: start, end: end))
            return ["createNamedRange": ["namedRangeId": id]]
        case "deleteNamedRange":
            if let id = op["namedRangeId"] as? String {
                guard namedRanges.contains(where: { $0.id == id }) else {
                    throw SimReject(message: "unknown named range id to delete")
                }
                namedRanges.removeAll { $0.id == id }
            } else if let name = op["name"] as? String {
                guard namedRanges.contains(where: { $0.name == name }) else {
                    throw SimReject(message: "unknown named range name to delete")
                }
                namedRanges.removeAll { $0.name == name }
            } else {
                throw SimReject(message: "deleteNamedRange without a selector")
            }
            return [:]
        case "replaceNamedRangeContent":
            try applyReplaceNamedRangeContent(op)
            return [:]
        case "updateDocumentStyle":
            let style = op["documentStyle"] as? [String: Any] ?? [:]
            if let value = style["useFirstPageHeaderFooter"] as? Bool {
                useFirstPageHeaderFooter = value
            }
            if let value = style["useEvenPageHeaderFooter"] as? Bool {
                useEvenPageHeaderFooter = value
            }
            if let mode = (style["documentFormat"] as? [String: Any])?["documentMode"] as? String {
                documentMode = mode
            }
            return [:]
        default:
            return [:]
        }
    }

    // MARK: Validation

    /// The total UTF-16 length of a block list (the end cursor after serializing).
    private func totalLength(_ blocks: [SimBlock]) -> Int {
        var cursor = 0
        for block in blocks { cursor += blockLength(block, start: cursor) }
        return cursor
    }

    /// Rejects a body/segment span that falls outside its segment. The body's
    /// first editable index is 1 (index 0 is the initial section break); a named
    /// segment starts at 0.
    private func requireRange(start: Int, end: Int, segmentId: String?) throws {
        let ref = segmentRef(segmentId)
        let minStart: Int
        if case .body = ref { minStart = 1 } else { minStart = 0 }
        guard start >= minStart, end > start, end <= totalLength(list(for: ref)) else {
            throw SimReject(message: "range [\(start), \(end)) is outside the document")
        }
    }

    /// Rejects a range-based op (text style, paragraph style, bullets) whose
    /// range is stale or outside its segment.
    private func requireRangeOp(_ op: [String: Any]) throws {
        let range = op["range"] as? [String: Any] ?? [:]
        try requireRange(
            start: range["startIndex"] as? Int ?? 0,
            end: range["endIndex"] as? Int ?? 0,
            segmentId: range["segmentId"] as? String)
    }

    /// Locates the table whose serialized start index equals `startIndex`.
    private func table(atStart startIndex: Int) -> SimTable? {
        var cursor = 0
        for block in body {
            let length = blockLength(block, start: cursor)
            if case .table(let table) = block, cursor == startIndex { return table }
            cursor += length
        }
        return nil
    }

    /// Resolves a `tableCellLocation`: rejects a wrong table start or a cell
    /// outside the located table.
    private func locateCell(_ any: Any?) throws -> (table: SimTable, row: Int, column: Int) {
        guard let cell = any as? [String: Any],
              let start = (cell["tableStartLocation"] as? [String: Any])?["index"] as? Int else {
            throw SimReject(message: "missing table cell location")
        }
        guard let table = table(atStart: start) else {
            throw SimReject(message: "no table starts at index \(start)")
        }
        let row = cell["rowIndex"] as? Int ?? 0
        let column = cell["columnIndex"] as? Int ?? 0
        guard row >= 0, row < table.rows else {
            throw SimReject(message: "row index \(row) is out of range")
        }
        guard column >= 0, column < table.columns else {
            throw SimReject(message: "column index \(column) is out of range")
        }
        return (table, row, column)
    }

    /// Resolves a `tableStartLocation`: rejects a wrong table start.
    private func locateTableStart(_ any: Any?) throws -> SimTable {
        guard let location = any as? [String: Any], let start = location["index"] as? Int else {
            throw SimReject(message: "missing table start location")
        }
        guard let table = table(atStart: start) else {
            throw SimReject(message: "no table starts at index \(start)")
        }
        return table
    }

    /// Resolves a `tableRange`: rejects a wrong cell or a span past the table.
    private func requireTableRange(_ any: Any?) throws {
        guard let range = any as? [String: Any] else {
            throw SimReject(message: "missing table range")
        }
        let (table, row, column) = try locateCell(range["tableCellLocation"])
        let rowSpan = range["rowSpan"] as? Int ?? 1
        let columnSpan = range["columnSpan"] as? Int ?? 1
        guard rowSpan >= 1, row + rowSpan <= table.rows else {
            throw SimReject(message: "row span \(rowSpan) at \(row) exceeds the table")
        }
        guard columnSpan >= 1, column + columnSpan <= table.columns else {
            throw SimReject(message: "column span \(columnSpan) at \(column) exceeds the table")
        }
    }

    /// Rejects any row/column index outside a count. An omitted list means every
    /// row or column, which is always valid.
    private func requireIndices(_ any: Any?, within count: Int, label: String) throws {
        guard let indices = any as? [Int] else { return }
        for index in indices where index < 0 || index >= count {
            throw SimReject(message: "\(label) index \(index) is out of range")
        }
    }

    // MARK: Mutations

    private func applyInsertText(_ op: [String: Any]) throws {
        let text = op["text"] as? String ?? ""
        var segmentId: String?
        var index: Int?
        var endOfSegment = false
        if let location = op["location"] as? [String: Any] {
            index = location["index"] as? Int
            segmentId = location["segmentId"] as? String
        } else if let end = op["endOfSegmentLocation"] as? [String: Any] {
            endOfSegment = true
            segmentId = end["segmentId"] as? String
        }
        let ref = segmentRef(segmentId)
        if !endOfSegment {
            guard let index else { throw SimReject(message: "insertText without a location") }
            guard paragraphOffset(in: list(for: ref), at: index) != nil else {
                throw SimReject(message: "insert index \(index) is outside the document")
            }
        }
        mutateList(for: ref) { blocks in
            insert(text: text, index: index, endOfSegment: endOfSegment, into: &blocks)
        }
    }

    private func applyDeleteContentRange(_ op: [String: Any]) throws {
        let range = op["range"] as? [String: Any] ?? [:]
        let start = range["startIndex"] as? Int ?? 0
        let end = range["endIndex"] as? Int ?? 0
        let segmentId = range["segmentId"] as? String
        try requireRange(start: start, end: end, segmentId: segmentId)
        mutateList(for: segmentRef(segmentId)) { blocks in
            delete(start: start, end: end, from: &blocks)
        }
    }

    /// Replaces a named range's content: rejects an unknown selector, rewrites
    /// the span's text in the body (delete then insert at the span start), and
    /// keeps the stored span consistent with the new length so a read observes it.
    private func applyReplaceNamedRangeContent(_ op: [String: Any]) throws {
        let target: SimNamedRange?
        if let id = op["namedRangeId"] as? String {
            target = namedRanges.first { $0.id == id }
        } else if let name = op["namedRangeName"] as? String {
            target = namedRanges.first { $0.name == name }
        } else {
            target = nil
        }
        guard let range = target else {
            throw SimReject(message: "unknown named range to fill")
        }
        let text = op["text"] as? String ?? ""
        mutateList(for: .body) { blocks in
            delete(start: range.start, end: range.end, from: &blocks)
            insert(text: text, index: range.start, endOfSegment: false, into: &blocks)
        }
        range.end = range.start + text.utf16.count
    }

    private func applyReplaceAllText(_ op: [String: Any]) -> Int {
        let find = (op["containsText"] as? [String: Any])?["text"] as? String ?? ""
        let replacement = op["replaceText"] as? String ?? ""
        guard !find.isEmpty else { return 0 }
        var count = 0
        for block in body {
            if case .paragraph(let paragraph) = block, paragraph.text.contains(find) {
                count += paragraph.text.components(separatedBy: find).count - 1
                paragraph.text = paragraph.text.replacingOccurrences(of: find, with: replacement)
            }
        }
        return count
    }

    private func applyParagraphStyle(_ op: [String: Any]) {
        guard let named = (op["paragraphStyle"] as? [String: Any])?["namedStyleType"] as? String
        else { return }
        forEachParagraph(op) { $0.namedStyleType = named }
    }

    private func applyBullets(_ op: [String: Any], listId: String?) {
        forEachParagraph(op) { $0.bulletListId = listId }
    }

    /// Applies `apply` to every paragraph the request's range overlaps.
    private func forEachParagraph(_ op: [String: Any], _ apply: (SimParagraph) -> Void) {
        let range = op["range"] as? [String: Any] ?? [:]
        let start = range["startIndex"] as? Int ?? 0
        let end = range["endIndex"] as? Int ?? 0
        let segmentId = range["segmentId"] as? String
        let blocks = list(for: segmentRef(segmentId))
        var cursor = 0
        for block in blocks {
            let length = blockLength(block, start: cursor)
            if case .paragraph(let paragraph) = block, cursor < end, cursor + length > start {
                apply(paragraph)
            }
            cursor += length
        }
    }

    // MARK: Text-buffer helpers

    /// Inserts `text` into a paragraph list, either at a flat `index` or at the
    /// end of the segment. Newlines in `text` split into new paragraphs.
    private func insert(text: String, index: Int?, endOfSegment: Bool, into blocks: inout [SimBlock]) {
        let target: (blockIndex: Int, offset: Int)?
        if endOfSegment {
            // The end of the segment is the end of its last paragraph's text.
            if let last = blocks.lastIndex(where: { if case .paragraph = $0 { return true }; return false }),
               case .paragraph(let paragraph) = blocks[last] {
                target = (last, paragraph.text.utf16.count)
            } else {
                target = nil
            }
        } else if let index {
            target = paragraphOffset(in: blocks, at: index)
        } else {
            target = nil
        }
        guard let target, case .paragraph(let paragraph) = blocks[target.blockIndex] else { return }
        let replacements = splice(paragraph, at: target.offset, insert: text)
        blocks.replaceSubrange(
            target.blockIndex...target.blockIndex, with: replacements.map { SimBlock.paragraph($0) })
    }

    /// Deletes `[start, end)` from a paragraph list. The runner deletes whole
    /// paragraphs, but a within-paragraph delete is handled too.
    private func delete(start: Int, end: Int, from blocks: inout [SimBlock]) {
        var cursor = 0
        for (blockIndex, block) in blocks.enumerated() {
            let length = blockLength(block, start: cursor)
            let blockStart = cursor
            let blockEnd = cursor + length
            if case .paragraph(let paragraph) = block, start >= blockStart, end <= blockEnd {
                if start == blockStart, end == blockEnd {
                    blocks.remove(at: blockIndex)
                } else {
                    let full = Array((paragraph.text + "\n").utf16)
                    let head = String(utf16CodeUnits: Array(full[0..<(start - blockStart)]),
                                      count: start - blockStart)
                    let tail = String(utf16CodeUnits: Array(full[(end - blockStart)...]),
                                      count: full.count - (end - blockStart))
                    paragraph.text = (head + tail).replacingOccurrences(of: "\n", with: "")
                }
                return
            }
            cursor = blockEnd
        }
    }

    /// Splices `insertText` into `paragraph` at a UTF-16 `offset` within its
    /// visible text, splitting on newlines into fresh paragraphs.
    private func splice(_ paragraph: SimParagraph, at offset: Int, insert insertText: String) -> [SimParagraph] {
        let full = Array((paragraph.text + "\n").utf16)
        let clamped = min(max(offset, 0), full.count)
        let head = String(utf16CodeUnits: Array(full[0..<clamped]), count: clamped)
        let tail = String(utf16CodeUnits: Array(full[clamped...]), count: full.count - clamped)
        var combined = head + insertText + tail
        // The combined text ends with the paragraph's terminating newline; drop
        // that terminator so each remaining component is one paragraph's text.
        if combined.hasSuffix("\n") { combined.removeLast() }
        return combined.components(separatedBy: "\n").map { SimParagraph(text: $0) }
    }

    /// Maps a flat, zero-based UTF-16 `index` to the paragraph block that holds
    /// it and the offset within that paragraph's visible text.
    private func paragraphOffset(in blocks: [SimBlock], at index: Int) -> (blockIndex: Int, offset: Int)? {
        var cursor = 0
        for (blockIndex, block) in blocks.enumerated() {
            let length = blockLength(block, start: cursor)
            if case .paragraph = block, index >= cursor, index < cursor + length {
                return (blockIndex, index - cursor)
            }
            cursor += length
        }
        return nil
    }

    /// Inserts `block` at the end of the body, before the trailing empty
    /// paragraph the body always keeps (a real body never ends with a table).
    private func appendToBody(_ block: SimBlock) {
        if case .paragraph = body.last {
            body.insert(block, at: body.count - 1)
        } else {
            body.append(block)
            body.append(.paragraph(SimParagraph(text: "")))
        }
    }

    private func segmentRef(_ segmentId: String?) -> SegmentRef {
        guard let id = segmentId, !id.isEmpty else { return .body }
        if headers[id] != nil { return .header(id) }
        if footers[id] != nil { return .footer(id) }
        if footnotes[id] != nil { return .footnote(id) }
        return .body
    }

    private func list(for ref: SegmentRef) -> [SimBlock] {
        switch ref {
        case .body: return body
        case .header(let id): return headers[id] ?? []
        case .footer(let id): return footers[id] ?? []
        case .footnote(let id): return footnotes[id] ?? []
        }
    }

    private func mutateList(for ref: SegmentRef, _ apply: (inout [SimBlock]) -> Void) {
        switch ref {
        case .body:
            apply(&body)
        case .header(let id):
            var blocks = headers[id] ?? []
            apply(&blocks)
            headers[id] = blocks
        case .footer(let id):
            var blocks = footers[id] ?? []
            apply(&blocks)
            footers[id] = blocks
        case .footnote(let id):
            var blocks = footnotes[id] ?? []
            apply(&blocks)
            footnotes[id] = blocks
        }
    }

    // MARK: Serialization

    /// The UTF-16 length a block occupies, given its start index.
    private func blockLength(_ block: SimBlock, start: Int) -> Int {
        switch block {
        case .sectionBreak: return 1
        case .paragraph(let paragraph):
            // An image paragraph is the object element (1) plus the newline (1).
            return paragraph.inlineObjectId != nil ? 2 : paragraph.text.utf16.count + 1
        case .table(let table):
            return tableElement(table, start: start).length
        }
    }

    private func serializeBlocks(_ blocks: [SimBlock], from startCursor: Int) -> [[String: Any]] {
        var cursor = startCursor
        var elements: [[String: Any]] = []
        for block in blocks {
            switch block {
            case .sectionBreak:
                var element: [String: Any] = ["endIndex": cursor + 1, "sectionBreak": [:]]
                if cursor > 0 { element["startIndex"] = cursor }
                elements.append(element)
                cursor += 1
            case .paragraph(let paragraph):
                let built = paragraphElement(paragraph, start: cursor)
                elements.append(built.element)
                cursor += built.length
            case .table(let table):
                let built = tableElement(table, start: cursor)
                elements.append(built.element)
                cursor += built.length
            }
        }
        return elements
    }

    private func paragraphElement(_ paragraph: SimParagraph, start: Int) -> (element: [String: Any], length: Int) {
        var inner: [[String: Any]] = []
        let length: Int
        if let objectId = paragraph.inlineObjectId {
            inner.append([
                "startIndex": start, "endIndex": start + 1,
                "inlineObjectElement": ["inlineObjectId": objectId, "textStyle": [:]],
            ])
            inner.append([
                "startIndex": start + 1, "endIndex": start + 2,
                "textRun": ["content": "\n", "textStyle": [:]],
            ])
            length = 2
        } else {
            let full = paragraph.text + "\n"
            length = full.utf16.count
            inner.append([
                "startIndex": start, "endIndex": start + length,
                "textRun": ["content": full, "textStyle": [:]],
            ])
        }
        var paragraphObject: [String: Any] = ["elements": inner]
        if let named = paragraph.namedStyleType {
            paragraphObject["paragraphStyle"] = ["namedStyleType": named]
        }
        if let listId = paragraph.bulletListId {
            paragraphObject["bullet"] = ["listId": listId, "nestingLevel": 0]
        }
        var element: [String: Any] = ["endIndex": start + length, "paragraph": paragraphObject]
        if start > 0 { element["startIndex"] = start }
        return (element, length)
    }

    /// Builds a table element following Google's documented index layout: a table
    /// starting at S with R rows and C empty cells spans S..(S + 2 + R*(1 + C*2)).
    private func tableElement(_ table: SimTable, start: Int) -> (element: [String: Any], length: Int) {
        var cursor = start + 1
        var rowElements: [[String: Any]] = []
        for _ in 0..<max(table.rows, 0) {
            let rowStart = cursor
            var cellStart = rowStart + 1
            var cellElements: [[String: Any]] = []
            for _ in 0..<max(table.columns, 0) {
                let paragraphStart = cellStart + 1
                let paragraphEnd = paragraphStart + 1  // an empty cell holds one "\n"
                cellElements.append([
                    "startIndex": cellStart, "endIndex": paragraphEnd,
                    "content": [[
                        "startIndex": paragraphStart, "endIndex": paragraphEnd,
                        "paragraph": ["elements": [[
                            "startIndex": paragraphStart, "endIndex": paragraphEnd,
                            "textRun": ["content": "\n", "textStyle": [:]],
                        ]]],
                    ]],
                ])
                cellStart = paragraphEnd
            }
            rowElements.append([
                "startIndex": rowStart, "endIndex": cellStart, "tableCells": cellElements,
            ])
            cursor = cellStart
        }
        let tableEnd = cursor + 1
        var element: [String: Any] = [
            "endIndex": tableEnd,
            "table": ["rows": table.rows, "columns": table.columns, "tableRows": rowElements],
        ]
        if start > 0 { element["startIndex"] = start }
        return (element, tableEnd - start)
    }

    private func documentJSON() -> [String: Any] {
        var document: [String: Any] = [
            "documentId": "doc-1",
            "title": "graham test doc run-1",
            "revisionId": "rev-\(revision)",
            "body": ["content": serializeBlocks(body, from: 0)],
        ]
        if !headers.isEmpty {
            var map: [String: Any] = [:]
            for (id, content) in headers {
                map[id] = ["headerId": id, "content": serializeBlocks(content, from: 0)]
            }
            document["headers"] = map
        }
        if !footers.isEmpty {
            var map: [String: Any] = [:]
            for (id, content) in footers {
                map[id] = ["footerId": id, "content": serializeBlocks(content, from: 0)]
            }
            document["footers"] = map
        }
        if !footnotes.isEmpty {
            var map: [String: Any] = [:]
            for (id, content) in footnotes {
                map[id] = ["footnoteId": id, "content": serializeBlocks(content, from: 0)]
            }
            document["footnotes"] = map
        }
        if !inlineObjects.isEmpty {
            var map: [String: Any] = [:]
            for (id, image) in inlineObjects {
                map[id] = [
                    "objectId": id,
                    "inlineObjectProperties": [
                        "embeddedObject": [
                            "imageProperties": [
                                "sourceUri": image.sourceUri, "contentUri": image.contentUri,
                            ],
                            "size": [
                                "width": ["magnitude": 120, "unit": "PT"],
                                "height": ["magnitude": 80, "unit": "PT"],
                            ],
                        ],
                    ],
                ]
            }
            document["inlineObjects"] = map
        }
        if !namedRanges.isEmpty {
            var byName: [String: [[String: Any]]] = [:]
            for range in namedRanges {
                byName[range.name, default: []].append([
                    "namedRangeId": range.id, "name": range.name,
                    "ranges": [["startIndex": range.start, "endIndex": range.end]],
                ])
            }
            var map: [String: Any] = [:]
            for (name, entries) in byName {
                map[name] = ["name": name, "namedRanges": entries]
            }
            document["namedRanges"] = map
        }
        var style: [String: Any] = [:]
        if let value = useFirstPageHeaderFooter { style["useFirstPageHeaderFooter"] = value }
        if let value = useEvenPageHeaderFooter { style["useEvenPageHeaderFooter"] = value }
        if !style.isEmpty { document["documentStyle"] = style }
        return document
    }

    // MARK: Response builders

    private func driveFile(id: String, name: String, mime: String?) -> HTTPResponse {
        var value: [String: Any] = ["id": id, "name": name]
        if let mime { value["mimeType"] = mime }
        return json(value)
    }

    private func googleError(message: String) -> HTTPResponse {
        json([
            "error": ["code": 400, "message": message, "status": "INVALID_ARGUMENT"],
        ], status: 400)
    }

    private func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return HTTPResponse(statusCode: status, body: data)
    }
}
