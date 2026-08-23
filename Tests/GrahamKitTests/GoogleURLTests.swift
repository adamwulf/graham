import XCTest
@testable import GrahamKit

final class GoogleURLTests: XCTestCase {
    func testBuildsQueryInOrder() throws {
        let url = try GoogleURL.build("https://example.com/path", query: [
            ("b", "2"),
            ("a", "1"),
        ])
        XCTAssertEqual(url.absoluteString, "https://example.com/path?b=2&a=1")
    }

    func testDropsNilParameters() throws {
        let url = try GoogleURL.build("https://example.com/path", query: [
            ("a", "1"),
            ("b", nil),
        ])
        XCTAssertEqual(url.absoluteString, "https://example.com/path?a=1")
    }

    func testNoQueryParametersMeansNoQuestionMark() throws {
        let url = try GoogleURL.build("https://example.com/path")
        XCTAssertEqual(url.absoluteString, "https://example.com/path")
    }

    func testEscapesPlusInQueryValues() throws {
        // URLComponents leaves "+" unescaped, but the server reads "+" as a
        // space. Page tokens are base64-like, so this must not happen.
        let url = try GoogleURL.build("https://example.com/files", query: [
            ("pageToken", "abc+def=="),
        ])
        XCTAssertEqual(url.query?.contains("abc%2Bdef"), true)
        XCTAssertFalse(url.absoluteString.contains("abc+def"))
    }

    func testEscapesSpacesInQueryValues() throws {
        let url = try GoogleURL.build("https://example.com/files", query: [
            ("q", "name contains 'report'"),
        ])
        XCTAssertEqual(url.query?.contains("name%20contains"), true)
    }

    func testEscapePathComponentKeepsA1Notation() {
        XCTAssertEqual(GoogleURL.escapePathComponent("Sheet1!A1:B2"), "Sheet1!A1:B2")
    }

    func testEscapePathComponentEscapesSpacesAndSlashes() {
        XCTAssertEqual(GoogleURL.escapePathComponent("My Sheet/1"), "My%20Sheet%2F1")
    }
}
