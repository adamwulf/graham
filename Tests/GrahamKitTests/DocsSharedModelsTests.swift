import XCTest
@testable import GrahamKit

/// Encoding coverage for the shared Docs write locations that later phases
/// build on: `DocsLocation`, `DocsRange`, `DocsEndOfSegmentLocation`,
/// `DocsTableCellLocation`, and `DocsTableRange`. The shared encoder sorts
/// keys, so every expected string is deterministic. Each optional (`segmentId`,
/// `tabId`) is asserted to encode only when set, so the common body location
/// stays minimal.
final class DocsSharedModelsTests: XCTestCase {
    private func encoded<T: Encodable>(_ value: T) throws -> String {
        String(data: try GoogleJSON.encoder.encode(value), encoding: .utf8) ?? ""
    }

    // MARK: - DocsLocation

    func testLocationEncodesIndexOnlyWhenSegmentAndTabAreNil() throws {
        XCTAssertEqual(try encoded(DocsLocation(index: 5)), #"{"index":5}"#)
    }

    func testLocationEncodesSegmentIdWhenSet() throws {
        XCTAssertEqual(
            try encoded(DocsLocation(index: 5, segmentId: "hdr-1")),
            #"{"index":5,"segmentId":"hdr-1"}"#
        )
    }

    func testLocationEncodesTabIdWhenSet() throws {
        XCTAssertEqual(
            try encoded(DocsLocation(index: 5, tabId: "tab-1")),
            #"{"index":5,"tabId":"tab-1"}"#
        )
    }

    func testLocationEncodesSegmentAndTabTogether() throws {
        XCTAssertEqual(
            try encoded(DocsLocation(index: 0, segmentId: "ftr-2", tabId: "tab-3")),
            #"{"index":0,"segmentId":"ftr-2","tabId":"tab-3"}"#
        )
    }

    // MARK: - DocsRange

    func testRangeEncodesBoundsOnlyWhenSegmentAndTabAreNil() throws {
        XCTAssertEqual(
            try encoded(DocsRange(startIndex: 5, endIndex: 12)),
            #"{"endIndex":12,"startIndex":5}"#
        )
    }

    func testRangeEncodesSegmentAndTabWhenSet() throws {
        XCTAssertEqual(
            try encoded(DocsRange(startIndex: 1, endIndex: 4, segmentId: "ftn-9", tabId: "tab-4")),
            #"{"endIndex":4,"segmentId":"ftn-9","startIndex":1,"tabId":"tab-4"}"#
        )
    }

    // MARK: - DocsEndOfSegmentLocation

    func testEndOfSegmentEncodesEmptyObjectForTheBody() throws {
        XCTAssertEqual(try encoded(DocsEndOfSegmentLocation()), "{}")
    }

    func testEndOfSegmentEncodesSegmentIdWhenSet() throws {
        XCTAssertEqual(
            try encoded(DocsEndOfSegmentLocation(segmentId: "hdr-7")),
            #"{"segmentId":"hdr-7"}"#
        )
    }

    func testEndOfSegmentEncodesTabIdOnlyWhenSet() throws {
        XCTAssertEqual(
            try encoded(DocsEndOfSegmentLocation(tabId: "tab-2")),
            #"{"tabId":"tab-2"}"#
        )
        XCTAssertEqual(
            try encoded(DocsEndOfSegmentLocation(segmentId: "hdr-7", tabId: "tab-2")),
            #"{"segmentId":"hdr-7","tabId":"tab-2"}"#
        )
    }

    // MARK: - DocsTableCellLocation

    func testTableCellLocationEncodesZeroBasedRowAndColumn() throws {
        let location = DocsTableCellLocation(
            tableStartLocation: DocsLocation(index: 10),
            rowIndex: 1,
            columnIndex: 2
        )
        XCTAssertEqual(
            try encoded(location),
            #"{"columnIndex":2,"rowIndex":1,"tableStartLocation":{"index":10}}"#
        )
    }

    // MARK: - DocsTableRange

    func testTableRangeEncodesNestedCellLocationAndSpans() throws {
        let range = DocsTableRange(
            tableCellLocation: DocsTableCellLocation(
                tableStartLocation: DocsLocation(index: 10),
                rowIndex: 0,
                columnIndex: 0
            ),
            rowSpan: 3,
            columnSpan: 2
        )
        XCTAssertEqual(
            try encoded(range),
            #"{"columnSpan":2,"rowSpan":3,"tableCellLocation":{"columnIndex":0,"rowIndex":0,"tableStartLocation":{"index":10}}}"#
        )
    }

    // MARK: - Round trips

    func testEveryLocationRoundTripsThroughCodable() throws {
        let location = DocsLocation(index: 3, segmentId: "s", tabId: "t")
        let range = DocsRange(startIndex: 1, endIndex: 9, segmentId: "s", tabId: "t")
        let end = DocsEndOfSegmentLocation(segmentId: "s")
        let cell = DocsTableCellLocation(
            tableStartLocation: DocsLocation(index: 2), rowIndex: 4, columnIndex: 5)
        let tableRange = DocsTableRange(tableCellLocation: cell, rowSpan: 2, columnSpan: 3)

        XCTAssertEqual(try roundTrip(location), location)
        XCTAssertEqual(try roundTrip(range), range)
        XCTAssertEqual(try roundTrip(end), end)
        XCTAssertEqual(try roundTrip(cell), cell)
        XCTAssertEqual(try roundTrip(tableRange), tableRange)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try GoogleJSON.decoder.decode(T.self, from: GoogleJSON.encoder.encode(value))
    }
}
