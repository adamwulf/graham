import XCTest
@testable import GrahamKit

final class GrahamErrorTests: XCTestCase {
    private struct RequiredID: Decodable {
        let id: String
    }

    private struct NumericPayload: Decodable {
        let count: Int
    }

    private struct NestedPayload: Decodable {
        let items: [NumericPayload]
    }

    private enum FallbackError: Error, CustomStringConvertible {
        case sentinel

        var description: String { "sentinel fallback" }
    }

    func testDecodingDetailNamesMissingRequiredKeyAtRoot() {
        let detail = decodingDetail(RequiredID.self, json: #"{}"#)

        XCTAssertTrue(detail.contains("id"))
        XCTAssertTrue(detail.contains("(root)"))
    }

    func testDecodingDetailNamesTypeMismatchPath() {
        let detail = decodingDetail(NumericPayload.self, json: #"{"count":"many"}"#)

        XCTAssertTrue(detail.contains("count"))
    }

    func testDecodingDetailNamesMissingValuePath() {
        let detail = decodingDetail(NumericPayload.self, json: #"{"count":null}"#)

        XCTAssertTrue(detail.contains("count"))
    }

    func testDecodingDetailNamesNestedArrayIndexPath() {
        let detail = decodingDetail(
            NestedPayload.self,
            json: #"{"items":[{"count":"many"}]}"#
        )

        XCTAssertTrue(detail.contains("items"))
        XCTAssertTrue(detail.contains("[0]"))
        XCTAssertTrue(detail.contains("count"))
    }

    func testDecodingDetailNamesRootForCorruptedPayload() {
        let detail = decodingDetail(RequiredID.self, json: #"{"id":"unfinished"#)

        XCTAssertTrue(detail.contains("(root)"))
    }

    func testDecodingDetailFallsBackForNonDecodingError() {
        let detail = GrahamError.decodingDetail(FallbackError.sentinel)

        XCTAssertTrue(detail.contains("sentinel fallback"))
    }

    private func decodingDetail<Value: Decodable>(
        _ type: Value.Type,
        json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        do {
            _ = try GoogleJSON.decoder.decode(Value.self, from: Data(json.utf8))
            XCTFail("Expected decoding to fail", file: file, line: line)
            return ""
        } catch {
            return GrahamError.decodingDetail(error)
        }
    }
}
