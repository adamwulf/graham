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
}
