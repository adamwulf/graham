import XCTest
@testable import SergeyKit

final class DriveClientTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DriveClient {
        transport.stubTokenEndpoint()
        return DriveClient(api: TestSupport.makeAPI(transport: transport))
    }

    func testListWalksAllPages() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
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
        let client = makeClient(transport: transport)
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
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/drive/v3/files?", json: #"{"files":[]}"#)

        _ = try await client.list(query: "name contains 'x'", orderBy: "modifiedTime desc", limit: 10)

        let url = try XCTUnwrap(transport.requests(urlContains: "/drive/v3/files?").first).url.absoluteString
        XCTAssertTrue(url.contains("q=name%20contains"))
        XCTAssertTrue(url.contains("orderBy=modifiedTime%20desc"))
        XCTAssertTrue(url.contains("pageSize=10"))
    }

    func testGetFetchesOneFile() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/drive/v3/files/f1",
            json: #"{"id":"f1","name":"Report","mimeType":"application/vnd.google-apps.document"}"#
        )

        let file = try await client.file(id: "f1")

        XCTAssertEqual(file.name, "Report")
        XCTAssertEqual(file.shortType, "doc")
    }

    func testExportRequestsTheMimeType() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/export", responses: [
            HTTPResponse(statusCode: 200, body: Data("plain text".utf8)),
        ])

        let data = try await client.export(id: "f1", mimeType: "text/plain")

        XCTAssertEqual(String(data: data, encoding: .utf8), "plain text")
        let url = try XCTUnwrap(transport.requests(urlContains: "/export").first).url.absoluteString
        XCTAssertTrue(url.contains("mimeType=text/plain"))
    }
}
