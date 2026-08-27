import XCTest
@testable import GrahamKit

final class GoogleScopeTests: XCTestCase {
    func testShortNamesRoundTripForEveryScope() {
        let expected: [(scope: GoogleScope, shortName: String)] = [
            (.drive, "drive"),
            (.driveReadonly, "drive-readonly"),
            (.spreadsheets, "sheets"),
            (.documents, "docs"),
            (.presentations, "slides"),
        ]

        XCTAssertEqual(GoogleScope.allCases.count, expected.count)
        for (scope, shortName) in expected {
            XCTAssertEqual(scope.shortName, shortName)
            XCTAssertEqual(GoogleScope(shortName: shortName), scope)
        }
        XCTAssertNil(GoogleScope(shortName: "unknown"))
    }
}
