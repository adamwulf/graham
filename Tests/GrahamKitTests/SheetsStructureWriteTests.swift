import XCTest
@testable import GrahamKit

/// Offline coverage for the Sheets structural write paths: merge / unmerge,
/// sort, auto-resize, and sheets-side named ranges.
final class SheetsStructureWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SheetsClient {
        transport.stubTokenEndpoint()
        return SheetsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Merge / unmerge

    func testMergeCellsEncodesRangeAndMergeTypeResolvingSheetName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.mergeCells(
            spreadsheetId: "sheet-1", range: "Data!A1:B2", mergeType: .mergeColumns)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(Self.path(request.url), "/v4/spreadsheets/sheet-1:batchUpdate")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"mergeCells":{"mergeType":"MERGE_COLUMNS","range":{"endColumnIndex":2,"endRowIndex":2,"sheetId":77,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    func testMergeCellsUsesFirstSheetWhenRangeHasNoName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1"), (4, "Other")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.mergeCells(
            spreadsheetId: "sheet-1", range: "A1:C1", mergeType: .mergeAll)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"mergeCells":{"mergeType":"MERGE_ALL","range":{"endColumnIndex":3,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    func testUnmergeCellsEncodesRangeResolvingSheetName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.unmergeCells(spreadsheetId: "sheet-1", range: "Data!A1:B2")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"unmergeCells":{"range":{"endColumnIndex":2,"endRowIndex":2,"sheetId":77,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    func testMergeCellsPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad merge","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        do {
            try await client.mergeCells(
                spreadsheetId: "sheet-1", range: "Data!A1:B2", mergeType: .mergeAll)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "Bad merge")
        }
    }

    // MARK: - Sort

    func testSortRangeTranslatesOneBasedColumnsToAbsoluteDimensionIndices() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.sortRange(
            spreadsheetId: "sheet-1",
            range: "Data!B2:D10",
            specs: [
                SheetsSortKey(column: 1, order: .ascending),
                SheetsSortKey(column: 3, order: .descending),
            ])

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // Column 1 within the range (B..D) maps to absolute column B (index 1);
        // column 3 maps to absolute column D (index 3).
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"sortRange":{"range":{"endColumnIndex":4,"endRowIndex":10,"sheetId":77,"startColumnIndex":1,"startRowIndex":1},"sortSpecs":[{"dimensionIndex":1,"sortOrder":"ASCENDING"},{"dimensionIndex":3,"sortOrder":"DESCENDING"}]}}]}"#
        )
    }

    func testSortRangeRejectsEmptySpecsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.sortRange(spreadsheetId: "sheet-1", range: "A1:B2", specs: [])
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSortRangeRejectsColumnOutsideRangeBeforeAnyRequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // The range A1:B2 is two columns wide; column 3 is out of range. The
        // width is known from the A1 parse, so no metadata read happens.
        await assertInvalidArgument {
            try await client.sortRange(
                spreadsheetId: "sheet-1", range: "A1:B2",
                specs: [SheetsSortKey(column: 3, order: .ascending)])
        }
        await assertInvalidArgument {
            try await client.sortRange(
                spreadsheetId: "sheet-1", range: "A1:B2",
                specs: [SheetsSortKey(column: 0, order: .ascending)])
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSortKeyParsesColumnsAndOrders() throws {
        XCTAssertEqual(try SheetsSortKey.parse("2"), SheetsSortKey(column: 2, order: .ascending))
        XCTAssertEqual(try SheetsSortKey.parse("1:asc"), SheetsSortKey(column: 1, order: .ascending))
        XCTAssertEqual(
            try SheetsSortKey.parse("3:desc"), SheetsSortKey(column: 3, order: .descending))
        // The order suffix is case-insensitive and accepts the long form.
        XCTAssertEqual(
            try SheetsSortKey.parse("4:DESCENDING"),
            SheetsSortKey(column: 4, order: .descending))
    }

    func testSortKeyRejectsMalformedTokens() {
        for input in ["", "x", "0", "-1", "2:sideways", "1:2:3", ":asc"] {
            XCTAssertThrowsError(try SheetsSortKey.parse(input)) { error in
                guard case GrahamError.invalidArgument = error else {
                    return XCTFail("Wrong error for \(input): \(error)")
                }
            }
        }
    }

    // MARK: - Auto-resize

    func testAutoResizeTranslatesOneBasedInclusiveToZeroBasedHalfOpen() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.autoResizeDimension(
            spreadsheetId: "sheet-1", sheetId: 0,
            dimension: .columns, start: 2, end: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"autoResizeDimensions":{"dimensions":{"dimension":"COLUMNS","endIndex":3,"sheetId":0,"startIndex":1}}}]}"#
        )
    }

    func testAutoResizeSingleDimensionWhenEndEqualsStart() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.autoResizeDimension(
            spreadsheetId: "sheet-1", sheetId: 0,
            dimension: .rows, start: 2, end: 2)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"autoResizeDimensions":{"dimensions":{"dimension":"ROWS","endIndex":2,"sheetId":0,"startIndex":1}}}]}"#
        )
    }

    func testAutoResizeRejectsBadRangeWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        for (start, end) in [(0, 1), (3, 2)] {
            await assertInvalidArgument {
                try await client.autoResizeDimension(
                    spreadsheetId: "sheet-1", sheetId: 0,
                    dimension: .columns, start: start, end: end)
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Named ranges

    func testAddNamedRangeEncodesBodyAndReturnsId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addNamedRange":{"namedRange":{"namedRangeId":"nr-9"}}}]}"#
        )

        let id = try await client.addNamedRange(
            spreadsheetId: "sheet-1", name: "Totals", range: "Data!A1:B2")

        XCTAssertEqual(id, "nr-9")
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addNamedRange":{"namedRange":{"name":"Totals","range":{"endColumnIndex":2,"endRowIndex":2,"sheetId":77,"startColumnIndex":0,"startRowIndex":0}}}}]}"#
        )
    }

    func testAddNamedRangeRejectsEmptyNameWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.addNamedRange(
                spreadsheetId: "sheet-1", name: "   ", range: "Data!A1:B2")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAddNamedRangeRejectsAReplyWithNoId() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addNamedRange":{"namedRange":{}}}]}"#
        )

        do {
            _ = try await client.addNamedRange(
                spreadsheetId: "sheet-1", name: "Totals", range: "Data!A1:B2")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testDeleteNamedRangeEncodesTheIdWithoutReadingMetadata() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.deleteNamedRange(spreadsheetId: "sheet-1", namedRangeId: "nr-9")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteNamedRange":{"namedRangeId":"nr-9"}}]}"#
        )
        // Deleting by id needs no metadata fetch.
        XCTAssertTrue(transport.requests(urlContains: "/spreadsheets/sheet-1?").isEmpty)
    }

    func testDeleteNamedRangeRejectsEmptyIdWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.deleteNamedRange(spreadsheetId: "sheet-1", namedRangeId: "  ")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testNamedRangesReadsThemFromMetadataAndRendersRows() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/spreadsheets/sheet-1?",
            json: #"{"spreadsheetId":"sheet-1","namedRanges":[{"namedRangeId":"nr-1","name":"Totals","range":{"sheetId":7,"startRowIndex":0,"endRowIndex":2,"startColumnIndex":0,"endColumnIndex":2}},{"namedRangeId":"nr-2","name":"Data range","range":{"sheetId":9,"startRowIndex":0,"endRowIndex":10,"startColumnIndex":0,"endColumnIndex":5}}]}"#
        )

        let ranges = try await client.namedRanges(spreadsheetId: "sheet-1")

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].namedRangeId, "nr-1")
        XCTAssertEqual(ranges[0].name, "Totals")
        XCTAssertEqual(ranges[0].range?.sheetId, 7)
        XCTAssertEqual(ranges[0].range?.endColumnIndex, 2)
        // GrahamRow renders the half-open GridRange back to a bounded A1 range.
        XCTAssertEqual(ranges[0].tableValues, ["nr-1", "Totals", "7", "A1:B2"])
        XCTAssertEqual(ranges[1].tableValues, ["nr-2", "Data range", "9", "A1:E10"])
        XCTAssertEqual(ranges[1].idValue, "nr-2")
    }

    func testNamedRangesToleratesAPartialGridRange() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        // A whole-column named range omits the row bounds. The strict GridRange
        // decode would reject it, so the read must tolerate a nil range instead
        // of failing the whole metadata decode.
        transport.stub(
            urlContains: "/spreadsheets/sheet-1?",
            json: #"{"spreadsheetId":"sheet-1","namedRanges":[{"namedRangeId":"nr-x","name":"WholeCols","range":{"sheetId":3,"startColumnIndex":0,"endColumnIndex":2}}]}"#
        )

        let ranges = try await client.namedRanges(spreadsheetId: "sheet-1")

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].namedRangeId, "nr-x")
        XCTAssertEqual(ranges[0].name, "WholeCols")
        XCTAssertNil(ranges[0].range)
        XCTAssertEqual(ranges[0].tableValues, ["nr-x", "WholeCols", "", ""])
    }

    func testNamedRangesReturnsEmptyWhenNoneAreDefined() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/spreadsheets/sheet-1?",
            json: #"{"spreadsheetId":"sheet-1","sheets":[{"properties":{"sheetId":0,"title":"Sheet1"}}]}"#
        )

        let ranges = try await client.namedRanges(spreadsheetId: "sheet-1")
        XCTAssertTrue(ranges.isEmpty)
    }

    // MARK: - Helpers

    private func stubSpreadsheet(
        _ transport: StubTransport,
        sheets: [(id: Int, title: String)]
    ) {
        let sheetJSON = sheets.map { sheet in
            #"{"properties":{"sheetId":\#(sheet.id),"title":"\#(sheet.title)"}}"#
        }.joined(separator: ",")
        transport.stub(
            urlContains: "/spreadsheets/sheet-1?",
            json: #"{"spreadsheetId":"sheet-1","sheets":[\#(sheetJSON)]}"#
        )
    }

    private func assertInvalidArgument(
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

    private static func bodyString(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func path(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
}
