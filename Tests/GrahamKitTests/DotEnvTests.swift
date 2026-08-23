import XCTest
@testable import GrahamKit

final class DotEnvTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("graham-dotenv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeEnv(_ text: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
    }

    func testFindsValueInStartDirectory() throws {
        try writeEnv("MY_KEY=hello", in: root)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: root), "hello")
    }

    func testWalksUpToParentDirectories() throws {
        let child = root.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try writeEnv("MY_KEY=from-root", in: root)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: child), "from-root")
    }

    func testNearestEnvFileWins() throws {
        let child = root.appendingPathComponent("a")
        try writeEnv("MY_KEY=outer", in: root)
        try writeEnv("MY_KEY=inner", in: child)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: child), "inner")
    }

    func testSearchContinuesWhenNearestFileLacksTheKey() throws {
        let child = root.appendingPathComponent("a")
        try writeEnv("MY_KEY=outer", in: root)
        try writeEnv("OTHER_KEY=inner", in: child)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: child), "outer")
    }

    func testSkipsCommentsAndBlankLines() throws {
        try writeEnv("\n# a comment\n\nMY_KEY=value\n", in: root)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: root), "value")
    }

    func testStripsSurroundingQuotes() throws {
        try writeEnv("A=\"double\"\nB='single'\n", in: root)
        XCTAssertEqual(DotEnv.loadValue(forKey: "A", startingIn: root), "double")
        XCTAssertEqual(DotEnv.loadValue(forKey: "B", startingIn: root), "single")
    }

    func testRequiresExactKeyMatch() throws {
        try writeEnv("MY_KEY_EXTRA=wrong\nMY_KEY=right\n", in: root)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: root), "right")
    }

    func testEmptyValueCountsAsNotFound() throws {
        let child = root.appendingPathComponent("a")
        try writeEnv("MY_KEY=outer", in: root)
        try writeEnv("MY_KEY=", in: child)
        XCTAssertEqual(DotEnv.loadValue(forKey: "MY_KEY", startingIn: child), "outer")
    }

    func testReturnsNilWhenNotFound() throws {
        XCTAssertNil(DotEnv.loadValue(forKey: "GRAHAM_TEST_KEY_THAT_DOES_NOT_EXIST", startingIn: root))
    }

    func testEnvironmentBeatsDotEnvFile() throws {
        try writeEnv("MY_KEY=from-file", in: root)
        let value = CredentialsResolver.value(
            forKey: "MY_KEY",
            environment: ["MY_KEY": "from-env"],
            startingIn: root
        )
        XCTAssertEqual(value, "from-env")
    }

    func testResolverFallsBackToDotEnvFile() throws {
        try writeEnv("MY_KEY=from-file", in: root)
        let value = CredentialsResolver.value(forKey: "MY_KEY", environment: [:], startingIn: root)
        XCTAssertEqual(value, "from-file")
    }

    func testResolveThrowsWithoutClientID() throws {
        XCTAssertThrowsError(
            try CredentialsResolver.resolve(environment: [:], startingIn: root)
        ) { error in
            guard case GrahamError.missingCredentials(let key) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(key, CredentialsResolver.clientIDKey)
        }
    }

    func testResolveReadsAllThreeKeys() throws {
        try writeEnv(
            """
            GOOGLE_CLIENT_ID=id
            GOOGLE_CLIENT_SECRET=secret
            GOOGLE_REFRESH_TOKEN=refresh
            """,
            in: root
        )
        let credentials = try CredentialsResolver.resolve(environment: [:], startingIn: root)
        XCTAssertEqual(credentials.clientID, "id")
        XCTAssertEqual(credentials.clientSecret, "secret")
        XCTAssertEqual(credentials.refreshToken, "refresh")
    }
}
