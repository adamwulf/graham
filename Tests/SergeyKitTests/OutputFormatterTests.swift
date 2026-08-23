import XCTest
@testable import SergeyKit

private struct TestRow: SergeyRow {
    let id: String
    let name: String

    static var tableColumns: [String] { ["ID", "NAME"] }
    var tableValues: [String] { [id, name] }
    var idValue: String { id }
}

final class OutputFormatterTests: XCTestCase {
    private let rows = [
        TestRow(id: "a1", name: "First"),
        TestRow(id: "b234", name: "Second"),
    ]

    func testTableAlignsColumns() throws {
        let output = try OutputFormatter.render(rows, format: .table)
        XCTAssertEqual(output, """
        ID    NAME
        a1    First
        b234  Second
        """)
    }

    func testTableHasNoTrailingWhitespace() throws {
        let output = try OutputFormatter.render(
            [TestRow(id: "a1", name: "x"), TestRow(id: "b2", name: "longer")],
            format: .table
        )
        for line in output.split(separator: "\n") {
            XCTAssertEqual(line, line.trimmingCharacters(in: .whitespaces)[...])
        }
    }

    func testIdFormatPrintsOneIDPerLine() throws {
        let output = try OutputFormatter.render(rows, format: .id)
        XCTAssertEqual(output, "a1\nb234")
    }

    func testJSONIsPrettyWithSortedKeys() throws {
        let output = try OutputFormatter.render(rows, format: .json)
        XCTAssertTrue(output.hasPrefix("["))
        XCTAssertTrue(output.contains("\"id\" : \"a1\""))
    }

    func testJSONOfEmptyListIsEmptyArray() throws {
        let output = try OutputFormatter.render([TestRow](), format: .json)
        XCTAssertEqual(output.filter { !$0.isWhitespace }, "[]")
    }

    func testJSONLPrintsOneObjectPerLine() throws {
        let output = try OutputFormatter.render(rows, format: .jsonl)
        let lines = output.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], #"{"id":"a1","name":"First"}"#)
        XCTAssertEqual(lines[1], #"{"id":"b234","name":"Second"}"#)
    }
}
