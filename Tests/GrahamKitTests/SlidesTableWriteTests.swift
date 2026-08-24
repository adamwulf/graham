import XCTest
@testable import GrahamKit

/// Offline coverage for Slides table structure and appearance writes.
final class SlidesTableWriteTests: XCTestCase {
    private func makeClient(transport: StubTransport) -> SlidesClient {
        transport.stubTokenEndpoint()
        return SlidesClient(api: TestSupport.makeAPI(transport: transport))
    }

    // MARK: - Exact request-union JSON

    func testEveryTableRequestTypeEncodesExactly() throws {
        let location = TableCellLocation(rowIndex: 1, columnIndex: 2)
        let range = TableRange(location: location, rowSpan: 3, columnSpan: 4)
        let cases: [(SlidesBatchUpdateRequest, String)] = [
            (
                .insertTableRows(InsertTableRowsRequest(
                    tableObjectId: "t", cellLocation: TableCellLocation(rowIndex: 1),
                    number: 2, insertBelow: false)),
                #"{"insertTableRows":{"cellLocation":{"rowIndex":1},"insertBelow":false,"number":2,"tableObjectId":"t"}}"#
            ),
            (
                .insertTableColumns(InsertTableColumnsRequest(
                    tableObjectId: "t", cellLocation: TableCellLocation(columnIndex: 2),
                    number: 3, insertRight: true)),
                #"{"insertTableColumns":{"cellLocation":{"columnIndex":2},"insertRight":true,"number":3,"tableObjectId":"t"}}"#
            ),
            (
                .deleteTableRow(DeleteTableRowRequest(
                    tableObjectId: "t", cellLocation: TableCellLocation(rowIndex: 1))),
                #"{"deleteTableRow":{"cellLocation":{"rowIndex":1},"tableObjectId":"t"}}"#
            ),
            (
                .deleteTableColumn(DeleteTableColumnRequest(
                    tableObjectId: "t", cellLocation: TableCellLocation(columnIndex: 2))),
                #"{"deleteTableColumn":{"cellLocation":{"columnIndex":2},"tableObjectId":"t"}}"#
            ),
            (
                .mergeTableCells(MergeTableCellsRequest(objectId: "t", tableRange: range)),
                #"{"mergeTableCells":{"objectId":"t","tableRange":{"columnSpan":4,"location":{"columnIndex":2,"rowIndex":1},"rowSpan":3}}}"#
            ),
            (
                .unmergeTableCells(UnmergeTableCellsRequest(objectId: "t", tableRange: range)),
                #"{"unmergeTableCells":{"objectId":"t","tableRange":{"columnSpan":4,"location":{"columnIndex":2,"rowIndex":1},"rowSpan":3}}}"#
            ),
            (
                .updateTableCellProperties(UpdateTableCellPropertiesRequest(
                    objectId: "t",
                    tableCellStyle: TableCellStyle(
                        tableCellBackgroundFill: TableCellBackgroundFill(
                            solidFill: SolidFill(
                                color: OpaqueColor(theme: .accent1), alpha: 0.5)),
                        contentAlignment: .middle),
                    fields: "tableCellBackgroundFill.solidFill.color,tableCellBackgroundFill.solidFill.alpha,contentAlignment")),
                #"{"updateTableCellProperties":{"fields":"tableCellBackgroundFill.solidFill.color,tableCellBackgroundFill.solidFill.alpha,contentAlignment","objectId":"t","tableCellProperties":{"contentAlignment":"MIDDLE","tableCellBackgroundFill":{"solidFill":{"alpha":0.5,"color":{"themeColor":"ACCENT1"}}}}}}"#
            ),
            (
                .updateTableRowProperties(UpdateTableRowPropertiesRequest(
                    objectId: "t", rowIndices: [],
                    tableRowStyle: TableRowStyle(
                        minRowHeight: ElementDimension(magnitude: 24, unit: .pt)),
                    fields: "minRowHeight")),
                #"{"updateTableRowProperties":{"fields":"minRowHeight","objectId":"t","rowIndices":[],"tableRowProperties":{"minRowHeight":{"magnitude":24,"unit":"PT"}}}}"#
            ),
            (
                .updateTableColumnProperties(UpdateTableColumnPropertiesRequest(
                    objectId: "t", columnIndices: [0, 2],
                    tableColumnStyle: TableColumnStyle(
                        columnWidth: ElementDimension(magnitude: 72, unit: .pt)),
                    fields: "columnWidth")),
                #"{"updateTableColumnProperties":{"columnIndices":[0,2],"fields":"columnWidth","objectId":"t","tableColumnProperties":{"columnWidth":{"magnitude":72,"unit":"PT"}}}}"#
            ),
            (
                .updateTableBorderProperties(UpdateTableBorderPropertiesRequest(
                    objectId: "t", tableRange: range,
                    borderPosition: .innerHorizontal,
                    tableBorderStyle: TableBorderStyle(
                        tableBorderFill: TableBorderFill(solidFill: SolidFill(
                            color: OpaqueColor(red: 1, green: 0, blue: 0), alpha: 0.75)),
                        weight: ElementDimension(magnitude: 2, unit: .pt),
                        dashStyle: .dashDot),
                    fields: "tableBorderFill.solidFill.color,tableBorderFill.solidFill.alpha,weight,dashStyle")),
                #"{"updateTableBorderProperties":{"borderPosition":"INNER_HORIZONTAL","fields":"tableBorderFill.solidFill.color,tableBorderFill.solidFill.alpha,weight,dashStyle","objectId":"t","tableBorderProperties":{"dashStyle":"DASH_DOT","tableBorderFill":{"solidFill":{"alpha":0.75,"color":{"rgbColor":{"blue":0,"green":0,"red":1}}}},"weight":{"magnitude":2,"unit":"PT"}},"tableRange":{"columnSpan":4,"location":{"columnIndex":2,"rowIndex":1},"rowSpan":3}}}"#
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
        for _ in 0..<10 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        try await client.insertTableRows(
            presentationId: "deck", tableId: "table", row: 2, below: false, count: 2)
        try await client.insertTableColumns(
            presentationId: "deck", tableId: "table", column: 3, right: true, count: 2)
        try await client.deleteTableRow(presentationId: "deck", tableId: "table", row: 2)
        try await client.deleteTableColumn(
            presentationId: "deck", tableId: "table", column: 3)
        try await client.mergeTableCells(
            presentationId: "deck", tableId: "table", row: 2, column: 3,
            rowSpan: 2, columnSpan: 3)
        try await client.unmergeTableCells(
            presentationId: "deck", tableId: "table", row: 1, column: 1,
            rowSpan: 2, columnSpan: 2)
        try await client.styleTableCells(
            presentationId: "deck", tableId: "table", fillColor: OpaqueColor(theme: .accent2),
            fillAlpha: 0.4, alignment: .bottom)
        try await client.setTableRowHeight(
            presentationId: "deck", tableId: "table", rows: [], minHeight: 20)
        try await client.setTableColumnWidth(
            presentationId: "deck", tableId: "table", columns: [1, 3], width: 64)
        try await client.styleTableBorders(
            presentationId: "deck", tableId: "table", row: 2, column: 3,
            rowSpan: 2, columnSpan: 4, position: .innerHorizontal,
            color: OpaqueColor(theme: .accent1), alpha: 0.5, weight: 1.5, dash: .dash)

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 10)
        XCTAssertTrue(requests.allSatisfy { $0.method == "POST" })
        XCTAssertTrue(requests.allSatisfy {
            URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.path
                == "/v1/presentations/deck:batchUpdate"
        })
        XCTAssertEqual(Self.body(requests[0]), #"{"requests":[{"insertTableRows":{"cellLocation":{"rowIndex":1},"insertBelow":false,"number":2,"tableObjectId":"table"}}]}"#)
        XCTAssertEqual(Self.body(requests[1]), #"{"requests":[{"insertTableColumns":{"cellLocation":{"columnIndex":2},"insertRight":true,"number":2,"tableObjectId":"table"}}]}"#)
        XCTAssertEqual(Self.body(requests[2]), #"{"requests":[{"deleteTableRow":{"cellLocation":{"rowIndex":1},"tableObjectId":"table"}}]}"#)
        XCTAssertEqual(Self.body(requests[3]), #"{"requests":[{"deleteTableColumn":{"cellLocation":{"columnIndex":2},"tableObjectId":"table"}}]}"#)
        XCTAssertEqual(Self.body(requests[4]), #"{"requests":[{"mergeTableCells":{"objectId":"table","tableRange":{"columnSpan":3,"location":{"columnIndex":2,"rowIndex":1},"rowSpan":2}}}]}"#)
        XCTAssertEqual(Self.body(requests[5]), #"{"requests":[{"unmergeTableCells":{"objectId":"table","tableRange":{"columnSpan":2,"location":{"columnIndex":0,"rowIndex":0},"rowSpan":2}}}]}"#)
        XCTAssertEqual(Self.body(requests[6]), #"{"requests":[{"updateTableCellProperties":{"fields":"tableCellBackgroundFill.solidFill.color,tableCellBackgroundFill.solidFill.alpha,contentAlignment","objectId":"table","tableCellProperties":{"contentAlignment":"BOTTOM","tableCellBackgroundFill":{"solidFill":{"alpha":0.4,"color":{"themeColor":"ACCENT2"}}}}}}]}"#)
        XCTAssertFalse(Self.body(requests[6]).contains("tableRange"))
        XCTAssertEqual(Self.body(requests[7]), #"{"requests":[{"updateTableRowProperties":{"fields":"minRowHeight","objectId":"table","rowIndices":[],"tableRowProperties":{"minRowHeight":{"magnitude":20,"unit":"PT"}}}}]}"#)
        XCTAssertEqual(Self.body(requests[8]), #"{"requests":[{"updateTableColumnProperties":{"columnIndices":[0,2],"fields":"columnWidth","objectId":"table","tableColumnProperties":{"columnWidth":{"magnitude":64,"unit":"PT"}}}}]}"#)
        XCTAssertEqual(Self.body(requests[9]), #"{"requests":[{"updateTableBorderProperties":{"borderPosition":"INNER_HORIZONTAL","fields":"tableBorderFill.solidFill.color,tableBorderFill.solidFill.alpha,weight,dashStyle","objectId":"table","tableBorderProperties":{"dashStyle":"DASH","tableBorderFill":{"solidFill":{"alpha":0.5,"color":{"themeColor":"ACCENT1"}}},"weight":{"magnitude":1.5,"unit":"PT"}},"tableRange":{"columnSpan":4,"location":{"columnIndex":2,"rowIndex":1},"rowSpan":2}}}]}"#)
    }

    func testStyleTableCellsNoFillAndDefaultedRangeSpansEncodeExactly() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        try await client.styleTableCells(
            presentationId: "deck", tableId: "table", noFill: true)
        try await client.styleTableCells(
            presentationId: "deck", tableId: "table", row: 2, column: 3,
            alignment: .top)

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(Self.body(requests[0]), #"{"requests":[{"updateTableCellProperties":{"fields":"tableCellBackgroundFill.propertyState","objectId":"table","tableCellProperties":{"tableCellBackgroundFill":{"propertyState":"NOT_RENDERED"}}}}]}"#)
        XCTAssertEqual(Self.body(requests[1]), #"{"requests":[{"updateTableCellProperties":{"fields":"contentAlignment","objectId":"table","tableCellProperties":{"contentAlignment":"TOP"},"tableRange":{"columnSpan":1,"location":{"columnIndex":2,"rowIndex":1},"rowSpan":1}}}]}"#)
    }

    // MARK: - Validation and error behavior

    func testOneBasedCountSpanAndWidthValidationSendNothing() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalid { try await client.deleteTableRow(
            presentationId: "deck", tableId: "table", row: 0) }
        await assertInvalid { try await client.deleteTableColumn(
            presentationId: "deck", tableId: "table", column: 0) }
        await assertInvalid { try await client.insertTableRows(
            presentationId: "deck", tableId: "table", row: 1, count: 21) }
        await assertInvalid { try await client.mergeTableCells(
            presentationId: "deck", tableId: "table", row: 1, column: 1,
            rowSpan: 0, columnSpan: 1) }
        await assertInvalid { try await client.setTableColumnWidth(
            presentationId: "deck", tableId: "table", columns: [], width: 31) }
        await assertInvalid { try await client.setTableRowHeight(
            presentationId: "deck", tableId: "table", rows: [0], minHeight: 20) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testRangeGroupsEmptyMasksAndNoFillExclusivitySendNothing() async {
        let transport = StubTransport()
        let client = makeClient(transport: transport)

        await assertInvalid { try await client.styleTableCells(
            presentationId: "deck", tableId: "table") }
        await assertInvalid { try await client.styleTableBorders(
            presentationId: "deck", tableId: "table") }
        await assertInvalid { try await client.styleTableCells(
            presentationId: "deck", tableId: "table", rowSpan: 2, noFill: true) }
        await assertInvalid { try await client.styleTableBorders(
            presentationId: "deck", tableId: "table", row: 1, color: OpaqueColor(theme: .accent1)) }
        await assertInvalid { try await client.styleTableCells(
            presentationId: "deck", tableId: "table", fillColor: OpaqueColor(theme: .accent1),
            noFill: true) }
        await assertInvalid { try await client.styleTableBorders(
            presentationId: "deck", tableId: "table", alpha: 1.1) }
        await assertInvalid { try await client.styleTableCells(
            presentationId: "deck", tableId: "table", fillAlpha: -0.1) }
        await assertInvalid { try await client.styleTableBorders(
            presentationId: "deck", tableId: "table", weight: 0) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testTableMethodPropagatesGoogleErrorEnvelope() async throws {
        let transport = StubTransport()
        let client = makeClient(transport: transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"bad table","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        do {
            try await client.insertTableColumns(
                presentationId: "deck", tableId: "table", column: 1)
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.googleAPIError(let code, let status, let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "bad table")
        }
    }

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

    private func encode(_ request: SlidesBatchUpdateRequest) throws -> String {
        String(data: try GoogleJSON.encoder.encode(request), encoding: .utf8) ?? ""
    }

    private static func body(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
