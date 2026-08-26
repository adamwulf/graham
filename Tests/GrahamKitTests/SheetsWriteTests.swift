import XCTest
@testable import GrahamKit

/// Offline coverage for A1 parsing and the Sheets values/batch write paths.
final class SheetsWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SheetsClient {
        transport.stubTokenEndpoint()
        return SheetsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - A1 parsing

    func testA1ParsesPlainRange() throws {
        XCTAssertEqual(
            try A1Range.parse("A1:B4"),
            A1Range(
                sheetName: nil,
                startRowIndex: 0,
                endRowIndex: 4,
                startColumnIndex: 0,
                endColumnIndex: 2
            )
        )
    }

    func testA1ParsesNamedSheet() throws {
        let range = try A1Range.parse("Sheet1!A1:B4")
        XCTAssertEqual(range.sheetName, "Sheet1")
        XCTAssertEqual(range.startRowIndex, 0)
        XCTAssertEqual(range.endRowIndex, 4)
        XCTAssertEqual(range.startColumnIndex, 0)
        XCTAssertEqual(range.endColumnIndex, 2)
    }

    func testA1ParsesQuotedSheetName() throws {
        let range = try A1Range.parse("'My Sheet'!A2:C10")
        XCTAssertEqual(range.sheetName, "My Sheet")
        XCTAssertEqual(range.startRowIndex, 1)
        XCTAssertEqual(range.endRowIndex, 10)
        XCTAssertEqual(range.startColumnIndex, 0)
        XCTAssertEqual(range.endColumnIndex, 3)
    }

    func testA1ParsesSingleCellAsOneByOneRange() throws {
        let range = try A1Range.parse("Sheet1!D7")
        XCTAssertEqual(range.startRowIndex, 6)
        XCTAssertEqual(range.endRowIndex, 7)
        XCTAssertEqual(range.startColumnIndex, 3)
        XCTAssertEqual(range.endColumnIndex, 4)
    }

    func testA1ParsesMultiLetterColumnsCaseInsensitively() throws {
        let range = try A1Range.parse("aa10:Ab11")
        XCTAssertEqual(range.startRowIndex, 9)
        XCTAssertEqual(range.endRowIndex, 11)
        XCTAssertEqual(range.startColumnIndex, 26)
        XCTAssertEqual(range.endColumnIndex, 28)
    }

    func testA1RejectsEmptyInput() {
        assertInvalidA1("")
    }

    func testA1RejectsMalformedCells() {
        assertInvalidA1("Sheet1!A0:B2")
        assertInvalidA1("A1:B2:C3")
    }

    func testA1RejectsReversedRanges() {
        assertInvalidA1("B2:A1")
        assertInvalidA1("A4:B2")
    }

    func testA1RejectsUnboundedColumnAndRowRanges() {
        assertInvalidA1("A:B")
        assertInvalidA1("1:4")
    }

    func testA1RejectsQuoteInsideQuotedSheetName() {
        assertInvalidA1("'Bob''s Sheet'!A1:B2")
    }

    // MARK: - Values update

    func testSetValuesPutsUserEnteredValuesToEscapedRange() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/values/",
            json: #"{"updatedRange":"'My Sheet'!A1:B3","updatedRows":3,"updatedColumns":2,"updatedCells":6}"#
        )

        let response = try await client.setValues(
            spreadsheetId: "sheet-1",
            range: "'My Sheet'!A1:B3",
            values: [["Label", "Value"], ["A", "10"], ["B", "20"]]
        )

        let request = try XCTUnwrap(transport.requests(urlContains: "/values/").first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://sheets.googleapis.com/v4/spreadsheets/sheet-1/values/'My%20Sheet'!A1:B3?valueInputOption=USER_ENTERED"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"values":[["Label","Value"],["A","10"],["B","20"]]}"#
        )
        XCTAssertEqual(response.updatedRange, "'My Sheet'!A1:B3")
        XCTAssertEqual(response.updatedRows, 3)
        XCTAssertEqual(response.updatedColumns, 2)
        XCTAssertEqual(response.updatedCells, 6)
    }

    func testSetValuesRejectsEmptyValuesAndRowsWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.setValues(spreadsheetId: "sheet-1", range: "A1", values: [])
        }
        await assertInvalidArgument {
            _ = try await client.setValues(
                spreadsheetId: "sheet-1", range: "A1", values: [["ok"], []])
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Values read options and batchGet

    func testValuesSendsNoRenderOptionByDefault() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: "/values/", json: #"{"values":[["1"]]}"#)

        _ = try await client.values(spreadsheetId: "sheet-1", range: "A1:B2")

        let request = try XCTUnwrap(transport.requests(urlContains: "/values/").first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertNil(Self.queryValue(request.url, "valueRenderOption"))
    }

    func testValuesSendsRenderOptionWhenRequested() async throws {
        for option in [SheetsValueRenderOption.unformatted, .formula] {
            let transport = StubTransport()
            let client = makeClient(transport: transport)
            transport.stub(urlContains: "/values/", json: #"{"values":[["1"]]}"#)

            _ = try await client.values(
                spreadsheetId: "sheet-1", range: "A1:B2", renderOption: option)

            let request = try XCTUnwrap(transport.requests(urlContains: "/values/").first)
            XCTAssertEqual(Self.queryValue(request.url, "valueRenderOption"), option.rawValue)
        }
    }

    func testBatchGetValuesRequestsEveryRangeAndDecodesValueRanges() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/values:batchGet",
            json: #"{"spreadsheetId":"sheet-1","valueRanges":[{"range":"A1:B2","values":[["x"]]},{"range":"C1:D2","values":[["y"]]}]}"#
        )

        let response = try await client.batchGetValues(
            spreadsheetId: "sheet-1", ranges: ["A1:B2", "C1:D2"], renderOption: .unformatted)

        let request = try XCTUnwrap(transport.requests(urlContains: "/values:batchGet").first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(Self.path(request.url), "/v4/spreadsheets/sheet-1/values:batchGet")
        XCTAssertEqual(Self.queryValues(request.url, "ranges"), ["A1:B2", "C1:D2"])
        XCTAssertEqual(Self.queryValue(request.url, "valueRenderOption"), "UNFORMATTED_VALUE")
        XCTAssertEqual(response.valueRanges?.count, 2)
        XCTAssertEqual(response.valueRanges?.first?.range, "A1:B2")
    }

    func testBatchGetValuesRejectsEmptyRangesWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.batchGetValues(spreadsheetId: "sheet-1", ranges: [])
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Append and clear

    func testAppendValuesPostsToTheAppendVerbWithInsertRows() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":append",
            json: #"{"spreadsheetId":"sheet-1","tableRange":"Sheet1!A1:C4","updates":{"updatedRange":"Sheet1!A5:C6","updatedRows":2,"updatedColumns":3,"updatedCells":6}}"#
        )

        let response = try await client.appendValues(
            spreadsheetId: "sheet-1",
            range: "Sheet1!A1:C4",
            values: [["A", "B", "C"], ["D", "E", "F"]]
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":append").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://sheets.googleapis.com/v4/spreadsheets/sheet-1/values/Sheet1!A1:C4:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"values":[["A","B","C"],["D","E","F"]]}"#
        )
        XCTAssertEqual(response.updates?.updatedCells, 6)
        XCTAssertEqual(response.tableRange, "Sheet1!A1:C4")
    }

    func testAppendValuesRejectsEmptyValuesWithoutSendingARequest() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.appendValues(spreadsheetId: "sheet-1", range: "A1", values: [])
        }
        await assertInvalidArgument {
            _ = try await client.appendValues(
                spreadsheetId: "sheet-1", range: "A1", values: [["ok"], []])
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testClearValuesPostsAnEmptyBodyToTheClearVerb() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":clear",
            json: #"{"spreadsheetId":"sheet-1","clearedRange":"Sheet1!A1:B10"}"#
        )

        let response = try await client.clearValues(
            spreadsheetId: "sheet-1", range: "Sheet1!A1:B10")

        let request = try XCTUnwrap(transport.requests(urlContains: ":clear").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            request.url.absoluteString,
            "https://sheets.googleapis.com/v4/spreadsheets/sheet-1/values/Sheet1!A1:B10:clear"
        )
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(Self.bodyString(request), "{}")
        XCTAssertEqual(response.clearedRange, "Sheet1!A1:B10")
    }

    // MARK: - Add chart

    func testAddChartBuildsOneSeriesAndReturnsChartId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Sales")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"spreadsheetId":"sheet-1","replies":[{"addChart":{"chart":{"chartId":314}}}]}"#
        )

        let chartId = try await client.addChart(
            spreadsheetId: "sheet-1",
            title: "Sales",
            range: "Sales!A1:B4"
        )

        XCTAssertEqual(chartId, 314)
        let requests = transport.requests.filter {
            $0.url.host == "sheets.googleapis.com"
        }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Self.path(requests[0].url), "/v4/spreadsheets/sheet-1")
        XCTAssertEqual(Self.path(requests[1].url), "/v4/spreadsheets/sheet-1:batchUpdate")
        XCTAssertEqual(requests[1].method, "POST")
        XCTAssertEqual(
            Self.bodyString(requests[1]),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"basicChart":{"chartType":"COLUMN","domains":[{"domain":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":4,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}}}],"headerCount":1,"legendPosition":"BOTTOM_LEGEND","series":[{"series":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":4,"sheetId":7,"startColumnIndex":1,"startRowIndex":0}]}},"targetAxis":"LEFT_AXIS"}]},"title":"Sales"}}}}]}"#
        )
    }

    func testAddChartBuildsOneSeriesPerRemainingColumn() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(22, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":99}}}]}"#
        )

        _ = try await client.addChart(
            spreadsheetId: "sheet-1",
            type: .line,
            range: "'Data'!B2:D5"
        )

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"basicChart":{"chartType":"LINE","domains":[{"domain":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":5,"sheetId":22,"startColumnIndex":1,"startRowIndex":1}]}}}],"headerCount":1,"legendPosition":"BOTTOM_LEGEND","series":[{"series":{"sourceRange":{"sources":[{"endColumnIndex":3,"endRowIndex":5,"sheetId":22,"startColumnIndex":2,"startRowIndex":1}]}},"targetAxis":"LEFT_AXIS"},{"series":{"sourceRange":{"sources":[{"endColumnIndex":4,"endRowIndex":5,"sheetId":22,"startColumnIndex":3,"startRowIndex":1}]}},"targetAxis":"LEFT_AXIS"}]}}}}}]}"#
        )
    }

    func testAddChartUsesFirstSheetWhenRangeHasNoSheetName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(41, "First"), (42, "Second")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":1}}}]}"#
        )

        _ = try await client.addChart(spreadsheetId: "sheet-1", range: "A1:B2")

        let body = Self.bodyString(try XCTUnwrap(
            transport.requests(urlContains: ":batchUpdate").first))
        XCTAssertTrue(body.contains(#""sheetId":41"#), "unexpected body: \(body)")
        XCTAssertFalse(body.contains(#""sheetId":42"#), "unexpected body: \(body)")
    }

    func testAddChartRejectsUnknownSheetWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Known")])

        do {
            _ = try await client.addChart(
                spreadsheetId: "sheet-1", range: "Missing!A1:B2")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidArgument(let detail) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("Missing"))
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testAddChartRejectsRangesThatAreTooSmallBeforeReading() async {
        for range in ["A1:A2", "A1:B1"] {
            let transport = StubTransport()
            let client = makeClient(transport: transport)
            await assertInvalidArgument {
                _ = try await client.addChart(spreadsheetId: "sheet-1", range: range)
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testAddChartRejectsMissingSheetId() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: "/spreadsheets/sheet-1?",
            json: #"{"spreadsheetId":"sheet-1","sheets":[{"properties":{"title":"Data"}}]}"#
        )

        do {
            _ = try await client.addChart(spreadsheetId: "sheet-1", range: "Data!A1:B2")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testAddChartRejectsMissingChartId() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{}}}]}"#
        )

        do {
            _ = try await client.addChart(spreadsheetId: "sheet-1", range: "Data!A1:B2")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testAddChartPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad chart","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        do {
            _ = try await client.addChart(spreadsheetId: "sheet-1", range: "Data!A1:B2")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "Bad chart")
        }
    }

    // MARK: - Sheet (tab) management

    func testAddSheetEncodesTitleAndZeroBasedIndexAndReturnsProperties() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addSheet":{"properties":{"sheetId":42,"title":"New","index":1}}}]}"#
        )

        let properties = try await client.addSheet(
            spreadsheetId: "sheet-1", title: "New", position: 2)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addSheet":{"properties":{"index":1,"title":"New"}}}]}"#
        )
        XCTAssertEqual(properties.sheetId, 42)
        XCTAssertEqual(properties.title, "New")
    }

    func testAddSheetOmitsIndexWhenPositionIsNil() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addSheet":{"properties":{"sheetId":7,"title":"New"}}}]}"#
        )

        _ = try await client.addSheet(spreadsheetId: "sheet-1", title: "New")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addSheet":{"properties":{"title":"New"}}}]}"#
        )
    }

    func testAddSheetRejectsNonPositivePositionWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.addSheet(spreadsheetId: "sheet-1", title: "New", position: 0)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAddSheetRejectsAReplyWithNoProperties() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        do {
            _ = try await client.addSheet(spreadsheetId: "sheet-1", title: "New")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testDeleteSheetEncodesTheSheetId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.deleteSheet(spreadsheetId: "sheet-1", sheetId: 7)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteSheet":{"sheetId":7}}]}"#
        )
    }

    func testRenameSheetEncodesTitleWithAFieldsMask() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.renameSheet(spreadsheetId: "sheet-1", sheetId: 7, title: "Renamed")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSheetProperties":{"fields":"title","properties":{"sheetId":7,"title":"Renamed"}}}]}"#
        )
    }

    func testSheetIdResolvesATitleToItsNumericId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(0, "Sheet1"), (99, "Data")])

        let id = try await client.sheetId(spreadsheetId: "sheet-1", title: "Data")
        XCTAssertEqual(id, 99)
    }

    func testSheetIdRejectsAnUnknownTitle() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(0, "Sheet1")])

        await assertInvalidArgument {
            _ = try await client.sheetId(spreadsheetId: "sheet-1", title: "Missing")
        }
    }

    // MARK: - Grid shape

    func testFreezeEncodesRowCountWithAFieldsMask() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.freeze(spreadsheetId: "sheet-1", sheetId: 0, rows: 1)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSheetProperties":{"fields":"gridProperties.frozenRowCount","properties":{"gridProperties":{"frozenRowCount":1},"sheetId":0}}}]}"#
        )
    }

    func testFreezeEncodesBothCountsAndMasksBoth() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.freeze(spreadsheetId: "sheet-1", sheetId: 0, rows: 1, columns: 2)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateSheetProperties":{"fields":"gridProperties.frozenRowCount,gridProperties.frozenColumnCount","properties":{"gridProperties":{"frozenColumnCount":2,"frozenRowCount":1},"sheetId":0}}}]}"#
        )
    }

    func testFreezeRejectsNoCountsAndNegativeCounts() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            try await client.freeze(spreadsheetId: "sheet-1", sheetId: 0)
        }
        await assertInvalidArgument {
            try await client.freeze(spreadsheetId: "sheet-1", sheetId: 0, rows: -1)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testResizeTranslatesOneBasedInclusiveToZeroBasedHalfOpen() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.resizeDimension(
            spreadsheetId: "sheet-1", sheetId: 0,
            dimension: .columns, start: 2, end: 3, pixelSize: 120)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDimensionProperties":{"fields":"pixelSize","properties":{"pixelSize":120},"range":{"dimension":"COLUMNS","endIndex":3,"sheetId":0,"startIndex":1}}}]}"#
        )
    }

    func testResizeSingleDimensionWhenEndEqualsStart() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.resizeDimension(
            spreadsheetId: "sheet-1", sheetId: 0,
            dimension: .rows, start: 2, end: 2, pixelSize: 40)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateDimensionProperties":{"fields":"pixelSize","properties":{"pixelSize":40},"range":{"dimension":"ROWS","endIndex":2,"sheetId":0,"startIndex":1}}}]}"#
        )
    }

    func testResizeRejectsBadRangeAndPixelSize() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        for (start, end, pixels) in [(0, 1, 10), (3, 2, 10), (1, 1, 0)] {
            await assertInvalidArgument {
                try await client.resizeDimension(
                    spreadsheetId: "sheet-1", sheetId: 0,
                    dimension: .columns, start: start, end: end, pixelSize: pixels)
            }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFirstSheetIdReturnsTheFirstSheetsId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(5, "First"), (6, "Second")])

        let id = try await client.firstSheetId(spreadsheetId: "sheet-1")
        XCTAssertEqual(id, 5)
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

    private func assertInvalidA1(
        _ input: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try A1Range.parse(input), file: file, line: line) { error in
            guard case GrahamError.invalidArgument(let detail) = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
            let inputMarker = input.isEmpty ? #""""# : input
            XCTAssertTrue(
                detail.contains(inputMarker),
                "input is not named: \(detail)",
                file: file,
                line: line
            )
        }
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

    private static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private static func queryValues(_ url: URL, _ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { $0.name == name }
            .compactMap(\.value)
    }
}
