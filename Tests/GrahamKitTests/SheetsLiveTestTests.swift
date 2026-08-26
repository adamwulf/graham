import Foundation
import XCTest
@testable import GrahamKit

final class SheetsLiveTestTests: XCTestCase {
    func testExistingFolderIsReusedWithoutCreatingAnotherFolder() async throws {
        let fixture = SheetsLiveFixture(existingFolder: true, failSpreadsheetCreate: true)
        let runner = fixture.makeRunner(folderName: "graham test")

        let summary = await runner.run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder", "create-spreadsheet"])
        XCTAssertEqual(summary.steps.first?.outcome, .pass)
        XCTAssertEqual(summary.steps.first?.createdIDs, [])
        let folderCreates = fixture.collectionPosts.filter {
            fixture.createBody($0)?.mimeType == DriveCreateType.folder.mimeType
        }
        XCTAssertTrue(folderCreates.isEmpty)
    }

    func testMissingFolderIsCreatedAtRootAndEscapesItsNameInTheQuery() async throws {
        let fixture = SheetsLiveFixture(existingFolder: false, failSpreadsheetCreate: true)
        let folderName = "graham's \\ test"
        let runner = fixture.makeRunner(folderName: folderName)

        let summary = await runner.run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder", "create-spreadsheet"])
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
        let fixture = SheetsLiveFixture()
        let callback = StepCapture()
        let runner = fixture.makeRunner { callback.append($0) }

        let summary = await runner.run()
        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(callback.steps, summary.steps)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.passed, Self.expectedStepNames.count)

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-spreadsheet" })?.createdIDs,
            ["sheet-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "chart-add" })?.createdIDs, ["314"])

        // The write path was exercised for real: the value write carried the
        // header row, and the read-backs succeeded, so the round-trips were
        // proven, not assumed. Four value reads run: values-read, append-read,
        // raw-read, and clear-read.
        XCTAssertEqual(fixture.valuePutRequests.count, 1)
        XCTAssertTrue(fixture.valuePutRequests.allSatisfy {
            fixture.bodyString($0).contains(#"["Label","Value"]"#)
        })
        XCTAssertEqual(fixture.valueGetRequests.count, 4)
        XCTAssertEqual(fixture.appendRequests.count, 1)
        XCTAssertTrue(fixture.appendRequests.allSatisfy {
            fixture.bodyString($0).contains(#"["Epsilon","50"]"#)
        })
        XCTAssertEqual(fixture.clearRequests.count, 1)
        XCTAssertEqual(fixture.batchGetRequests.count, 1)
        XCTAssertTrue(fixture.chartBatchRequests.contains {
            let body = fixture.bodyString($0)
            return body.contains(#""addChart""#) && body.contains(#""COLUMN""#)
        })
        XCTAssertEqual(fixture.trashRequests.count, 1)
        XCTAssertTrue(fixture.trashRequests.allSatisfy { $0.url.path.hasSuffix("/sheet-1") })
    }

    func testSetValuesFailureSkipsDependentsButContinuesAndCleansUp() async {
        let fixture = SheetsLiveFixture(failSetValues: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 8)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "set-values" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): values rejected"))
        // Every step gated on the value write skips, in order.
        for name in ["values-read", "append", "raw-read", "batch-get", "chart-add", "clear"] {
            XCTAssertEqual(
                summary.steps.first(where: { $0.name == name })?.outcome,
                .skip(reason: "set-values failed"), "unexpected outcome for \(name)")
        }
        // The read-backs chain off their own step, which itself skipped.
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "append-read" })?.outcome,
            .skip(reason: "append failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "clear-read" })?.outcome,
            .skip(reason: "clear failed"))
        // The metadata read is independent of the value write and still passes.
        XCTAssertEqual(summary.steps.first(where: { $0.name == "get" })?.outcome, .pass)
        // The spreadsheet is still trashed.
        XCTAssertEqual(fixture.trashRequests.count, 1)
    }

    func testChartAddFailureFailsOnlyThatStepButStillCleansUp() async {
        let fixture = SheetsLiveFixture(failChartAdd: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "chart-add" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): chart rejected"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "values-read" })?.outcome, .pass)
        XCTAssertEqual(summary.steps.first(where: { $0.name == "get" })?.outcome, .pass)
        XCTAssertEqual(fixture.trashRequests.count, 1)
    }

    func testKeepSkipsCleanupWithoutSendingTrashRequests() async {
        let fixture = SheetsLiveFixture()
        let summary = await fixture.makeRunner(keep: true).run()

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.steps.last?.name, "drive-trash-spreadsheet")
        XCTAssertEqual(summary.steps.last?.outcome, .skip(reason: "kept"))
        XCTAssertTrue(fixture.trashRequests.isEmpty)
    }

    // A read-back that does not match the write must fail: this proves the
    // happy-path pass is earned by a real round-trip, not a rubber stamp.
    func testMismatchedReadBackFailsValuesRead() async {
        let fixture = SheetsLiveFixture(corruptReadBack: true)
        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "set-values" })?.outcome, .pass)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "values-read" })?.outcome,
            .fail(reason: "Invalid response: the written values did not round-trip"))
        // The unrelated steps still run and clean up.
        XCTAssertEqual(summary.steps.first(where: { $0.name == "get" })?.outcome, .pass)
        XCTAssertEqual(fixture.trashRequests.count, 1)
    }

    private static let expectedStepNames = [
        "folder", "create-spreadsheet",
        "set-values", "values-read", "append", "append-read", "raw-read", "batch-get",
        "get", "chart-add", "clear", "clear-read",
        "drive-trash-spreadsheet",
    ]
}

private final class StepCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SheetsLiveTestStep] = []

    var steps: [SheetsLiveTestStep] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ step: SheetsLiveTestStep) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(step)
    }
}

// MARK: - The spreadsheet simulator
//
// A small stateful, offline Sheets "server". A value write stores the grid it
// receives, and the matching read returns exactly that grid, so the runner reads
// back what its own write produced — the round-trip is real, not stubbed.

private final class SheetsLiveFixture: @unchecked Sendable {
    let transport = StubTransport()
    let existingFolder: Bool
    let failSpreadsheetCreate: Bool
    let failSetValues: Bool
    let failChartAdd: Bool
    let corruptReadBack: Bool

    // The grid the runner last wrote, returned on the matching values read.
    private var storedValues: [[String]] = []

    init(
        existingFolder: Bool = true,
        failSpreadsheetCreate: Bool = false,
        failSetValues: Bool = false,
        failChartAdd: Bool = false,
        corruptReadBack: Bool = false
    ) {
        self.existingFolder = existingFolder
        self.failSpreadsheetCreate = failSpreadsheetCreate
        self.failSetValues = failSetValues
        self.failChartAdd = failChartAdd
        self.corruptReadBack = corruptReadBack
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

    var valuePutRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "PUT" && $0.url.path.contains("/values/")
        }
    }

    var valueGetRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "GET" && $0.url.path.contains("/values/")
        }
    }

    var appendRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "POST" && $0.url.path.hasSuffix(":append")
        }
    }

    var clearRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "POST" && $0.url.path.hasSuffix(":clear")
        }
    }

    var batchGetRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "GET" && $0.url.path.hasSuffix("/values:batchGet")
        }
    }

    var chartBatchRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "POST" && $0.url.path.hasSuffix(":batchUpdate")
        }
    }

    func makeRunner(
        folderName: String = "graham test",
        keep: Bool = false,
        onStep: @escaping @Sendable (SheetsLiveTestStep) -> Void = { _ in }
    ) -> SheetsLiveTest {
        let api = TestSupport.makeAPI(transport: transport)
        return SheetsLiveTest(
            drive: DriveClient(api: api),
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
            if mime == DriveCreateType.sheets.mimeType {
                if failSpreadsheetCreate {
                    return googleError(message: "spreadsheet rejected")
                }
                return driveFile(
                    id: "sheet-1", name: "graham test sheet run-1",
                    mime: DriveCreateType.sheets.mimeType)
            }
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "PATCH" {
            let id = path.split(separator: "/").last.map(String.init) ?? "file"
            return driveFile(id: id, name: id, mime: nil)
        }
        if path.hasSuffix(":append"), request.method == "POST" {
            let values = writtenValues(request)
            let firstNewRow = storedValues.count + 1
            storedValues.append(contentsOf: values)
            return json([
                "spreadsheetId": "sheet-1",
                "tableRange": "A1:B\(max(firstNewRow - 1, 1))",
                "updates": [
                    "updatedRange": "A\(firstNewRow):B\(storedValues.count)",
                    "updatedRows": values.count,
                    "updatedColumns": values.first?.count ?? 0,
                    "updatedCells": values.reduce(0) { $0 + $1.count },
                ],
            ])
        }
        if path.hasSuffix(":clear"), request.method == "POST" {
            let cleared = "A1:B\(max(storedValues.count, 1))"
            storedValues = []
            return json(["spreadsheetId": "sheet-1", "clearedRange": cleared])
        }
        if path.hasSuffix("/values:batchGet"), request.method == "GET" {
            let ranges = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
                .queryItems?.filter { $0.name == "ranges" }.compactMap(\.value) ?? []
            let valueRanges = ranges.map { range -> [String: Any] in
                ["range": range, "majorDimension": "ROWS", "values": [["cell"]]]
            }
            return json(["spreadsheetId": "sheet-1", "valueRanges": valueRanges])
        }
        if path.contains("/values/"), request.method == "PUT" {
            if failSetValues {
                return googleError(message: "values rejected")
            }
            let values = writtenValues(request)
            storedValues = corruptReadBack
                ? values.map { _ in ["scrambled"] }
                : values
            return json([
                "updatedRange": "A1:B4",
                "updatedRows": values.count,
                "updatedColumns": values.first?.count ?? 0,
                "updatedCells": values.reduce(0) { $0 + $1.count },
            ])
        }
        if path.contains("/values/"), request.method == "GET" {
            return json([
                "range": "A1:B\(max(storedValues.count, 1))",
                "majorDimension": "ROWS",
                "values": storedValues,
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
        if path == "/v4/spreadsheets/sheet-1", request.method == "GET" {
            return json([
                "spreadsheetId": "sheet-1",
                "properties": ["title": "graham test sheet run-1"],
                "sheets": [["properties": ["sheetId": 0, "title": "Sheet1"]]],
            ])
        }
        return HTTPResponse(
            statusCode: 599, body: Data("unmatched \(request.method) \(request.url)".utf8))
    }

    /// The `[[String]]` grid carried in a values PUT body.
    private func writtenValues(_ request: HTTPRequest) -> [[String]] {
        guard let data = request.body,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["values"] as? [[String]] else {
            return []
        }
        return values
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
