import XCTest
@testable import GrahamKit

final class DriveClientTests: XCTestCase {

    func testListWalksAllPages() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", responses: [
            StubTransport.json(#"""
            {"nextPageToken":"tok+1","files":[
                {"id":"a","name":"First"},
                {"id":"b","name":"Second"}
            ]}
            """#),
            StubTransport.json(#"{"files":[{"id":"c","name":"Third"}]}"#),
        ])

        let files = try await client.list()

        XCTAssertEqual(files.map(\.id), ["a", "b", "c"])
        let listRequests = transport.requests(urlContains: "/drive/v3/files?")
        XCTAssertEqual(listRequests.count, 2)
        // The "+" in the page token must reach the server as %2B, not as a space.
        XCTAssertTrue(listRequests[1].url.absoluteString.contains("pageToken=tok%2B1"))
    }

    func testListStopsAtTheLimit() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"""
        {"nextPageToken":"more","files":[
            {"id":"a","name":"First"},
            {"id":"b","name":"Second"}
        ]}
        """#)

        let files = try await client.list(limit: 2)

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(transport.requests(urlContains: "/drive/v3/files?").count, 1)
    }

    func testListSendsQueryAndOrder() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(query: "name contains 'x'", orderBy: "modifiedTime desc", limit: 10)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        let url = request.url.absoluteString
        XCTAssertTrue(url.contains("orderBy=modifiedTime%20desc"))
        XCTAssertTrue(url.contains("pageSize=10"))
        // The user query is wrapped in parentheses and ANDed with trashed = false.
        XCTAssertEqual(Self.queryValue(request.url), "(name contains 'x') and trashed = false")
    }

    func testGetFetchesOneFile() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"id":"f1","name":"Report","mimeType":"application/vnd.google-apps.document"}"#
        )

        let file = try await client.file(id: "f1")

        XCTAssertEqual(file.name, "Report")
        XCTAssertEqual(file.shortType, "doc")
        // Spans shared drives, so a shared-drive file resolves instead of 404-ing.
        let url = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first).url.absoluteString
        XCTAssertTrue(url.contains("supportsAllDrives=true"))
    }

    func testExportRequestsTheMimeType() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/export", responses: [
            HTTPResponse(statusCode: 200, body: Data("plain text".utf8)),
        ])

        let data = try await client.export(id: "f1", mimeType: "text/plain")

        XCTAssertEqual(String(data: data, encoding: .utf8), "plain text")
        let url = try XCTUnwrap(transport.requests(urlContains: "/export").first).url.absoluteString
        XCTAssertTrue(url.contains("mimeType=text/plain"))
        XCTAssertTrue(url.contains("supportsAllDrives=true"))
    }

    func testDownloadRequestsRawMediaAcrossSharedDrives() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files/f1", responses: [
            HTTPResponse(statusCode: 200, body: Data("raw bytes".utf8)),
        ])

        let data = try await client.download(id: "f1")

        XCTAssertEqual(String(data: data, encoding: .utf8), "raw bytes")
        let url = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/f1").first).url.absoluteString
        XCTAssertTrue(url.contains("alt=media"))
        XCTAssertTrue(url.contains("supportsAllDrives=true"))
    }

    // MARK: - Navigation and filters

    func testListByParentIDScopesToTheFolderAndAllDrives() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(parentID: "folder123")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(Self.queryValue(request.url), "'folder123' in parents and trashed = false")
        let url = request.url.absoluteString
        XCTAssertTrue(url.contains("corpora=allDrives"))
        XCTAssertTrue(url.contains("includeItemsFromAllDrives=true"))
        XCTAssertTrue(url.contains("supportsAllDrives=true"))
    }

    func testListByTypeAddsTheMimeClause() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(type: .sheets)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(
            Self.queryValue(request.url),
            "mimeType='application/vnd.google-apps.spreadsheet' and trashed = false"
        )
    }

    func testListCombinesParentTypeAndQuery() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(parentID: "p1", type: .docs, query: "name contains 'x'")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(
            Self.queryValue(request.url),
            "'p1' in parents and mimeType='application/vnd.google-apps.document' "
                + "and (name contains 'x') and trashed = false"
        )
    }

    func testListEscapesSingleQuotesInTheParentID() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(parentID: "a'b")

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(Self.queryValue(request.url), #"'a\'b' in parents and trashed = false"#)
    }

    func testDrivesWalksAllPages() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/drives?", responses: [
            StubTransport.json(#"""
            {"nextPageToken":"pg+2","drives":[
                {"id":"d1","name":"Team A"},
                {"id":"d2","name":"Team B"}
            ]}
            """#),
            StubTransport.json(#"{"drives":[{"id":"d3","name":"Team C"}]}"#),
        ])

        let drives = try await client.drives()

        XCTAssertEqual(drives.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(drives.map { $0.name ?? "" }, ["Team A", "Team B", "Team C"])
        let requests = transport.requests(urlContains: "/drive/v3/drives?")
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].url.absoluteString.contains("fields=nextPageToken,drives(id,name)"))
        // The "+" in the page token must reach the server as %2B, not as a space.
        XCTAssertTrue(requests[1].url.absoluteString.contains("pageToken=pg%2B2"))
    }

    func testDrivesStopsAtTheLimit() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/drives?", json: #"""
        {"nextPageToken":"more","drives":[
            {"id":"d1","name":"Team A"},
            {"id":"d2","name":"Team B"}
        ]}
        """#)

        let drives = try await client.drives(limit: 1)

        XCTAssertEqual(drives.map(\.id), ["d1"])
        XCTAssertEqual(transport.requests(urlContains: "/drive/v3/drives?").count, 1)
    }

    func testRootDecodesTheFilesGetResponse() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/root",
            json: #"{"id":"root-id","name":"My Drive","mimeType":"application/vnd.google-apps.folder"}"#
        )

        let root = try await client.root()

        XCTAssertEqual(root.id, "root-id")
        XCTAssertEqual(root.name, "My Drive")
        XCTAssertEqual(root.shortType, "folder")
        let url = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files/root").first).url.absoluteString
        XCTAssertTrue(url.contains("fields=id,name,mimeType"))
    }

    func testListEscapesBackslashesInTheParentID() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(parentID: #"a\b"#)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        // The backslash is doubled, then the value stays inside single quotes.
        XCTAssertEqual(Self.queryValue(request.url), #"'a\\b' in parents and trashed = false"#)
    }

    func testRootsReturnsMyDriveThenTheSharedDrives() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/root",
            json: #"{"id":"root-id","name":"My Drive","mimeType":"application/vnd.google-apps.folder"}"#
        )
        transport.stub(urlContains: "/drive/v3/drives?", json: #"""
        {"drives":[{"id":"d1","name":"Team A"},{"id":"d2","name":"Team B"}]}
        """#)

        let rows = try await client.roots()

        XCTAssertEqual(rows.map(\.id), ["root-id", "d1", "d2"])
        XCTAssertEqual(rows.map(\.shortType), ["folder", "drive", "drive"])
    }

    func testRootsWithLimitOneReturnsOnlyMyDriveAndSkipsTheDrivesCall() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/root",
            json: #"{"id":"root-id","name":"My Drive","mimeType":"application/vnd.google-apps.folder"}"#
        )

        let rows = try await client.roots(limit: 1)

        XCTAssertEqual(rows.map(\.id), ["root-id"])
        // My Drive already fills the limit, so the shared-drive endpoint is not hit.
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/drives?").isEmpty)
    }

    func testRootsWithZeroLimitReturnsNothing() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)

        let rows = try await client.roots(limit: 0)

        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testBrowseWithIDListsFolderContents() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[{"id":"c1","name":"child"}]}"#)

        let rows = try await client.browse(id: "f1")

        XCTAssertEqual(rows.map(\.id), ["c1"])
        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(Self.queryValue(request.url), "'f1' in parents and trashed = false")
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/files/root").isEmpty)
    }

    func testBrowseWithNoArgumentsReturnsTheTopLevelRoots() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/root",
            json: #"{"id":"root-id","name":"My Drive","mimeType":"application/vnd.google-apps.folder"}"#
        )
        transport.stub(urlContains: "/drive/v3/drives?", json: #"{"drives":[{"id":"d1","name":"Team A"}]}"#)

        let rows = try await client.browse()

        XCTAssertEqual(rows.map(\.id), ["root-id", "d1"])
        // The top-level path never runs a files search.
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/files?").isEmpty)
    }

    func testBrowseWithFoldersTypeAndNoIDStillReturnsTheRoots() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/root",
            json: #"{"id":"root-id","name":"My Drive","mimeType":"application/vnd.google-apps.folder"}"#
        )
        transport.stub(urlContains: "/drive/v3/drives?", json: #"{"drives":[]}"#)

        let rows = try await client.browse(type: .folders)

        XCTAssertEqual(rows.map(\.id), ["root-id"])
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/files?").isEmpty)
    }

    func testBrowseWithQueryAndNoIDRunsAGlobalSearch() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[{"id":"g1","name":"hit"}]}"#)

        let rows = try await client.browse(query: "name contains 'x'")

        XCTAssertEqual(rows.map(\.id), ["g1"])
        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(Self.queryValue(request.url), "(name contains 'x') and trashed = false")
        // A global search does not fetch the roots.
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/files/root").isEmpty)
    }

    func testBrowseWithDocsTypeAndNoIDRunsAGlobalSearch() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.browse(type: .docs)

        let request = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first)
        XCTAssertEqual(
            Self.queryValue(request.url),
            "mimeType='application/vnd.google-apps.document' and trashed = false"
        )
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/files/root").isEmpty)
    }

    func testBrowseTreatsAnEmptyQueryAsNoQuery() async throws {
        let transport = StubTransport()
        let client = TestSupport.driveClient(transport)
        transport.stub(
            urlContains: "/drive/v3/files/root",
            json: #"{"id":"root-id","name":"My Drive","mimeType":"application/vnd.google-apps.folder"}"#
        )
        transport.stub(urlContains: "/drive/v3/drives?", json: #"{"drives":[]}"#)

        let rows = try await client.browse(query: "")

        // An empty query behaves like no query, so this returns the roots.
        XCTAssertEqual(rows.map(\.id), ["root-id"])
        XCTAssertTrue(transport.requests(urlContains: "/drive/v3/files?").isEmpty)
    }

    /// Reads the decoded `q` query item from a request URL.
    private static func queryValue(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" })?
            .value
    }
}
