import XCTest
@testable import GrahamKit

/// Offline coverage for the Docs v1 table structure writes: `insertTable`,
/// `insertTableRow`, `insertTableColumn`, `deleteTableRow`, `deleteTableColumn`,
/// `mergeTableCells`, `unmergeTableCells`, and `pinTableHeaderRows`. Every
/// fixture is static JSON; no test touches the network, and the request bodies
/// are asserted exactly (the shared encoder sorts keys, so the strings are
/// deterministic). One-based CLI rows and columns are translated to the API's
/// zero-based indices at the client boundary, and the assertions lock that
/// translation. Mirrors `SlidesTableWriteTests`.
final class DocsTableWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> DocsClient {
        transport.stubTokenEndpoint()
        return DocsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Exact request-union JSON

    /// The union encodes each case under its own JSON key, with the shared
    /// location models nested exactly. This locks every discriminator and the
    /// zero-based wire indices.
    func testEveryTableRequestTypeEncodesExactly() throws {
        let start = DocsLocation(index: 10)
        let cell = DocsTableCellLocation(tableStartLocation: start, rowIndex: 1, columnIndex: 2)
        let range = DocsTableRange(tableCellLocation: cell, rowSpan: 3, columnSpan: 4)
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .insertTable(DocsInsertTableRequest(
                    rows: 2, columns: 3, location: DocsLocation(index: 5))),
                #"{"insertTable":{"columns":3,"location":{"index":5},"rows":2}}"#
            ),
            (
                .insertTable(DocsInsertTableRequest(
                    rows: 2, columns: 3,
                    endOfSegmentLocation: DocsEndOfSegmentLocation())),
                #"{"insertTable":{"columns":3,"endOfSegmentLocation":{},"rows":2}}"#
            ),
            (
                .insertTableRow(DocsInsertTableRowRequest(
                    tableCellLocation: cell, insertBelow: true)),
                #"{"insertTableRow":{"insertBelow":true,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}"#
            ),
            (
                .insertTableColumn(DocsInsertTableColumnRequest(
                    tableCellLocation: cell, insertRight: false)),
                #"{"insertTableColumn":{"insertRight":false,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}"#
            ),
            (
                .deleteTableRow(DocsDeleteTableRowRequest(tableCellLocation: cell)),
                #"{"deleteTableRow":{"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}"#
            ),
            (
                .deleteTableColumn(DocsDeleteTableColumnRequest(tableCellLocation: cell)),
                #"{"deleteTableColumn":{"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}"#
            ),
            (
                .mergeTableCells(DocsMergeTableCellsRequest(tableRange: range)),
                #"{"mergeTableCells":{"tableRange":{"columnSpan":4,"rowSpan":3,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}}"#
            ),
            (
                .unmergeTableCells(DocsUnmergeTableCellsRequest(tableRange: range)),
                #"{"unmergeTableCells":{"tableRange":{"columnSpan":4,"rowSpan":3,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}}"#
            ),
            (
                .pinTableHeaderRows(DocsPinTableHeaderRowsRequest(
                    tableStartLocation: start, pinnedHeaderRowsCount: 1)),
                #"{"pinTableHeaderRows":{"pinnedHeaderRowsCount":1,"tableStartLocation":{"index":10}}}"#
            ),
        ]
        for (request, expected) in cases {
            XCTAssertEqual(try encode(request), expected)
        }
    }

    // MARK: - Client bodies

    func testEveryTableClientMethodPostsItsExactBody() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        for _ in 0..<9 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        // insertTable at index 5 (body): the location index goes on the wire; the
        // returned start index is index + 1 (asserted below).
        _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 3, index: 5)
        // add-row below cell (2,3): one-based CLI row/column become zero-based 1/2.
        _ = try await client.insertTableRow(
            documentId: "doc-1", tableStartIndex: 10, row: 2, column: 3, below: true)
        // add-column left of cell (2,3): insertRight is false for --left.
        _ = try await client.insertTableColumn(
            documentId: "doc-1", tableStartIndex: 10, row: 2, column: 3, right: false)
        _ = try await client.deleteTableRow(
            documentId: "doc-1", tableStartIndex: 10, row: 2, column: 3)
        _ = try await client.deleteTableColumn(
            documentId: "doc-1", tableStartIndex: 10, row: 2, column: 3)
        _ = try await client.mergeTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1,
            rowSpan: 2, columnSpan: 3)
        _ = try await client.unmergeTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1,
            rowSpan: 2, columnSpan: 3)
        _ = try await client.pinTableHeaderRows(
            documentId: "doc-1", tableStartIndex: 10, pinnedHeaderRowsCount: 1)
        // pin count 0 unpins.
        _ = try await client.pinTableHeaderRows(
            documentId: "doc-1", tableStartIndex: 10, pinnedHeaderRowsCount: 0)

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 9)
        XCTAssertTrue(requests.allSatisfy { $0.method == "POST" })
        XCTAssertTrue(requests.allSatisfy {
            $0.url.absoluteString
                == "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        })
        XCTAssertEqual(Self.body(requests[0]), #"{"requests":[{"insertTable":{"columns":3,"location":{"index":5},"rows":2}}]}"#)
        XCTAssertEqual(Self.body(requests[1]), #"{"requests":[{"insertTableRow":{"insertBelow":true,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}]}"#)
        XCTAssertEqual(Self.body(requests[2]), #"{"requests":[{"insertTableColumn":{"insertRight":false,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}]}"#)
        XCTAssertEqual(Self.body(requests[3]), #"{"requests":[{"deleteTableRow":{"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}]}"#)
        XCTAssertEqual(Self.body(requests[4]), #"{"requests":[{"deleteTableColumn":{"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}]}"#)
        XCTAssertEqual(Self.body(requests[5]), #"{"requests":[{"mergeTableCells":{"tableRange":{"columnSpan":3,"rowSpan":2,"tableCellLocation":{"columnIndex":0,"rowIndex":0,"tableStartLocation":{"index":10}}}}}]}"#)
        XCTAssertEqual(Self.body(requests[6]), #"{"requests":[{"unmergeTableCells":{"tableRange":{"columnSpan":3,"rowSpan":2,"tableCellLocation":{"columnIndex":0,"rowIndex":0,"tableStartLocation":{"index":10}}}}}]}"#)
        XCTAssertEqual(Self.body(requests[7]), #"{"requests":[{"pinTableHeaderRows":{"pinnedHeaderRowsCount":1,"tableStartLocation":{"index":10}}}]}"#)
        XCTAssertEqual(Self.body(requests[8]), #"{"requests":[{"pinTableHeaderRows":{"pinnedHeaderRowsCount":0,"tableStartLocation":{"index":10}}}]}"#)
    }

    // MARK: - insertTable start index

    func testInsertTableReturnsStartIndexOfLocationPlusOne() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // The API inserts a newline before the table, so the table start index is
        // the location index + 1 — this is what the command prints.
        let result = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2, index: 5)

        XCTAssertEqual(result.tableStartIndex, 6)
        XCTAssertEqual(result.response.documentId, "doc-1")
        XCTAssertEqual(result.response.replies?.count, 1)
    }

    func testInsertTableAtEndOfBodyHasNoComputableStartIndex() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // Appending to the end of the body encodes an empty endOfSegmentLocation
        // and has no computable start index without re-reading the document.
        let result = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2, endOfSegment: true)

        XCTAssertNil(result.tableStartIndex)
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"insertTable":{"columns":2,"endOfSegmentLocation":{},"rows":2}}]}"#
        )
    }

    func testInsertTableInSegmentAllowsIndexZeroAndCarriesSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // A named segment starts its content at index 0, which the body guard
        // would reject; here it is allowed, the location carries the segmentId,
        // and the returned start index is still index + 1.
        let result = try await client.insertTable(
            documentId: "doc-1", rows: 1, columns: 1, index: 0, segmentId: "hdr-1")

        XCTAssertEqual(result.tableStartIndex, 1)
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"insertTable":{"columns":1,"location":{"index":0,"segmentId":"hdr-1"},"rows":1}}]}"#
        )
    }

    // MARK: - Segment normalization

    func testTableCellOpInSegmentCarriesSegmentIdOnTheStartLocation() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.insertTableRow(
            documentId: "doc-1", tableStartIndex: 0, row: 1, column: 1,
            below: false, segmentId: "ftr-2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"insertTableRow":{"insertBelow":false,"tableCellLocation":{"columnIndex":0,"rowIndex":0,"tableStartLocation":{"index":0,"segmentId":"ftr-2"}}}}]}"#
        )
    }

    func testEmptySegmentIdNormalizesToBodyWithNoSegmentId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        // An empty segment id means the body: no empty segmentId leaks into the
        // start location.
        _ = try await client.pinTableHeaderRows(
            documentId: "doc-1", tableStartIndex: 10, pinnedHeaderRowsCount: 2,
            segmentId: "")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"pinTableHeaderRows":{"pinnedHeaderRowsCount":2,"tableStartLocation":{"index":10}}}]}"#
        )
    }

    // MARK: - Empty reply decode

    func testTableOpDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.deleteTableRow(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    // MARK: - WriteControl

    func testTableOpWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"documentId":"doc-1","replies":[{}]}"#)

        _ = try await client.mergeTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1,
            rowSpan: 2, columnSpan: 2, requiredRevisionId: "rev-3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"mergeTableCells":{"tableRange":{"columnSpan":2,"rowSpan":2,"tableCellLocation":{"columnIndex":0,"rowIndex":0,"tableStartLocation":{"index":10}}}}}],"writeControl":{"requiredRevisionId":"rev-3"}}"#
        )
    }

    // MARK: - Validation

    func testInsertTableRejectsBadDimensionsAndIndexWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // rows/columns must be 1 or greater.
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 0, columns: 2, index: 1) }
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 0, index: 1) }
        // Body index 0 lands inside the initial section break.
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2, index: 0) }
        // A negative index is rejected in the body and in a segment.
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2, index: -1) }
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2, index: -1, segmentId: "hdr-1") }
        // No index and no end-of-segment: nothing to target.
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCellAndSpanValidationSendNothing() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Row and column must be one-based (1 or greater).
        await assertInvalid { _ = try await client.insertTableRow(
            documentId: "doc-1", tableStartIndex: 10, row: 0, column: 1, below: true) }
        await assertInvalid { _ = try await client.insertTableColumn(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 0, right: true) }
        await assertInvalid { _ = try await client.deleteTableRow(
            documentId: "doc-1", tableStartIndex: 10, row: 0, column: 1) }
        await assertInvalid { _ = try await client.deleteTableColumn(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 0) }
        // Spans must be one-based too.
        await assertInvalid { _ = try await client.mergeTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1,
            rowSpan: 0, columnSpan: 1) }
        await assertInvalid { _ = try await client.unmergeTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1,
            rowSpan: 1, columnSpan: 0) }
        // The pinned-header count must be 0 or greater.
        await assertInvalid { _ = try await client.pinTableHeaderRows(
            documentId: "doc-1", tableStartIndex: 10, pinnedHeaderRowsCount: -1) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Error propagation

    func testTableMethodPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"bad table","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "bad table") {
            _ = try await client.insertTableColumn(
                documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1, right: true)
        }
    }

    // MARK: - Helpers

    private func assertInvalid(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
        }
    }

    private func assertGoogleError(
        code expectedCode: Int,
        status expectedStatus: String,
        message expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(code, expectedCode, file: file, line: line)
            XCTAssertEqual(status, expectedStatus, file: file, line: line)
            XCTAssertEqual(message, expectedMessage, file: file, line: line)
        }
    }

    private func encode(_ request: DocsBatchUpdateRequest) throws -> String {
        String(data: try GoogleJSON.encoder.encode(request), encoding: .utf8) ?? ""
    }

    private static func body(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
