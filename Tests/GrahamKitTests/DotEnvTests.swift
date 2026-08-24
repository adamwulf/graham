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

    private func readEnv(in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(".env"), encoding: .utf8)
    }

    func testSetValueAppendsWhenKeyIsAbsent() throws {
        try writeEnv("GOOGLE_CLIENT_ID=id\nGOOGLE_CLIENT_SECRET=secret\n", in: root)
        let url = try DotEnv.setValue("refresh", forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root)
        XCTAssertEqual(url, root.appendingPathComponent(".env"))
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root), "refresh")
        // The existing keys stay intact.
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_CLIENT_ID", startingIn: root), "id")
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_CLIENT_SECRET", startingIn: root), "secret")
    }

    func testSetValueReplacesExistingKeyWithoutDuplicate() throws {
        try writeEnv("GOOGLE_CLIENT_ID=id\nGOOGLE_REFRESH_TOKEN=old\n", in: root)
        try DotEnv.setValue("new", forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root)
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root), "new")
        let contents = try readEnv(in: root)
        let occurrences = contents.components(separatedBy: "GOOGLE_REFRESH_TOKEN=").count - 1
        XCTAssertEqual(occurrences, 1, "The key must appear exactly once after a replace.")
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_CLIENT_ID", startingIn: root), "id")
    }

    func testSetValueRemovesDuplicateKeyLines() throws {
        try writeEnv("GOOGLE_REFRESH_TOKEN=a\nOTHER=x\nGOOGLE_REFRESH_TOKEN=b\n", in: root)
        try DotEnv.setValue("c", forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root)
        let contents = try readEnv(in: root)
        let occurrences = contents.components(separatedBy: "GOOGLE_REFRESH_TOKEN=").count - 1
        XCTAssertEqual(occurrences, 1)
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root), "c")
        XCTAssertEqual(DotEnv.loadValue(forKey: "OTHER", startingIn: root), "x")
    }

    func testSetValueWritesToNearestExistingFileWalkingUp() throws {
        let child = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try writeEnv("GOOGLE_CLIENT_ID=id\n", in: root)
        let url = try DotEnv.setValue("refresh", forKey: "GOOGLE_REFRESH_TOKEN", startingIn: child)
        XCTAssertEqual(url, root.appendingPathComponent(".env"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: child.appendingPathComponent(".env").path),
            "No new .env should be created in the child directory.")
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_REFRESH_TOKEN", startingIn: child), "refresh")
    }

    func testSetValueCreatesFileWhenNoneExists() throws {
        let url = try DotEnv.setValue("refresh", forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root)
        XCTAssertEqual(url, root.appendingPathComponent(".env"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root), "refresh")
    }

    func testSetValuePreservesCommentsAndBlankLines() throws {
        try writeEnv("# my creds\n\nGOOGLE_CLIENT_ID=id\n", in: root)
        try DotEnv.setValue("refresh", forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root)
        let contents = try readEnv(in: root)
        XCTAssertTrue(contents.contains("# my creds"))
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_CLIENT_ID", startingIn: root), "id")
        XCTAssertEqual(DotEnv.loadValue(forKey: "GOOGLE_REFRESH_TOKEN", startingIn: root), "refresh")
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
