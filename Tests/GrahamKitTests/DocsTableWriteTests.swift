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
final class DocsTableWriteTests: GrahamTestCase {

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
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.deleteTableRow(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    // MARK: - WriteControl

    func testTableOpWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
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
        let client = TestSupport.docsClient(transport)

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
        // Both an index and end-of-segment is ambiguous; rejected, not silently
        // resolved to one.
        await assertInvalid { _ = try await client.insertTable(
            documentId: "doc-1", rows: 2, columns: 2, index: 1, endOfSegment: true) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCellAndSpanValidationSendNothing() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

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
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"bad table","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "bad table") {
            _ = try await client.insertTableColumn(
                documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1, right: true)
        }
    }

    // MARK: - Styling: exact request-union JSON

    /// The three styling cases encode under their own JSON keys, with the style
    /// sub-models and the range/location target nested exactly. This locks the
    /// discriminators, the fields masks, and the zero-based wire indices.
    func testEveryTableStylingRequestTypeEncodesExactly() throws {
        let start = DocsLocation(index: 10)
        let cell = DocsTableCellLocation(tableStartLocation: start, rowIndex: 1, columnIndex: 2)
        let range = DocsTableRange(tableCellLocation: cell, rowSpan: 3, columnSpan: 4)
        let cellStyle = DocsTableCellStyle(
            backgroundColor: DocsOptionalColor(rgb: DocsRgbColor(red: 1, green: 0, blue: 0)),
            contentAlignment: .middle)
        let rowStyle = DocsTableRowStyle(
            minRowHeight: DocsDimension(magnitude: 20, unit: .pt),
            preventOverflow: false)
        let columnProps = DocsTableColumnProperties(
            widthType: .fixedWidth, width: DocsDimension(magnitude: 90, unit: .pt))
        let cases: [(DocsBatchUpdateRequest, String)] = [
            (
                .updateTableCellStyle(DocsUpdateTableCellStyleRequest(
                    tableCellStyle: cellStyle,
                    fields: "backgroundColor,contentAlignment", tableRange: range)),
                #"{"updateTableCellStyle":{"fields":"backgroundColor,contentAlignment","tableCellStyle":{"backgroundColor":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}},"contentAlignment":"MIDDLE"},"tableRange":{"columnSpan":4,"rowSpan":3,"tableCellLocation":{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}}}}"#
            ),
            (
                .updateTableCellStyle(DocsUpdateTableCellStyleRequest(
                    tableCellStyle: DocsTableCellStyle(contentAlignment: .top),
                    fields: "contentAlignment", tableStartLocation: start)),
                #"{"updateTableCellStyle":{"fields":"contentAlignment","tableCellStyle":{"contentAlignment":"TOP"},"tableStartLocation":{"index":10}}}"#
            ),
            (
                .updateTableRowStyle(DocsUpdateTableRowStyleRequest(
                    tableStartLocation: start, rowIndices: [0, 2],
                    tableRowStyle: rowStyle,
                    fields: "minRowHeight,preventOverflow")),
                #"{"updateTableRowStyle":{"fields":"minRowHeight,preventOverflow","rowIndices":[0,2],"tableRowStyle":{"minRowHeight":{"magnitude":20,"unit":"PT"},"preventOverflow":false},"tableStartLocation":{"index":10}}}"#
            ),
            (
                .updateTableColumnProperties(DocsUpdateTableColumnPropertiesRequest(
                    tableStartLocation: start, columnIndices: [1],
                    tableColumnProperties: columnProps, fields: "widthType,width")),
                #"{"updateTableColumnProperties":{"columnIndices":[1],"fields":"widthType,width","tableColumnProperties":{"width":{"magnitude":90,"unit":"PT"},"widthType":"FIXED_WIDTH"},"tableStartLocation":{"index":10}}}"#
            ),
        ]
        for (request, expected) in cases {
            XCTAssertEqual(try encode(request), expected)
        }
    }

    // MARK: - Styling: client bodies

    func testEveryStylingClientMethodPostsItsExactBody() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        for _ in 0..<6 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        // Cell style, whole table, background only (no range -> tableStartLocation).
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10,
            backgroundColor: try DocsOptionalColor.parse("#00FF00"))
        // Cell style, a range with every writable style: the border and padding
        // each fan out to four sides, and the mask lists every provided path.
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10,
            row: 2, column: 3, rowSpan: 2, columnSpan: 2,
            backgroundColor: try DocsOptionalColor.parse("#FF0000"),
            borderColor: try DocsOptionalColor.parse("#0000FF"),
            borderWidth: 2, borderDash: .dash,
            padding: 3, contentAlignment: .middle)
        // Row style, all rows (empty list -> no rowIndices), min height only.
        _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10, minRowHeight: 24)
        // Row style, specific one-based rows -> zero-based, overflow only.
        _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10, rows: [1, 3],
            preventOverflow: false)
        // Column width, specific one-based column -> zero-based, fixed width.
        _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10, columns: [2], width: 90)
        // Column width, all columns (empty -> no columnIndices), evenly distributed.
        _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10, evenlyDistributed: true)

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 6)
        XCTAssertTrue(requests.allSatisfy { $0.method == "POST" })
        XCTAssertTrue(requests.allSatisfy {
            $0.url.absoluteString
                == "https://docs.googleapis.com/v1/documents/doc-1:batchUpdate"
        })

        XCTAssertEqual(
            Self.body(requests[0]),
            #"{"requests":[{"updateTableCellStyle":{"fields":"backgroundColor","tableCellStyle":{"backgroundColor":{"color":{"rgbColor":{"blue":0,"green":1,"red":0}}}},"tableStartLocation":{"index":10}}}]}"#
        )

        // The border and padding repeat identically across all four sides; build
        // the expected body from those pieces so the repetition is unmistakable.
        let border = #"{"color":{"color":{"rgbColor":{"blue":1,"green":0,"red":0}}},"dashStyle":"DASH","width":{"magnitude":2,"unit":"PT"}}"#
        let pad = #"{"magnitude":3,"unit":"PT"}"#
        let cellStyleJSON =
            "{\"backgroundColor\":{\"color\":{\"rgbColor\":{\"blue\":0,\"green\":0,\"red\":1}}},"
            + "\"borderBottom\":\(border),\"borderLeft\":\(border),"
            + "\"borderRight\":\(border),\"borderTop\":\(border),"
            + "\"contentAlignment\":\"MIDDLE\","
            + "\"paddingBottom\":\(pad),\"paddingLeft\":\(pad),"
            + "\"paddingRight\":\(pad),\"paddingTop\":\(pad)}"
        let expectedCellRange =
            "{\"requests\":[{\"updateTableCellStyle\":{"
            + "\"fields\":\"backgroundColor,borderLeft,borderRight,borderTop,borderBottom,"
            + "paddingLeft,paddingRight,paddingTop,paddingBottom,contentAlignment\","
            + "\"tableCellStyle\":\(cellStyleJSON),"
            + "\"tableRange\":{\"columnSpan\":2,\"rowSpan\":2,\"tableCellLocation\":"
            + "{\"columnIndex\":2,\"rowIndex\":1,\"tableStartLocation\":{\"index\":10}}}}}]}"
        XCTAssertEqual(Self.body(requests[1]), expectedCellRange)

        XCTAssertEqual(
            Self.body(requests[2]),
            #"{"requests":[{"updateTableRowStyle":{"fields":"minRowHeight","tableRowStyle":{"minRowHeight":{"magnitude":24,"unit":"PT"}},"tableStartLocation":{"index":10}}}]}"#
        )
        XCTAssertEqual(
            Self.body(requests[3]),
            #"{"requests":[{"updateTableRowStyle":{"fields":"preventOverflow","rowIndices":[0,2],"tableRowStyle":{"preventOverflow":false},"tableStartLocation":{"index":10}}}]}"#
        )
        XCTAssertEqual(
            Self.body(requests[4]),
            #"{"requests":[{"updateTableColumnProperties":{"columnIndices":[1],"fields":"widthType,width","tableColumnProperties":{"width":{"magnitude":90,"unit":"PT"},"widthType":"FIXED_WIDTH"},"tableStartLocation":{"index":10}}}]}"#
        )
        XCTAssertEqual(
            Self.body(requests[5]),
            #"{"requests":[{"updateTableColumnProperties":{"fields":"widthType","tableColumnProperties":{"widthType":"EVENLY_DISTRIBUTED"},"tableStartLocation":{"index":10}}}]}"#
        )
    }

    // MARK: - Styling: whole-table vs range, defaults

    func testCellStyleWholeTableUsesStartLocationNotARange() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // No row/column: the whole table is styled through a tableStartLocation,
        // never a tableRange.
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 7, contentAlignment: .bottom)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"updateTableCellStyle":{"fields":"contentAlignment","tableCellStyle":{"contentAlignment":"BOTTOM"},"tableStartLocation":{"index":7}}}]}"#
        )
    }

    func testCellStyleRangeDefaultsSpansToOne() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // A cell with a row and column but no spans styles a single cell: the
        // spans default to 1.
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, column: 1,
            backgroundColor: try DocsOptionalColor.parse("#123456"))

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"updateTableCellStyle":{"fields":"backgroundColor","tableCellStyle":{"backgroundColor":{"color":{"rgbColor":{"blue":0.33725490196078434,"green":0.20392156862745098,"red":0.07058823529411765}}}},"tableRange":{"columnSpan":1,"rowSpan":1,"tableCellLocation":{"columnIndex":0,"rowIndex":0,"tableStartLocation":{"index":10}}}}}]}"#
        )
    }

    func testCellStyleBorderDefaultsWidthOneAndSolidDash() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // --border with no width or dash: the width defaults to 1pt and the dash
        // to solid, and all four border paths are in the mask.
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10,
            borderColor: try DocsOptionalColor.parse("#000000"))

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        let border = #"{"color":{"color":{"rgbColor":{"blue":0,"green":0,"red":0}}},"dashStyle":"SOLID","width":{"magnitude":1,"unit":"PT"}}"#
        let style =
            "{\"borderBottom\":\(border),\"borderLeft\":\(border),"
            + "\"borderRight\":\(border),\"borderTop\":\(border)}"
        XCTAssertEqual(
            Self.body(request),
            "{\"requests\":[{\"updateTableCellStyle\":{"
            + "\"fields\":\"borderLeft,borderRight,borderTop,borderBottom\","
            + "\"tableCellStyle\":\(style),"
            + "\"tableStartLocation\":{\"index\":10}}}]}"
        )
    }

    func testRowStyleWithBothStylesEmitsFullMaskInBuilderOrder() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        // Setting min height and overflow together exercises the full row-style
        // mask, in the fixed builder order. (`tableHeader` is not writable via
        // updateTableRowStyle, so the mask has exactly these two paths.)
        _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10,
            minRowHeight: 18, preventOverflow: true)

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"updateTableRowStyle":{"fields":"minRowHeight,preventOverflow","tableRowStyle":{"minRowHeight":{"magnitude":18,"unit":"PT"},"preventOverflow":true},"tableStartLocation":{"index":10}}}]}"#
        )
    }

    // MARK: - Styling: segment normalization

    func testStylingCarriesSegmentIdAndNormalizesEmptyToBody() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        for _ in 0..<2 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        // A named segment carries onto the tableStartLocation.
        _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 5, evenlyDistributed: true, segmentId: "hdr-1")
        // An empty segment id means the body: no empty segmentId leaks through.
        _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 5, minRowHeight: 10, segmentId: "")

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(
            Self.body(requests[0]),
            #"{"requests":[{"updateTableColumnProperties":{"fields":"widthType","tableColumnProperties":{"widthType":"EVENLY_DISTRIBUTED"},"tableStartLocation":{"index":5,"segmentId":"hdr-1"}}}]}"#
        )
        XCTAssertEqual(
            Self.body(requests[1]),
            #"{"requests":[{"updateTableRowStyle":{"fields":"minRowHeight","tableRowStyle":{"minRowHeight":{"magnitude":10,"unit":"PT"}},"tableStartLocation":{"index":5}}}]}"#
        )
    }

    // MARK: - Styling: empty reply decode

    func testStylingOpDecodesEmptyReply() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: "{}")

        let response = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10, preventOverflow: true)

        XCTAssertNil(response.documentId)
        XCTAssertNil(response.replies)
    }

    // MARK: - Styling: WriteControl

    func testStylingOpWithRequiredRevisionCarriesWriteControl() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{}"#)

        _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10, width: 72, requiredRevisionId: "rev-9")

        let request = try XCTUnwrap(transport.requests(urlContains: ":batchUpdate").first)
        XCTAssertEqual(
            Self.body(request),
            #"{"requests":[{"updateTableColumnProperties":{"fields":"widthType,width","tableColumnProperties":{"width":{"magnitude":72,"unit":"PT"},"widthType":"FIXED_WIDTH"},"tableStartLocation":{"index":10}}}],"writeControl":{"requiredRevisionId":"rev-9"}}"#
        )
    }

    // MARK: - Styling: validation sends nothing

    func testCellStyleValidationSendsNothing() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // No style option at all.
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10) }
        // A cell target with a bad one-based row (a style option is present so the
        // range building is what rejects it).
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 0, column: 1,
            contentAlignment: .top) }
        // Only one of row/column given.
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, row: 1, contentAlignment: .top) }
        // A span without a cell target.
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, rowSpan: 2, contentAlignment: .top) }
        // A border width or dash without a color.
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, borderWidth: 2) }
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, borderDash: .dot) }
        // A negative border width or padding (0 is valid — see the acceptance
        // test below).
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10,
            borderColor: try DocsOptionalColor.parse("#000000"), borderWidth: -1) }
        await assertInvalid { _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, padding: -1) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testCellStyleAcceptsZeroBorderWidthAndZeroPadding() async throws {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        for _ in 0..<2 { transport.stub(urlContains: ":batchUpdate", json: #"{}"#) }

        // A border width of 0 hides the border and is valid: it encodes a border
        // with width 0.
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10,
            borderColor: try DocsOptionalColor.parse("#000000"), borderWidth: 0)
        // A padding of 0 (no padding) is valid too.
        _ = try await client.styleTableCells(
            documentId: "doc-1", tableStartIndex: 10, padding: 0)

        let requests = transport.requests(urlContains: ":batchUpdate")
        let border = #"{"color":{"color":{"rgbColor":{"blue":0,"green":0,"red":0}}},"dashStyle":"SOLID","width":{"magnitude":0,"unit":"PT"}}"#
        XCTAssertEqual(
            Self.body(requests[0]),
            "{\"requests\":[{\"updateTableCellStyle\":{"
            + "\"fields\":\"borderLeft,borderRight,borderTop,borderBottom\","
            + "\"tableCellStyle\":{\"borderBottom\":\(border),\"borderLeft\":\(border),"
            + "\"borderRight\":\(border),\"borderTop\":\(border)},"
            + "\"tableStartLocation\":{\"index\":10}}}]}"
        )
        let pad = #"{"magnitude":0,"unit":"PT"}"#
        XCTAssertEqual(
            Self.body(requests[1]),
            "{\"requests\":[{\"updateTableCellStyle\":{"
            + "\"fields\":\"paddingLeft,paddingRight,paddingTop,paddingBottom\","
            + "\"tableCellStyle\":{\"paddingBottom\":\(pad),\"paddingLeft\":\(pad),"
            + "\"paddingRight\":\(pad),\"paddingTop\":\(pad)},"
            + "\"tableStartLocation\":{\"index\":10}}}]}"
        )
    }

    func testRowStyleValidationSendsNothing() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // No style option.
        await assertInvalid { _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10) }
        // A non-positive minimum height.
        await assertInvalid { _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10, minRowHeight: 0) }
        // A bad one-based row number in the list.
        await assertInvalid { _ = try await client.styleTableRow(
            documentId: "doc-1", tableStartIndex: 10, rows: [0], preventOverflow: true) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    func testColumnWidthValidationSendsNothing() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)

        // Neither a width nor evenly-distributed.
        await assertInvalid { _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10) }
        // Both a width and evenly-distributed.
        await assertInvalid { _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10, width: 90, evenlyDistributed: true) }
        // A fixed width below the 5-point minimum.
        await assertInvalid { _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10, width: 4) }
        // A bad one-based column number in the list.
        await assertInvalid { _ = try await client.styleTableColumnWidth(
            documentId: "doc-1", tableStartIndex: 10, columns: [0], width: 90) }

        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - Styling: error propagation

    func testStylingMethodPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        let client = TestSupport.docsClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"bad style","status":"INVALID_ARGUMENT"}}"#,
            status: 400)

        await assertGoogleError(code: 400, status: "INVALID_ARGUMENT", message: "bad style") {
            _ = try await client.styleTableCells(
                documentId: "doc-1", tableStartIndex: 10, contentAlignment: .top)
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


    private func encode(_ request: DocsBatchUpdateRequest) throws -> String {
        String(data: try GoogleJSON.encoder.encode(request), encoding: .utf8) ?? ""
    }

    private static func body(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
