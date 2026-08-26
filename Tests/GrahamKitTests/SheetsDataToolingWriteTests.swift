import XCTest
@testable import GrahamKit

/// Offline coverage for the Sheets data-tooling writes: conditional formatting,
/// data validation, basic filters and filter views, and protected ranges. Each
/// operation asserts its exact encoded batch-update body, the id-returning ops
/// assert reply decoding, and the guarded inputs assert no request is sent.
final class SheetsDataToolingWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SheetsClient {
        transport.stubTokenEndpoint()
        return SheetsClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Shared boolean condition

    func testBooleanConditionMakeBuildsUserEnteredValues() throws {
        let condition = try SheetsBooleanCondition.make(
            type: .numberBetween, values: ["1", "10"])
        XCTAssertEqual(condition.type, "NUMBER_BETWEEN")
        XCTAssertEqual(
            condition.values,
            [SheetsConditionValue(userEnteredValue: "1"),
             SheetsConditionValue(userEnteredValue: "10")])
    }

    func testBooleanConditionMakeValidatesValueArity() {
        // Zero-value types reject any values.
        assertInvalidArgument { _ = try SheetsBooleanCondition.make(type: .blank, values: ["x"]) }
        assertInvalidArgument { _ = try SheetsBooleanCondition.make(type: .notBlank, values: ["x"]) }
        // *_BETWEEN types need exactly two values.
        assertInvalidArgument { _ = try SheetsBooleanCondition.make(type: .numberBetween, values: ["1"]) }
        assertInvalidArgument {
            _ = try SheetsBooleanCondition.make(type: .numberNotBetween, values: ["1", "2", "3"])
        }
        // Otherwise at least one value is required.
        assertInvalidArgument { _ = try SheetsBooleanCondition.make(type: .numberGreater, values: []) }
        assertInvalidArgument { _ = try SheetsBooleanCondition.make(type: .textContains, values: []) }
    }

    func testBooleanConditionMakeAllowsValidCounts() throws {
        XCTAssertEqual(try SheetsBooleanCondition.make(type: .blank, values: []).values, [])
        XCTAssertEqual(
            try SheetsBooleanCondition.make(type: .oneOfList, values: ["A", "B", "C"]).values.count, 3)
    }

    // MARK: - Conditional formatting

    func testAddConditionalFormatRuleEncodesBooleanRuleAndResolvesSheet() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(5, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.addConditionalFormatRule(
            spreadsheetId: "sheet-1",
            range: "Data!A2:A100",
            type: .numberGreater,
            values: ["10"],
            backgroundColor: try SheetsColor.parse("#FF0000"),
            index: 2)

        // The metadata read plus the batch-update write.
        let apiRequests = transport.requests.filter { $0.url.host == "sheets.googleapis.com" }
        XCTAssertEqual(apiRequests.count, 2)
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addConditionalFormatRule":{"index":2,"rule":{"booleanRule":{"condition":{"type":"NUMBER_GREATER","values":[{"userEnteredValue":"10"}]},"format":{"backgroundColor":{"blue":0,"green":0,"red":1}}},"ranges":[{"endColumnIndex":1,"endRowIndex":100,"sheetId":5,"startColumnIndex":0,"startRowIndex":1}]}}}]}"#
        )
    }

    func testAddConditionalFormatRuleBetweenEncodesTwoValues() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(5, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.addConditionalFormatRule(
            spreadsheetId: "sheet-1",
            range: "Data!A2:A100",
            type: .numberBetween,
            values: ["1", "10"],
            backgroundColor: try SheetsColor.parse("#00FF00"))

        let body = Self.bodyString(try XCTUnwrap(
            transport.requests(urlContains: ":batchUpdate").first))
        XCTAssertTrue(body.contains(#""type":"NUMBER_BETWEEN""#), "unexpected body: \(body)")
        XCTAssertTrue(
            body.contains(#""values":[{"userEnteredValue":"1"},{"userEnteredValue":"10"}]"#),
            "unexpected body: \(body)")
        // The default index is zero.
        XCTAssertTrue(body.contains(#""index":0"#), "unexpected body: \(body)")
    }

    func testAddConditionalFormatRuleValidatesInputWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        // Wrong value counts, and a negative index, all fail before any request.
        await assertInvalidArgumentAsync {
            try await client.addConditionalFormatRule(
                spreadsheetId: "sheet-1", range: "Data!A2:A100",
                type: .numberGreater, values: [],
                backgroundColor: try SheetsColor.parse("#FF0000"))
        }
        await assertInvalidArgumentAsync {
            try await client.addConditionalFormatRule(
                spreadsheetId: "sheet-1", range: "Data!A2:A100",
                type: .blank, values: ["x"],
                backgroundColor: try SheetsColor.parse("#FF0000"))
        }
        await assertInvalidArgumentAsync {
            try await client.addConditionalFormatRule(
                spreadsheetId: "sheet-1", range: "Data!A2:A100",
                type: .numberGreater, values: ["1"],
                backgroundColor: try SheetsColor.parse("#FF0000"), index: -1)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testDeleteConditionalFormatRuleEncodesSheetIdAndIndexWithoutReadingMetadata() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.deleteConditionalFormatRule(spreadsheetId: "sheet-1", sheetId: 5, index: 1)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteConditionalFormatRule":{"index":1,"sheetId":5}}]}"#)
        // Deleting by id needs no metadata fetch.
        XCTAssertTrue(transport.requests(urlContains: "/spreadsheets/sheet-1?").isEmpty)
    }

    func testDeleteConditionalFormatRuleRejectsNegativeIndexWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgumentAsync {
            try await client.deleteConditionalFormatRule(
                spreadsheetId: "sheet-1", sheetId: 5, index: -1)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Data validation

    func testSetDataValidationEncodesConditionAndOptions() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(8, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.setDataValidation(
            spreadsheetId: "sheet-1",
            range: "Data!B2:B3",
            type: .oneOfList,
            values: ["Yes", "No"],
            strict: true,
            showCustomUi: true,
            inputMessage: "Pick one")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"setDataValidation":{"range":{"endColumnIndex":2,"endRowIndex":3,"sheetId":8,"startColumnIndex":1,"startRowIndex":1},"rule":{"condition":{"type":"ONE_OF_LIST","values":[{"userEnteredValue":"Yes"},{"userEnteredValue":"No"}]},"inputMessage":"Pick one","showCustomUi":true,"strict":true}}}]}"#
        )
    }

    func testSetDataValidationOmitsUnsetOptions() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(8, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.setDataValidation(
            spreadsheetId: "sheet-1", range: "Data!B2:B3", type: .numberGreater, values: ["5"])

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"setDataValidation":{"range":{"endColumnIndex":2,"endRowIndex":3,"sheetId":8,"startColumnIndex":1,"startRowIndex":1},"rule":{"condition":{"type":"NUMBER_GREATER","values":[{"userEnteredValue":"5"}]}}}}]}"#
        )
    }

    func testClearDataValidationSendsANilRule() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(8, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.clearDataValidation(spreadsheetId: "sheet-1", range: "Data!B2:B3")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // A cleared range carries no `rule` key.
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"setDataValidation":{"range":{"endColumnIndex":2,"endRowIndex":3,"sheetId":8,"startColumnIndex":1,"startRowIndex":1}}}]}"#
        )
    }

    func testSetDataValidationValidatesValueCountWithoutWriting() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalidArgumentAsync {
            try await client.setDataValidation(
                spreadsheetId: "sheet-1", range: "Data!B2:B3", type: .blank, values: ["x"])
        }
        await assertInvalidArgumentAsync {
            try await client.setDataValidation(
                spreadsheetId: "sheet-1", range: "Data!B2:B3", type: .numberBetween, values: ["1"])
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Basic filter and filter views

    func testSetBasicFilterEncodesTheRangeAndFallsBackToFirstSheet() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1"), (4, "Other")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        // No sheet name in the range resolves to the first sheet (id 3).
        try await client.setBasicFilter(spreadsheetId: "sheet-1", range: "A1:D100")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"setBasicFilter":{"filter":{"range":{"endColumnIndex":4,"endRowIndex":100,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}}]}"#
        )
    }

    func testClearBasicFilterEncodesSheetIdWithoutReadingMetadata() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.clearBasicFilter(spreadsheetId: "sheet-1", sheetId: 3)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"clearBasicFilter":{"sheetId":3}}]}"#)
        XCTAssertTrue(transport.requests(urlContains: "/spreadsheets/sheet-1?").isEmpty)
    }

    func testAddFilterViewEncodesTitleAndRangeAndReturnsId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(6, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addFilterView":{"filter":{"filterViewId":123}}}]}"#)

        let id = try await client.addFilterView(
            spreadsheetId: "sheet-1", range: "Data!A1:D100", title: "Q1")

        XCTAssertEqual(id, 123)
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addFilterView":{"filter":{"range":{"endColumnIndex":4,"endRowIndex":100,"sheetId":6,"startColumnIndex":0,"startRowIndex":0},"title":"Q1"}}}]}"#
        )
    }

    func testAddFilterViewRejectsAReplyWithNoId() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(6, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{"addFilterView":{"filter":{}}}]}"#)

        do {
            _ = try await client.addFilterView(
                spreadsheetId: "sheet-1", range: "Data!A1:D100", title: "Q1")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Protected ranges

    func testAddProtectedRangeEncodesEveryFieldAndReturnsId() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(9, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addProtectedRange":{"protectedRange":{"protectedRangeId":55}}}]}"#)

        let id = try await client.addProtectedRange(
            spreadsheetId: "sheet-1",
            range: "Data!A1:D10",
            description: "Locked",
            warningOnly: true)

        XCTAssertEqual(id, 55)
        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addProtectedRange":{"protectedRange":{"description":"Locked","range":{"endColumnIndex":4,"endRowIndex":10,"sheetId":9,"startColumnIndex":0,"startRowIndex":0},"warningOnly":true}}}]}"#
        )
    }

    func testAddProtectedRangeOmitsUnsetFields() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(9, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addProtectedRange":{"protectedRange":{"protectedRangeId":7}}}]}"#)

        _ = try await client.addProtectedRange(spreadsheetId: "sheet-1", range: "Data!A1:D10")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"addProtectedRange":{"protectedRange":{"range":{"endColumnIndex":4,"endRowIndex":10,"sheetId":9,"startColumnIndex":0,"startRowIndex":0}}}}]}"#
        )
    }

    func testAddProtectedRangeRejectsAReplyWithNoId() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(9, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"replies":[{"addProtectedRange":{"protectedRange":{}}}]}"#)

        do {
            _ = try await client.addProtectedRange(spreadsheetId: "sheet-1", range: "Data!A1:D10")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidResponse = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testDeleteProtectedRangeEncodesTheIdWithoutReadingMetadata() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.deleteProtectedRange(spreadsheetId: "sheet-1", protectedRangeId: 55)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.bodyString(request),
            #"{"requests":[{"deleteProtectedRange":{"protectedRangeId":55}}]}"#)
        XCTAssertTrue(transport.requests(urlContains: "/spreadsheets/sheet-1?").isEmpty)
    }

    // MARK: - Error propagation

    func testDeleteProtectedRangePropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"No such range","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        do {
            try await client.deleteProtectedRange(spreadsheetId: "sheet-1", protectedRangeId: 999)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "No such range")
        }
    }

    func testSetDataValidationPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        stubSpreadsheet(transport, sheets: [(8, "Data")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":403,"message":"Denied","status":"PERMISSION_DENIED"}}"#,
            status: 403)

        do {
            try await client.setDataValidation(
                spreadsheetId: "sheet-1", range: "Data!B2:B3", type: .numberGreater, values: ["1"])
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, _, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 403)
            XCTAssertEqual(message, "Denied")
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

    /// Asserts a synchronous throwing body throws ``GrahamError/invalidArgument``.
    private func assertInvalidArgument(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case GrahamError.invalidArgument = error else {
                return XCTFail("Wrong error: \(error)", file: file, line: line)
            }
        }
    }

    /// Asserts an async throwing body throws ``GrahamError/invalidArgument``.
    private func assertInvalidArgumentAsync(
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
