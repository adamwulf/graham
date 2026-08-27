import XCTest
@testable import GrahamKit

/// Offline coverage for the histogram, scorecard, and candlestick chart specs,
/// and for moving an embedded chart (`updateEmbeddedObjectPosition`).
final class SheetsChartTypesWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SheetsClient {
        transport.stubTokenEndpoint()
        return SheetsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Histogram

    func testAddChartHistogramBuildsOneSeriesPerColumnWithTuning() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":5}}}]}"#)

        _ = try await client.addChart(
            spreadsheetId: "sheet-1", title: "Hist", range: "Data!A1:C5",
            kind: .histogram, bucketSize: 5, outlierPercentile: 0.5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"histogramChart":{"bucketSize":5,"outlierPercentile":0.5,"series":[{"data":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":5,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}}},{"data":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":5,"sheetId":7,"startColumnIndex":1,"startRowIndex":0}]}}},{"data":{"sourceRange":{"sources":[{"endColumnIndex":3,"endRowIndex":5,"sheetId":7,"startColumnIndex":2,"startRowIndex":0}]}}}]},"title":"Hist"}}}}]}"#
        )
    }

    func testAddChartHistogramOmitsTuningWhenNil() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":5}}}]}"#)

        _ = try await client.addChart(
            spreadsheetId: "sheet-1", range: "Data!A1:A5", kind: .histogram)

        let body = Self.bodyString(try XCTUnwrap(
            transport.requests(urlContains: ":batchUpdate").first))
        XCTAssertTrue(body.contains(#""histogramChart""#), "unexpected body: \(body)")
        XCTAssertFalse(body.contains("bucketSize"), "nil bucketSize must be omitted: \(body)")
        XCTAssertFalse(
            body.contains("outlierPercentile"), "nil outlierPercentile must be omitted: \(body)")
    }

    // MARK: - Scorecard

    func testAddChartScorecardBuildsKeyBaselineAndAggregate() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":8}}}]}"#)

        _ = try await client.addChart(
            spreadsheetId: "sheet-1", title: "Score", range: "Data!A1:B5",
            kind: .scorecard, aggregate: .sum)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"scorecardChart":{"aggregateType":"SUM","baselineValueData":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":5,"sheetId":7,"startColumnIndex":1,"startRowIndex":0}]}},"keyValueData":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":5,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}}},"title":"Score"}}}}]}"#
        )
    }

    func testAddChartScorecardSingleColumnOmitsBaselineAndAggregate() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":8}}}]}"#)

        _ = try await client.addChart(
            spreadsheetId: "sheet-1", range: "Data!A1:A5", kind: .scorecard)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"scorecardChart":{"keyValueData":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":5,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}}}}}}}]}"#
        )
    }

    func testAddChartScorecardRejectsTooWideRangeBeforeReading() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgument {
            _ = try await client.addChart(
                spreadsheetId: "sheet-1", range: "A1:C5", kind: .scorecard)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Candlestick

    func testAddChartCandlestickMapsFiveColumnsInOrder() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":11}}}]}"#)

        _ = try await client.addChart(
            spreadsheetId: "sheet-1", title: "Candle", range: "Data!A1:E5", kind: .candlestick)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"candlestickChart":{"data":[{"closeSeries":{"data":{"sourceRange":{"sources":[{"endColumnIndex":5,"endRowIndex":5,"sheetId":7,"startColumnIndex":4,"startRowIndex":0}]}}},"highSeries":{"data":{"sourceRange":{"sources":[{"endColumnIndex":3,"endRowIndex":5,"sheetId":7,"startColumnIndex":2,"startRowIndex":0}]}}},"lowSeries":{"data":{"sourceRange":{"sources":[{"endColumnIndex":4,"endRowIndex":5,"sheetId":7,"startColumnIndex":3,"startRowIndex":0}]}}},"openSeries":{"data":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":5,"sheetId":7,"startColumnIndex":1,"startRowIndex":0}]}}}}],"domain":{"data":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":5,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}}}},"title":"Candle"}}}}]}"#
        )
    }

    func testAddChartCandlestickRejectsWrongColumnCountBeforeReading() async {
        for range in ["A1:D5", "A1:F5"] {
            let transport = StubTransport()
            let client = makeClient(transport: transport)
            await assertInvalidArgument {
                _ = try await client.addChart(
                    spreadsheetId: "sheet-1", range: range, kind: .candlestick)
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    // MARK: - Kind resolution

    func testAddChartKindOverridesBasicType() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":1}}}]}"#)

        // --kind bar wins over the default --type column.
        _ = try await client.addChart(
            spreadsheetId: "sheet-1", type: .column, range: "A1:B4", kind: .bar)

        let body = Self.bodyString(try XCTUnwrap(
            transport.requests(urlContains: ":batchUpdate").first))
        XCTAssertTrue(body.contains(#""chartType":"BAR""#), "unexpected body: \(body)")
    }

    func testAddChartKindPieMatchesThePieFlag() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addChart":{"chart":{"chartId":1}}}]}"#)

        _ = try await client.addChart(
            spreadsheetId: "sheet-1", title: "Pie", range: "A1:B4", kind: .pie)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addChart":{"chart":{"position":{"newSheet":true},"spec":{"pieChart":{"domain":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":4,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}},"legendPosition":"RIGHT_LEGEND","series":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":4,"sheetId":7,"startColumnIndex":1,"startRowIndex":0}]}}},"title":"Pie"}}}}]}"#
        )
    }

    func testUpdateChartHistogramEncodesUpdateChartSpec() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.updateChart(
            spreadsheetId: "sheet-1", chartId: 42, range: "Data!A1:B5",
            kind: .histogram, bucketSize: 5)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateChartSpec":{"chartId":42,"spec":{"histogramChart":{"bucketSize":5,"series":[{"data":{"sourceRange":{"sources":[{"endColumnIndex":1,"endRowIndex":5,"sheetId":7,"startColumnIndex":0,"startRowIndex":0}]}}},{"data":{"sourceRange":{"sources":[{"endColumnIndex":2,"endRowIndex":5,"sheetId":7,"startColumnIndex":1,"startRowIndex":0}]}}}]}}}}]}"#
        )
    }

    // MARK: - Move chart

    func testMoveChartOverlayEncodesPositionAndResolvesAnchorSheet() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data"), (9, "Second")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.moveChart(
            spreadsheetId: "sheet-1", chartId: 42, anchor: "Second!D2",
            width: 300, height: 200)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateEmbeddedObjectPosition":{"fields":"anchorCell,widthPixels,heightPixels","newPosition":{"overlayPosition":{"anchorCell":{"columnIndex":3,"rowIndex":1,"sheetId":9},"heightPixels":200,"widthPixels":300}},"objectId":42}}]}"#
        )
    }

    func testMoveChartOverlayUsesFirstSheetWhenAnchorHasNoSheetName() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(7, "Data"), (9, "Second")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.moveChart(spreadsheetId: "sheet-1", chartId: 42, anchor: "C1")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateEmbeddedObjectPosition":{"fields":"anchorCell","newPosition":{"overlayPosition":{"anchorCell":{"columnIndex":2,"rowIndex":0,"sheetId":7}}},"objectId":42}}]}"#
        )
    }

    func testMoveChartToNewSheetEncodesNewSheetWithoutReadingMetadata() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.moveChart(spreadsheetId: "sheet-1", chartId: 42, newSheet: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"updateEmbeddedObjectPosition":{"fields":"*","newPosition":{"newSheet":true},"objectId":42}}]}"#
        )
        // No metadata fetch is needed to move to a new sheet.
        XCTAssertTrue(transport.requests(urlContains: "/spreadsheets/sheet-1?").isEmpty)
    }

    func testMoveChartRejectsWrongPlacementModesWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Neither placement.
        await assertInvalidArgument {
            try await client.moveChart(spreadsheetId: "sheet-1", chartId: 42)
        }
        // Both placements.
        await assertInvalidArgument {
            try await client.moveChart(
                spreadsheetId: "sheet-1", chartId: 42, anchor: "C1", newSheet: true)
        }
        // Width/height without an anchor.
        await assertInvalidArgument {
            try await client.moveChart(
                spreadsheetId: "sheet-1", chartId: 42, width: 100, newSheet: true)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testMoveChartPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad move","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        do {
            try await client.moveChart(spreadsheetId: "sheet-1", chartId: 42, newSheet: true)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "Bad move")
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
}
