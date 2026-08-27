import Foundation
import XCTest
@testable import GrahamKit

final class DriveLiveTestTests: XCTestCase {
    func testHappyPathReportsStableStepOrderAndExercisesDriveSurface() async {
        let fixture = DriveLiveFixture()
        let callback = DriveStepCapture()

        let summary = await fixture.makeRunner { callback.append($0) }.run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(callback.steps, summary.steps)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.passed, Self.expectedStepNames.count)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-document" })?.createdIDs,
            ["document-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-shortcut" })?.createdIDs,
            ["shortcut-1"])
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "copy-document" })?.createdIDs,
            ["copy-1"])

        XCTAssertEqual(fixture.rootRequests.count, 1)
        XCTAssertEqual(fixture.sharedDriveRequests.count, 1)
        XCTAssertEqual(fixture.copyRequests.count, 1)
        XCTAssertEqual(fixture.exportRequests.count, 1)
        XCTAssertEqual(fixture.deleteRequests.count, 1)
        XCTAssertTrue(fixture.deleteRequests[0].url.path.hasSuffix("/copy-1"))
        XCTAssertEqual(fixture.trashRequests.count, 5)
        XCTAssertEqual(fixture.starRequests.count, 2)
        XCTAssertEqual(fixture.moveRequests.count, 1)
    }

    func testExistingFolderIsReused() async {
        let fixture = DriveLiveFixture(existingFolder: true)

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.steps.first?.createdIDs, [])
        XCTAssertFalse(fixture.createRequests.contains {
            fixture.createBody($0)?["name"] as? String == "graham test"
        })
    }

    func testMissingFolderIsCreatedAtRootAndEscapesItsNameInTheQuery() async throws {
        let fixture = DriveLiveFixture(existingFolder: false)
        let folderName = "graham's \\ test"

        let summary = await fixture.makeRunner(folderName: folderName).run()

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.steps.first?.createdIDs, ["folder-1"])
        let request = try XCTUnwrap(fixture.listRequests.first)
        let query = try XCTUnwrap(fixture.queryValue("q", in: request))
        XCTAssertTrue(query.contains("'root' in parents"))
        XCTAssertTrue(query.contains("mimeType='application/vnd.google-apps.folder'"))
        XCTAssertTrue(query.contains("name = 'graham\\'s \\\\ test'"))
        XCTAssertTrue(query.contains("trashed = false"))

        let create = try XCTUnwrap(fixture.createRequests.first {
            fixture.createBody($0)?["name"] as? String == folderName
        })
        XCTAssertEqual(fixture.createBody(create)?["parents"] as? [String], ["root"])
    }

    func testMoveFailureSkipsDestinationReadButIndependentStepsContinue() async {
        let fixture = DriveLiveFixture(failMove: true)

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "move-document" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): move rejected"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "list-destination" })?.outcome,
            .skip(reason: "move-document failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-shortcut" })?.outcome, .pass)
        XCTAssertEqual(summary.steps.first(where: { $0.name == "copy-document" })?.outcome, .pass)
        XCTAssertEqual(fixture.deleteRequests.count, 1)
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 4)
    }

    func testRenameMustRoundTripTheNewName() async {
        let fixture = DriveLiveFixture(corruptRenameResponse: true)

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "rename-document" })?.outcome,
            .fail(reason: "Invalid response: the document rename did not round-trip"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "move-document" })?.outcome, .pass)
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 4)
    }

    func testKeepRetainsArtifactsAndSkipsDestructiveCleanup() async {
        let fixture = DriveLiveFixture()

        let summary = await fixture.makeRunner(keep: true).run()

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 5)
        for name in [
            "delete-copy", "drive-trash-shortcut", "drive-trash-document",
            "drive-trash-source-folder", "drive-trash-destination-folder",
        ] {
            XCTAssertEqual(
                summary.steps.first(where: { $0.name == name })?.outcome,
                .skip(reason: "kept"), "unexpected outcome for \(name)")
        }
        XCTAssertTrue(fixture.deleteRequests.isEmpty)
        XCTAssertTrue(fixture.cleanupTrashRequests.isEmpty)
        // The reversible trash/untrash lifecycle still runs before cleanup.
        XCTAssertEqual(fixture.trashRequests.count, 1)
        XCTAssertEqual(fixture.untrashRequests.count, 1)
    }

    func testDeleteFailureIsReportedAndParentCleanupStillRuns() async {
        let fixture = DriveLiveFixture(failDelete: true)

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "delete-copy" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): delete rejected"))
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 4)
        XCTAssertTrue(fixture.cleanupTrashRequests.contains {
            $0.url.path.hasSuffix("/source-1")
        })
    }

    func testStateTransitionsMustRoundTrip() async {
        let fixture = DriveLiveFixture(ignoreStateMutations: true)

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "star-document" })?.outcome,
            .fail(reason: "Invalid response: the starred state did not round-trip"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "unstar-document" })?.outcome,
            .skip(reason: "star-document failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "trash-copy" })?.outcome,
            .fail(reason: "Invalid response: the trashed state did not round-trip"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "untrash-copy" })?.outcome,
            .skip(reason: "trash-copy failed"))
        XCTAssertTrue(fixture.deleteRequests.isEmpty)
    }

    func testRootFolderCreationFailureStopsBeforeCreatingArtifacts() async {
        let fixture = DriveLiveFixture(existingFolder: false, failCreateID: "folder-1")

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), ["folder"])
        XCTAssertEqual(
            summary.steps.first?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): folder-1 create rejected"))
        XCTAssertTrue(fixture.patchRequests.isEmpty)
        XCTAssertTrue(fixture.deleteRequests.isEmpty)
    }

    func testSourceFolderCreationFailureSkipsDependentsAndCleansDestination() async {
        let fixture = DriveLiveFixture(failCreateID: "source-1")

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(summary.steps.map(\.name), Self.expectedStepNames)
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-source-folder" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): source-1 create rejected"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-document" })?.outcome,
            .skip(reason: "create-source-folder failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "drive-trash-source-folder" })?.outcome,
            .skip(reason: "create-source-folder failed"))
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 1)
        XCTAssertTrue(fixture.cleanupTrashRequests[0].url.path.hasSuffix("/destination-1"))
        XCTAssertTrue(fixture.deleteRequests.isEmpty)
    }

    func testDestinationFolderCreationFailureCleansSurvivingSourceChain() async {
        let fixture = DriveLiveFixture(failCreateID: "destination-1")

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-destination-folder" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): destination-1 create rejected"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "move-document" })?.outcome,
            .skip(reason: "create-destination-folder failed"))
        XCTAssertEqual(summary.steps.first(where: { $0.name == "copy-document" })?.outcome, .pass)
        XCTAssertEqual(fixture.deleteRequests.count, 1)
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 2)
        XCTAssertTrue(fixture.cleanupTrashRequests.contains {
            $0.url.path.hasSuffix("/document-1")
        })
        XCTAssertTrue(fixture.cleanupTrashRequests.contains {
            $0.url.path.hasSuffix("/source-1")
        })
    }

    func testDocumentCreationFailureSkipsFileOperationsAndCleansFolders() async {
        let fixture = DriveLiveFixture(failCreateID: "document-1")

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "create-document" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): document-1 create rejected"))
        for name in [
            "get-document", "rename-document", "star-document", "move-document",
            "create-shortcut", "copy-document", "export-document",
        ] {
            XCTAssertEqual(
                summary.steps.first(where: { $0.name == name })?.outcome,
                .skip(reason: "create-document failed"), "unexpected outcome for \(name)")
        }
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 2)
        XCTAssertTrue(fixture.deleteRequests.isEmpty)
    }

    func testCopyFailureSkipsLifecycleAndStillCleansEverySurvivingArtifact() async {
        let fixture = DriveLiveFixture(failCopy: true)

        let summary = await fixture.makeRunner().run()

        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "copy-document" })?.outcome,
            .fail(reason: "Google API error 400 (INVALID_ARGUMENT): copy rejected"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "trash-copy" })?.outcome,
            .skip(reason: "copy-document failed"))
        XCTAssertEqual(
            summary.steps.first(where: { $0.name == "delete-copy" })?.outcome,
            .skip(reason: "untrash-copy failed"))
        XCTAssertTrue(fixture.deleteRequests.isEmpty)
        XCTAssertEqual(fixture.cleanupTrashRequests.count, 4)
    }

    private static let expectedStepNames = [
        "folder", "roots", "create-source-folder", "create-destination-folder",
        "create-document", "get-document", "list-source", "global-search",
        "rename-document", "star-document", "unstar-document", "move-document",
        "list-destination", "create-shortcut", "copy-document", "export-document",
        "trash-copy", "untrash-copy", "delete-copy", "drive-trash-shortcut",
        "drive-trash-document", "drive-trash-source-folder", "drive-trash-destination-folder",
    ]
}

private final class DriveStepCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DriveLiveTestStep] = []

    var steps: [DriveLiveTestStep] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ step: DriveLiveTestStep) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(step)
    }
}

/// A small stateful, offline Drive server. The runner's mutations update the
/// stored files, and later reads/listings observe those changes, so the tests
/// prove real request/response round trips without touching the network.
private final class DriveLiveFixture: @unchecked Sendable {
    struct StoredFile {
        let id: String
        var name: String
        let mimeType: String
        var parents: [String]
        var trashed: Bool
        var starred: Bool
    }

    let transport = StubTransport()
    let existingFolder: Bool
    let failMove: Bool
    let corruptRenameResponse: Bool
    let failDelete: Bool
    let failCreateID: String?
    let failCopy: Bool
    let ignoreStateMutations: Bool

    private var files: [String: StoredFile] = [:]

    init(
        existingFolder: Bool = true,
        failMove: Bool = false,
        corruptRenameResponse: Bool = false,
        failDelete: Bool = false,
        failCreateID: String? = nil,
        failCopy: Bool = false,
        ignoreStateMutations: Bool = false
    ) {
        self.existingFolder = existingFolder
        self.failMove = failMove
        self.corruptRenameResponse = corruptRenameResponse
        self.failDelete = failDelete
        self.failCreateID = failCreateID
        self.failCopy = failCopy
        self.ignoreStateMutations = ignoreStateMutations
        if existingFolder {
            files["folder-1"] = StoredFile(
                id: "folder-1", name: "graham test",
                mimeType: DriveCreateType.folder.mimeType,
                parents: ["root"], trashed: false, starred: false)
        }
        transport.stubTokenEndpoint()
        transport.stub(matching: { _ in true }, responding: { [self] request in
            response(to: request)
        })
    }

    var listRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "GET" && $0.url.path == "/drive/v3/files" }
    }

    var rootRequests: [HTTPRequest] {
        transport.requests.filter {
            $0.method == "GET" && $0.url.path == "/drive/v3/files/root"
        }
    }

    var sharedDriveRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "GET" && $0.url.path == "/drive/v3/drives" }
    }

    var createRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "POST" && $0.url.path == "/drive/v3/files" }
    }

    var copyRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "POST" && $0.url.path.hasSuffix("/copy") }
    }

    var exportRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "GET" && $0.url.path.hasSuffix("/export") }
    }

    var deleteRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "DELETE" }
    }

    var patchRequests: [HTTPRequest] {
        transport.requests.filter { $0.method == "PATCH" }
    }

    var trashRequests: [HTTPRequest] {
        patchRequests.filter { createBody($0)?["trashed"] as? Bool == true }
    }

    var untrashRequests: [HTTPRequest] {
        patchRequests.filter { createBody($0)?["trashed"] as? Bool == false }
    }

    var cleanupTrashRequests: [HTTPRequest] {
        trashRequests.filter { !$0.url.path.hasSuffix("/copy-1") }
    }

    var starRequests: [HTTPRequest] {
        patchRequests.filter { createBody($0)?["starred"] != nil }
    }

    var moveRequests: [HTTPRequest] {
        patchRequests.filter { queryValue("addParents", in: $0) != nil }
    }

    func makeRunner(
        folderName: String = "graham test",
        keep: Bool = false,
        onStep: @escaping @Sendable (DriveLiveTestStep) -> Void = { _ in }
    ) -> DriveLiveTest {
        let api = TestSupport.makeAPI(transport: transport)
        return DriveLiveTest(
            drive: DriveClient(api: api),
            folderName: folderName,
            keep: keep,
            label: "run-1",
            onStep: onStep)
    }

    func createBody(_ request: HTTPRequest) -> [String: Any]? {
        guard let body = request.body else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    func queryValue(_ name: String, in request: HTTPRequest) -> String? {
        URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private func response(to request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path

        if path == "/drive/v3/files/root", request.method == "GET" {
            return json([
                "id": "root", "name": "My Drive",
                "mimeType": DriveCreateType.folder.mimeType,
            ])
        }
        if path == "/drive/v3/drives", request.method == "GET" {
            return json(["drives": []])
        }
        if path == "/drive/v3/files", request.method == "GET" {
            return listResponse(request)
        }
        if path == "/drive/v3/files", request.method == "POST" {
            return createResponse(request)
        }
        if path.hasSuffix("/copy"), request.method == "POST" {
            return copyResponse(request)
        }
        if path.hasSuffix("/export"), request.method == "GET" {
            return HTTPResponse(statusCode: 200, body: Data("Graham Drive live test\n".utf8))
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "GET" {
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            guard let file = files[id] else { return googleError(message: "file not found", status: 404) }
            return driveFile(file)
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "PATCH" {
            return updateResponse(request)
        }
        if path.hasPrefix("/drive/v3/files/"), request.method == "DELETE" {
            if failDelete { return googleError(message: "delete rejected") }
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            guard files[id] != nil else {
                return googleError(message: "file not found", status: 404)
            }
            files[id] = nil
            return HTTPResponse(statusCode: 204)
        }
        return HTTPResponse(
            statusCode: 599,
            body: Data("unmatched \(request.method) \(request.url)".utf8))
    }

    private func listResponse(_ request: HTTPRequest) -> HTTPResponse {
        let query = queryValue("q", in: request) ?? ""
        let matches = files.values.filter { file in
            guard !file.trashed else { return false }
            if query.contains("mimeType='\(DriveCreateType.folder.mimeType)'"),
               file.mimeType != DriveCreateType.folder.mimeType {
                return false
            }
            if query.contains("mimeType='\(DriveCreateType.docs.mimeType)'"),
               file.mimeType != DriveCreateType.docs.mimeType {
                return false
            }
            for candidate in ["root", "folder-1", "source-1", "destination-1"]
            where query.contains("'\(candidate)' in parents") {
                if !file.parents.contains(candidate) { return false }
            }
            if query.contains("name = 'graham test'"), file.name != "graham test" {
                return false
            }
            if query.contains("name = 'graham drive document run-1'"),
               file.name != "graham drive document run-1" {
                return false
            }
            return true
        }.sorted { $0.id < $1.id }
        return json(["files": matches.map(fileObject)])
    }

    private func createResponse(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = createBody(request),
              let name = body["name"] as? String,
              let mime = body["mimeType"] as? String else {
            return googleError(message: "malformed create")
        }
        let parents = body["parents"] as? [String] ?? []
        let id: String
        if mime == DriveShortcutCreateRequest.mimeType {
            id = "shortcut-1"
        } else if name == "graham test" || name == "graham's \\ test" {
            id = "folder-1"
        } else if name.contains("source") {
            id = "source-1"
        } else if name.contains("destination") {
            id = "destination-1"
        } else {
            id = "document-1"
        }
        if failCreateID == id {
            return googleError(message: "\(id) create rejected")
        }
        let file = StoredFile(
            id: id, name: name, mimeType: mime, parents: parents,
            trashed: false, starred: false)
        files[id] = file
        return driveFile(file)
    }

    private func copyResponse(_ request: HTTPRequest) -> HTTPResponse {
        if failCopy { return googleError(message: "copy rejected") }
        let body = createBody(request) ?? [:]
        let file = StoredFile(
            id: "copy-1",
            name: body["name"] as? String ?? "Copy",
            mimeType: DriveCreateType.docs.mimeType,
            parents: body["parents"] as? [String] ?? [],
            trashed: false,
            starred: false)
        files[file.id] = file
        var object = fileObject(file)
        // The live API returns only its default projection unless the caller
        // explicitly requests parents. Modeling that here prevents the fixture
        // from hiding a missing `fields` selector on files.copy.
        if queryValue("fields", in: request)?.contains("parents") != true {
            object["parents"] = nil
        }
        return json(object)
    }

    private func updateResponse(_ request: HTTPRequest) -> HTTPResponse {
        let id = request.url.path.split(separator: "/").last.map(String.init) ?? ""
        guard var file = files[id] else { return googleError(message: "file not found", status: 404) }
        let body = createBody(request) ?? [:]
        if let name = body["name"] as? String {
            if corruptRenameResponse {
                return driveFile(file)
            }
            file.name = name
        }
        if !ignoreStateMutations {
            if let starred = body["starred"] as? Bool { file.starred = starred }
            if let trashed = body["trashed"] as? Bool { file.trashed = trashed }
        }
        if let parent = queryValue("addParents", in: request) {
            if failMove { return googleError(message: "move rejected") }
            file.parents = [parent]
        }
        files[id] = file
        return driveFile(file)
    }

    private func driveFile(_ file: StoredFile) -> HTTPResponse {
        json(fileObject(file))
    }

    private func fileObject(_ file: StoredFile) -> [String: Any] {
        [
            "id": file.id,
            "name": file.name,
            "mimeType": file.mimeType,
            "parents": file.parents,
            "starred": file.starred,
            "trashed": file.trashed,
        ]
    }

    private func googleError(message: String, status: Int = 400) -> HTTPResponse {
        json([
            "error": ["code": status, "message": message, "status": "INVALID_ARGUMENT"],
        ], status: status)
    }

    private func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return HTTPResponse(statusCode: status, body: data)
    }
}
