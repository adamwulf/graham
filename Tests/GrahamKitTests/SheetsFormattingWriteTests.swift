import XCTest
@testable import GrahamKit

/// Offline coverage for the Sheets "more formatting" write paths: the extended
/// `formatCells` (clear/toggle, number type, text color/font, non-deprecated
/// color styles) and the new `setBorders` (`updateBorders`) operation.
final class SheetsFormattingWriteTests: GrahamTestCase {

    // MARK: - Toggle and clear

    func testFormatNoBoldSetsBoldFalseWithSameMask() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.formatCells(spreadsheetId: "sheet-1", range: "A1:B1", bold: false)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"repeatCell":{"cell":{"userEnteredFormat":{"textFormat":{"bold":false}}},"fields":"userEnteredFormat.textFormat.bold","range":{"endColumnIndex":2,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    func testFormatClearsResetAspectsWithMaskedEmptyPayload() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.formatCells(
            spreadsheetId: "sheet-1",
            range: "A1:B1",
            clearBackground: true,
            clearNumberFormat: true,
            clearAlignment: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        // Every cleared aspect keeps its mask path but sends no value, so the
        // cell's userEnteredFormat is an empty object.
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"repeatCell":{"cell":{"userEnteredFormat":{}},"fields":"userEnteredFormat.backgroundColorStyle,userEnteredFormat.numberFormat,userEnteredFormat.horizontalAlignment","range":{"endColumnIndex":2,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    func testFormatRejectsSettingAndClearingTheSameAspectWithoutWriting() async {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)

        await assertInvalidArgument {
            try await client.formatCells(
                spreadsheetId: "sheet-1", range: "A1:B1",
                backgroundColor: try SheetsColor.parse("#FFFFFF"), clearBackground: true)
        }
        await assertInvalidArgument {
            try await client.formatCells(
                spreadsheetId: "sheet-1", range: "A1:B1",
                numberFormat: "#,##0", clearNumberFormat: true)
        }
        await assertInvalidArgument {
            try await client.formatCells(
                spreadsheetId: "sheet-1", range: "A1:B1",
                horizontalAlignment: .center, clearAlignment: true)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFormatRejectsNonPositiveFontSizeWithoutWriting() async {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)

        await assertInvalidArgument {
            try await client.formatCells(spreadsheetId: "sheet-1", range: "A1:B1", fontSize: 0)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Background color style

    func testFormatBackgroundWritesNonDeprecatedColorStyle() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.formatCells(
            spreadsheetId: "sheet-1", range: "A1:B1",
            backgroundColor: try SheetsColor.parse("#00FF00"))

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"repeatCell":{"cell":{"userEnteredFormat":{"backgroundColorStyle":{"rgbColor":{"blue":0,"green":1,"red":0}}}},"fields":"userEnteredFormat.backgroundColorStyle","range":{"endColumnIndex":2,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    // MARK: - Number format type

    func testFormatNumberTypeSetsExplicitTypeWithPattern() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.formatCells(
            spreadsheetId: "sheet-1", range: "A1:B1",
            numberFormat: "#,##0", numberFormatType: .currency)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            ##"{"requests":[{"repeatCell":{"cell":{"userEnteredFormat":{"numberFormat":{"pattern":"#,##0","type":"CURRENCY"}}},"fields":"userEnteredFormat.numberFormat","range":{"endColumnIndex":2,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"##
        )
    }

    func testFormatNumberTypeWithoutPatternOmitsPattern() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.formatCells(
            spreadsheetId: "sheet-1", range: "A1:B1", numberFormatType: .percent)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"repeatCell":{"cell":{"userEnteredFormat":{"numberFormat":{"type":"PERCENT"}}},"fields":"userEnteredFormat.numberFormat","range":{"endColumnIndex":2,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    // MARK: - Text color and font

    func testFormatTextColorFontAndSizeEncodeMaskedTextFormatFields() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.formatCells(
            spreadsheetId: "sheet-1", range: "A1:B1",
            bold: true,
            textColor: try SheetsColor.parse("#0000FF"),
            fontFamily: "Roboto",
            fontSize: 12)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"repeatCell":{"cell":{"userEnteredFormat":{"textFormat":{"bold":true,"fontFamily":"Roboto","fontSize":12,"foregroundColorStyle":{"rgbColor":{"blue":1,"green":0,"red":0}}}}},"fields":"userEnteredFormat.textFormat.bold,userEnteredFormat.textFormat.foregroundColorStyle,userEnteredFormat.textFormat.fontFamily,userEnteredFormat.textFormat.fontSize","range":{"endColumnIndex":2,"endRowIndex":1,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    // MARK: - Borders

    func testSetBordersEncodesEverySideWithColorAndResolvesSheetName() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(77, "Data")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.setBorders(
            spreadsheetId: "sheet-1",
            range: "Data!A1:B4",
            style: .solid,
            color: try SheetsColor.parse("#000000"),
            top: true, bottom: true, left: true, right: true,
            innerHorizontal: true, innerVertical: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateBorders":{"bottom":{"colorStyle":{"rgbColor":{"blue":0,"green":0,"red":0}},"style":"SOLID"},"innerHorizontal":{"colorStyle":{"rgbColor":{"blue":0,"green":0,"red":0}},"style":"SOLID"},"innerVertical":{"colorStyle":{"rgbColor":{"blue":0,"green":0,"red":0}},"style":"SOLID"},"left":{"colorStyle":{"rgbColor":{"blue":0,"green":0,"red":0}},"style":"SOLID"},"range":{"endColumnIndex":2,"endRowIndex":4,"sheetId":77,"startColumnIndex":0,"startRowIndex":0},"right":{"colorStyle":{"rgbColor":{"blue":0,"green":0,"red":0}},"style":"SOLID"},"top":{"colorStyle":{"rgbColor":{"blue":0,"green":0,"red":0}},"style":"SOLID"}}}]}"#
        )
    }

    func testSetBordersSingleSideOmitsOtherSidesAndColor() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.setBorders(
            spreadsheetId: "sheet-1", range: "A1:B4", style: .solidThick, top: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateBorders":{"range":{"endColumnIndex":2,"endRowIndex":4,"sheetId":3,"startColumnIndex":0,"startRowIndex":0},"top":{"style":"SOLID_THICK"}}}]}"#
        )
    }

    func testSetBordersNoneStyleClearsAChosenSide() async throws {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(urlContains: ":batchUpdate", json: #"{"replies":[{}]}"#)

        try await client.setBorders(
            spreadsheetId: "sheet-1", range: "A1:B4", style: .none, bottom: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            TestSupport.bodyString(request),
            #"{"requests":[{"updateBorders":{"bottom":{"style":"NONE"},"range":{"endColumnIndex":2,"endRowIndex":4,"sheetId":3,"startColumnIndex":0,"startRowIndex":0}}}]}"#
        )
    }

    func testSetBordersRejectsNoSidesWithoutWriting() async {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)

        await assertInvalidArgument {
            try await client.setBorders(spreadsheetId: "sheet-1", range: "A1:B4", style: .solid)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSetBordersPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = TestSupport.sheetsClient(transport)
        stubSpreadsheet(transport, sheets: [(3, "Sheet1")])
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"Bad borders","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        do {
            try await client.setBorders(
                spreadsheetId: "sheet-1", range: "A1:B4", style: .solid, top: true)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "Bad borders")
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


}
