import Foundation
import XCTest
@testable import GrahamKit

final class SlidesLiveTestTests: XCTestCase {
    func testExistingFolderIsReusedWithoutCreatingAnotherFolder() async throws {
        let fixture = LiveTestFixture(existingFolder: true, failPresentationCreate: true)
        let runner = fixture.makeRunner(folderName: "graham test")

        let summary = await runner.run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder", "create-presentation"])
        XCTAssertEqual(summary.steps.first?.outcome, .pass)
        XCTAssertEqual(summary.steps.first?.createdIDs, [])
        let folderCreates = fixture.collectionPosts.filter {
            fixture.createBody($0)?.mimeType == DriveCreateType.folder.mimeType
        }
        XCTAssertTrue(folderCreates.isEmpty)
    }

    func testMissingFolderIsCreatedAtRootAndEscapesItsNameInTheQuery() async throws {
        let fixture = LiveTestFixture(existingFolder: false, failPresentationCreate: true)
        let folderName = "graham's \\ test"
        let runner = fixture.makeRunner(folderName: folderName)

        let summary = await runner.run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder", "create-presentation"])
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
        let fixture = LiveTestFixture()
        let callback = StepCapture()
        let runner = fixture.makeRunner { callback.append($0) }

        let summary = await runner.run()
        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(callback.steps, summary.steps)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.passed, Self.expectedStepNames.count)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "chart-sheet-add" })?.createdIDs,
            ["314"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-chart" })?.createdIDs,
            ["chart-1"])
        XCTAssertEqual(fixture.sheetsValueRequests.count, 1)
        XCTAssertTrue(fixture.sheetsValueRequests.allSatisfy {
            fixture.bodyString($0).contains(#"["Label","Value"]"#)
        })
        XCTAssertTrue(fixture.slidesBatchRequests.contains {
            let body = fixture.bodyString($0)
            return body.contains(#""createSheetsChart""#)
                && body.contains(#""linkingMode":"LINKED""#)
        })
        XCTAssertEqual(fixture.trashRequests.count, 2)
        XCTAssertEqual(fixture.deleteRequests.count, 1)
        XCTAssertTrue(fixture.copyRequests.allSatisfy {
            fixture.bodyString($0).contains(#""parents":["folder-1"]"#)
        })
    }

    func testMidRunFailureSkipsDependentsContinuesAndStillCleansUp() async {
        let fixture = LiveTestFixture(failImageCreate: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 3)
        XCTAssertEqual(summary.steps.first(where: { $0.name == "create-image" })?.outcome,
                       .fail(reason: "Google API error 400 (INVALID_ARGUMENT): image rejected"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "images-list" })?.outcome,
                       .skip(reason: "create-image failed"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "style-image" })?.outcome,
                       .skip(reason: "create-image failed"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "style-line" })?.outcome, .pass)
        XCTAssertEqual(fixture.trashRequests.count, 2)
    }

    func testChartAddFailureSkipsChartDependentsButContinuesUnrelatedSteps() async {
        let fixture = LiveTestFixture(failChartAdd: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 3)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "chart-sheet-add" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): chart rejected"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-chart" })?.outcome,
            .skip(reason: "chart-sheet-add failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "chart-refresh" })?.outcome,
            .skip(reason: "create-chart failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "chart-verify" })?.outcome,
            .skip(reason: "create-chart failed"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "drive-copy" })?.outcome, .pass)
        XCTAssertEqual(fixture.trashRequests.count, 2)
    }

    func testKeepSkipsCleanupWithoutSendingTrashRequests() async {
        let fixture = LiveTestFixture()
        let summary = await fixture.makeRunner(keep: true).run()

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 2)
        let cleanup = summary.steps.suffix(2)
        XCTAssertEqual(cleanup.map(\.name), [
            "drive-trash-presentation", "drive-trash-chart-sheet",
        ])
        XCTAssertTrue(cleanup.allSatisfy { $0.outcome == .skip(reason: "kept") })
        XCTAssertTrue(fixture.trashRequests.isEmpty)
        // The copy/delete exercise is part of the test surface, not cleanup.
        XCTAssertEqual(fixture.deleteRequests.count, 1)
    }

    private static let expectedStepNames = [
        "folder", "create-presentation",
        "slides-add", "slides-add-at-layout", "layouts-read", "slides-add-layout-id",
        "slides-move", "slides-delete",
        "create-textbox", "create-image", "create-video", "create-line", "create-table",
        "elements-list", "images-list",
        "element-move", "element-scale", "element-rotate", "element-transform",
        "element-reorder", "group", "ungroup",
        "style-shape", "style-image", "style-line", "style-video",
        "table-insert-rows", "table-insert-columns", "table-merge", "table-unmerge",
        "table-style-cells", "table-row-height", "table-column-width", "table-borders",
        "table-delete-row", "table-delete-column",
        "text-insert", "text-style", "text-link", "text-paragraph", "text-bullets",
        "text-unbullet", "text-delete", "text-insert-cell",
        "alt-text-set", "alt-text-verify", "alt-text-clear",
        "notes-set", "notes-verify", "notes-clear", "element-delete",
        "chart-sheet-create", "chart-sheet-values", "chart-sheet-add",
        "create-chart", "chart-refresh", "chart-verify",
        "drive-copy", "drive-delete-copy",
        "drive-trash-presentation", "drive-trash-chart-sheet",
    ]
}

private final class StepCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SlidesLiveTestStep] = []

    var steps: [SlidesLiveTestStep] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ step: SlidesLiveTestStep) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(step)
    }
}

/// A reusable live API script. Every response is generated from the request,
/// so the test exercises the real client URL/body encoding without a network.
private final class LiveTestFixture: @unchecked Sendable {
    let transport = StubTransport()
    let existingFolder: Bool
    let failPresentationCreate: Bool
    let failImageCreate: Bool
    let failChartAdd: Bool

    private var slideDeleted = false
    private var lineDeleted = false
    private var altTitle: String?
    private var altDescription: String?
    private var notes = ""
    private var chartCreated = false

    init(
        existingFolder: Bool = true,
        failPresentationCreate: Bool = false,
        failImageCreate: Bool = false,
        failChartAdd: Bool = false
    ) {
        self.existingFolder = existingFolder
        self.failPresentationCreate = failPresentationCreate
        self.failImageCreate = failImageCreate
        self.failChartAdd = failChartAdd
        transport.stubTokenEndpoint()
        transport.stub(matching: { _ in true }, responding: { [self] request in
            response(to: request)
        })
    }

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

    var deleteRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "DELETE" && $0.url.path.hasPrefix("/drive/v3/files/")
        }
    }

    var copyRequests: [HTTPRequest] {
        transport.requests.filter { $0.url.path.hasSuffix("/copy") }
    }

    var sheetsValueRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "PUT" && $0.url.path.contains("/values/")
        }
    }

    var slidesBatchRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "POST" && $0.url.path.hasSuffix(":batchUpdate")
                && $0.url.host == "slides.googleapis.com"
        }
    }

    func makeRunner(
        folderName: String = "graham test",
        keep: Bool = false,
        onStep: @escaping @Sendable (SlidesLiveTestStep) -> Void = { _ in }
    ) -> SlidesLiveTest {
        let api = TestSupport.makeAPI(transport: transport)
        return SlidesLiveTest(
            drive: DriveClient(api: api),
            slides: SlidesClient(api: api),
            sheets: SheetsClient(api: api),
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
                return driveFile(id: "folder-1", name: "graham test", mime: DriveCreateType.folder.mimeType)
            }
            if mime == DriveCreateType.slides.mimeType {
                if failPresentationCreate {
                    return googleError(message: "deck rejected")
                }
                return driveFile(id: "deck-1", name: "graham test run-1", mime: DriveCreateType.slides.mimeType)
            }
            if mime == DriveCreateType.sheets.mimeType {
                return driveFile(id: "sheet-1", name: "sheet", mime: DriveCreateType.sheets.mimeType)
            }
        }
        if path.hasSuffix("/copy"), request.method == "POST" {
            return driveFile(id: "copy-1", name: "copy", mime: DriveCreateType.slides.mimeType)
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "PATCH" {
            let id = path.split(separator: "/").last.map(String.init) ?? "file"
            return driveFile(id: id, name: id, mime: nil)
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "DELETE" {
            return HTTPResponse(statusCode: 204, body: Data())
        }
        if path == "/v1/presentations/deck-1", request.method == "GET" {
            return presentationResponse()
        }
        if path == "/v1/presentations/deck-1:batchUpdate", request.method == "POST" {
            return batchResponse(request)
        }
        if path.hasPrefix("/v4/spreadsheets/sheet-1/values/"), request.method == "PUT" {
            return json([
                "updatedRange": "A1:B4",
                "updatedRows": 4,
                "updatedColumns": 2,
                "updatedCells": 8,
            ])
        }
        if path == "/v4/spreadsheets/sheet-1", request.method == "GET" {
            return json([
                "spreadsheetId": "sheet-1",
                "properties": ["title": "sheet"],
                "sheets": [["properties": ["sheetId": 0, "title": "Sheet1"]]],
            ])
        }
        if path == "/v4/spreadsheets/sheet-1:batchUpdate", request.method == "POST" {
            if failChartAdd {
                return googleError(message: "chart rejected")
            }
            return json([
                "spreadsheetId": "sheet-1",
                "replies": [["addChart": ["chart": ["chartId": 314]]]],
            ])
        }
        return HTTPResponse(statusCode: 599, body: Data("unmatched \(request.method) \(request.url)".utf8))
    }

    private func batchResponse(_ request: HTTPRequest) -> HTTPResponse {
        let body = bodyString(request)
        if failImageCreate, body.contains("\"createImage\"") {
            return googleError(message: "image rejected")
        }
        if body.contains("\"deleteObject\""), body.contains("slide-layout") {
            slideDeleted = true
        }
        if body.contains("\"deleteObject\""), body.contains("line-1") {
            lineDeleted = true
        }
        if body.contains("\"updatePageElementAltText\"") {
            if body.contains("\"title\":\"\"") {
                altTitle = nil
                altDescription = nil
            } else {
                altTitle = "graham live test"
                altDescription = "verified by run-1"
            }
        }
        if body.contains("notes-1"), body.contains("\"insertText\"") {
            notes = "graham live test notes run-1"
        }
        if body.contains("notes-1"), body.contains("\"deleteText\"") {
            notes = ""
        }
        if body.contains("\"createSheetsChart\"") {
            chartCreated = true
            return json(["replies": [["createSheetsChart": ["objectId": "chart-1"]]]])
        }

        if body.contains("\"createSlide\"") {
            let id: String
            if body.contains("TITLE_AND_BODY") {
                id = "slide-layout"
            } else if body.contains("layoutId") {
                id = "slide-exact"
            } else {
                id = "slide-primary"
            }
            return json(["replies": [["createSlide": ["objectId": id]]]])
        }
        let createReplies = [
            ("\"createShape\"", "createShape", "shape-1"),
            ("\"createImage\"", "createImage", "image-1"),
            ("\"createVideo\"", "createVideo", "video-1"),
            ("\"createLine\"", "createLine", "line-1"),
            ("\"createTable\"", "createTable", "table-1"),
            ("\"groupObjects\"", "groupObjects", "group-1"),
        ]
        if let match = createReplies.first(where: { body.contains($0.0) }) {
            return json(["replies": [[match.1: ["objectId": match.2]]]])
        }
        return json(["replies": [[:]]])
    }

    private func presentationResponse() -> HTTPResponse {
        var elements: [[String: Any]] = [
            [
                "objectId": "shape-1",
                "size": size(width: 240, height: 50),
                "transform": transform(x: 40, y: 30),
                "shape": ["text": text("Graham live test")],
            ],
            [
                "objectId": "image-1",
                "size": size(width: 180, height: 61),
                "transform": transform(x: 40, y: 100),
                "image": [
                    "contentUrl": "https://usercontent.example/image",
                    "sourceUrl": SlidesLiveTest.defaultImageURL,
                ],
            ],
            [
                "objectId": "video-1",
                "size": size(width: 240, height: 135),
                "transform": transform(x: 250, y: 100),
                "video": ["source": "YOUTUBE", "id": "dQw4w9WgXcQ"],
            ],
            [
                "objectId": "table-1",
                "size": size(width: 360, height: 150),
                "transform": transform(x: 300, y: 280),
                "table": ["rows": 3, "columns": 3, "tableRows": []],
            ],
        ]
        if !lineDeleted {
            elements.append([
                "objectId": "line-1",
                "size": size(width: 220, height: 1),
                "transform": transform(x: 40, y: 260),
                "line": ["lineCategory": "STRAIGHT"],
            ])
        }
        if chartCreated {
            elements.append([
                "objectId": "chart-1",
                "sheetsChart": ["spreadsheetId": "sheet-1", "chartId": 314],
            ])
        }
        if let altTitle { elements[0]["title"] = altTitle }
        if let altDescription { elements[0]["description"] = altDescription }

        let notesElement: [String: Any] = [
            "objectId": "notes-1",
            "shape": ["text": text(notes)],
        ]
        let primary: [String: Any] = [
            "objectId": "slide-primary",
            "pageElements": elements,
            "slideProperties": [
                "notesPage": [
                    "objectId": "notes-page-1",
                    "notesProperties": ["speakerNotesObjectId": "notes-1"],
                    "pageElements": [notesElement],
                ],
            ],
        ]
        let exact: [String: Any] = ["objectId": "slide-exact", "pageElements": []]
        let layout: [String: Any] = ["objectId": "slide-layout", "pageElements": []]
        let slides = slideDeleted ? [primary, exact] : [primary, layout, exact]
        return json([
            "presentationId": "deck-1",
            "title": "graham test run-1",
            "slides": slides,
            "layouts": [[
                "objectId": "layout-1",
                "layoutProperties": [
                    "name": "TITLE_AND_BODY", "displayName": "Title and body",
                ],
            ]],
        ])
    }

    private func size(width: Double, height: Double) -> [String: Any] {
        [
            "width": ["magnitude": width, "unit": "PT"],
            "height": ["magnitude": height, "unit": "PT"],
        ]
    }

    private func transform(x: Double, y: Double) -> [String: Any] {
        [
            "scaleX": 1.0, "scaleY": 1.0,
            "translateX": x, "translateY": y, "unit": "PT",
        ]
    }

    private func text(_ content: String) -> [String: Any] {
        ["textElements": [["textRun": ["content": content]]]]
    }

    private func driveFile(id: String, name: String, mime: String?) -> HTTPResponse {
        var value: [String: Any] = ["id": id, "name": name]
        if let mime { value["mimeType"] = mime }
        return json(value)
    }

    private func googleError(message: String) -> HTTPResponse {
        json([
            "error": [
                "code": 400, "message": message, "status": "INVALID_ARGUMENT",
            ],
        ], status: 400)
    }

    private func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return HTTPResponse(statusCode: status, body: data)
    }
}
