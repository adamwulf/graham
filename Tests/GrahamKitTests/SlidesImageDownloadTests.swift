import XCTest
@testable import GrahamKit

/// Tests for image listing, the download seam, safe file names, and the
/// download run. Every download goes through a ``StubTransport`` with static
/// bytes, and every file is written under a fresh temporary directory, so no
/// test touches the network or the user's disk outside `tmp`.
final class SlidesImageDownloadTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("graham-slides-tests-\(ProcessInfo.processInfo.globallyUniqueString)")
        // Deliberately NOT created here: some tests assert that the download
        // creates the directory itself.
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - File extension sniffing

    func testFileExtensionSniffsKnownFormats() {
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Self.png), "png")
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Self.jpeg), "jpg")
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Self.gif), "gif")
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Self.webp), "webp")
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Data([0x42, 0x4D, 0x00])), "bmp")
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Data([0x49, 0x49, 0x2A, 0x00])), "tiff")
    }

    func testFileExtensionFallsBackToBinForUnknownOrShortData() {
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Data([0x00, 0x01, 0x02, 0x03])), "bin")
        // Too short to match any signature.
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Data([0x89])), "bin")
        XCTAssertEqual(SlideImageFile.fileExtension(forBytes: Data()), "bin")
    }

    // MARK: - Safe file names

    func testSanitizeReplacesUnsafeCharactersAndNeverEmpty() {
        // Path separators, dots, spaces, and other punctuation all become "_",
        // so no name can traverse a directory or hide as a dotfile.
        XCTAssertEqual(SlideImageFile.sanitize("g abc/../x"), "g_abc____x")
        XCTAssertEqual(SlideImageFile.sanitize("..;/"), "____")
        XCTAssertEqual(SlideImageFile.sanitize("keeps-OK_09"), "keeps-OK_09")
        // An empty or all-unsafe id still yields a usable stem.
        XCTAssertEqual(SlideImageFile.sanitize(""), "image")
    }

    func testFilenameIsDeterministicSafeAndSequenced() {
        let name = SlideImageFile.filename(
            sequence: 3, slideIndex: 4, objectId: "g:12/ab", fileExtension: "png"
        )
        XCTAssertEqual(name, "003-slide5-g_12_ab.png")
        // No traversal or separators survive.
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(".."))

        // A missing object id still produces a valid, unique-by-sequence name.
        let anon = SlideImageFile.filename(
            sequence: 12, slideIndex: 0, objectId: nil, fileExtension: "bin"
        )
        XCTAssertEqual(anon, "012-slide1-image.bin")
    }

    // MARK: - The download seam

    func testDownloadImageSendsNoAuthorizationHeader() async throws {
        // The content URL is a pre-authorized, short-lived URL on a Google
        // user-content host. Attaching the API bearer would leak the token to
        // that host, so the download must send a plain GET with no auth.
        let transport = StubTransport()
        transport.stub(urlContains: "usercontent", responses: [
            HTTPResponse(statusCode: 200, body: Self.png),
        ])
        let client = SlidesClient(
            api: TestSupport.makeAPI(transport: transport),
            downloadTransport: transport
        )

        let data = try await client.downloadImage(from: "https://lh3.googleusercontent.com/x")

        XCTAssertEqual(data, Self.png)
        let request = try XCTUnwrap(transport.requests(urlContains: "usercontent").first)
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertEqual(request.method, "GET")
    }

    func testDownloadImageThrowsOnHttpError() async {
        let transport = StubTransport()
        transport.stub(urlContains: "usercontent", responses: [
            HTTPResponse(statusCode: 404, body: Data("gone".utf8)),
        ])
        let client = SlidesClient(
            api: TestSupport.makeAPI(transport: transport),
            downloadTransport: transport
        )

        do {
            _ = try await client.downloadImage(from: "https://lh3.googleusercontent.com/missing")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.httpError(let statusCode, _) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(statusCode, 404)
        }
    }

    func testDownloadImageRejectsAMalformedUrl() async {
        let client = SlidesClient(
            api: TestSupport.makeAPI(transport: StubTransport()),
            downloadTransport: StubTransport()
        )
        do {
            _ = try await client.downloadImage(from: "not a url")
            XCTFail("Expected an error")
        } catch {
            guard case GrahamError.invalidURL = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: - The download run

    /// Six images: two known formats, two that share an object id (to exercise
    /// collision-free naming), one with no content URL (skipped), and one that
    /// fails with a 404 (recorded, without stopping the rest).
    private static let downloadJSON = #"""
    {
      "presentationId": "p",
      "slides": [{"objectId": "slide-1", "pageElements": [
        {"objectId": "pngimg", "image": {"contentUrl": "https://c.example/png"}},
        {"objectId": "jpgimg", "image": {"contentUrl": "https://c.example/jpg"}},
        {"objectId": "dup", "image": {"contentUrl": "https://c.example/dup1"}},
        {"objectId": "dup", "image": {"contentUrl": "https://c.example/dup2"}},
        {"objectId": "nourl", "image": {"sourceUrl": "https://example.com/s.png"}},
        {"objectId": "failimg", "image": {"contentUrl": "https://c.example/fail"}}
      ]}]
    }
    """#

    private func makeDownloadClient() -> (SlidesClient, StubTransport) {
        let transport = StubTransport()
        transport.stub(urlContains: "c.example/png", responses: [
            HTTPResponse(statusCode: 200, body: Self.png),
        ])
        transport.stub(urlContains: "c.example/jpg", responses: [
            HTTPResponse(statusCode: 200, body: Self.jpeg),
        ])
        transport.stub(urlContains: "c.example/dup1", responses: [
            HTTPResponse(statusCode: 200, body: Self.gif),
        ])
        transport.stub(urlContains: "c.example/dup2", responses: [
            HTTPResponse(statusCode: 200, body: Self.gif),
        ])
        transport.stub(urlContains: "c.example/fail", responses: [
            HTTPResponse(statusCode: 500, body: Data("boom".utf8)),
        ])
        let client = SlidesClient(
            api: TestSupport.makeAPI(transport: transport),
            downloadTransport: transport
        )
        return (client, transport)
    }

    private func imageRows() throws -> [SlideImageRow] {
        try GoogleJSON.decoder.decode(Presentation.self, from: Data(Self.downloadJSON.utf8)).imageRows
    }

    func testDownloadImagesCreatesTheDirectoryAndWritesFiles() async throws {
        let (client, _) = makeDownloadClient()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // The directory was created on demand.
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // One result per row, in row order.
        XCTAssertEqual(results.map(\.objectId), ["pngimg", "jpgimg", "dup", "dup", "nourl", "failimg"])
    }

    func testDownloadImagesNamesFilesSafelyAndWritesTheBytes() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // The two known formats get sniffed extensions and sequenced names.
        XCTAssertEqual(Self.outcome(results, "pngimg"), .downloaded(filename: "001-slide1-pngimg.png", byteCount: Self.png.count))
        XCTAssertEqual(Self.outcome(results, "jpgimg"), .downloaded(filename: "002-slide1-jpgimg.jpg", byteCount: Self.jpeg.count))

        // The bytes on disk match what the transport returned.
        let pngURL = tempDir.appendingPathComponent("001-slide1-pngimg.png")
        XCTAssertEqual(try Data(contentsOf: pngURL), Self.png)
    }

    func testDownloadImagesAvoidsCollisionsForEqualObjectIds() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // Both "dup" images share an object id but the sequence prefix keeps
        // their file names distinct, so neither overwrites the other.
        let dupResults = results.filter { $0.objectId == "dup" }
        let names = dupResults.compactMap { result -> String? in
            if case let .downloaded(filename, _) = result.outcome { return filename }
            return nil
        }
        XCTAssertEqual(names, ["003-slide1-dup.gif", "004-slide1-dup.gif"])
        XCTAssertEqual(Set(names).count, 2)
        for name in names {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(name).path))
        }
    }

    func testDownloadImagesSkipsRowsWithNoContentUrl() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        XCTAssertEqual(Self.outcome(results, "nourl"), .skipped(reason: "no content URL"))
    }

    func testDownloadImagesRecordsFailuresWithoutStoppingOthers() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // The 500 is recorded as a failure...
        guard case .failed = Self.outcome(results, "failimg") else {
            return XCTFail("failimg should have failed: \(String(describing: Self.outcome(results, "failimg")))")
        }
        // ...yet the images before and after it still succeeded.
        guard case .downloaded = Self.outcome(results, "pngimg") else {
            return XCTFail("pngimg should have downloaded")
        }
        // The failed image left no file behind.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("005-slide1-failimg.bin").path))
    }

    func testDownloadImagesSendsNoAuthorizationOnAnyRequest() async throws {
        let (client, transport) = makeDownloadClient()

        _ = try await client.downloadImages(try imageRows(), to: tempDir)

        let contentRequests = transport.requests(urlContains: "c.example")
        XCTAssertFalse(contentRequests.isEmpty)
        for request in contentRequests {
            XCTAssertNil(request.headers["Authorization"], "download must not carry the API bearer")
        }
    }

    func testDownloadImagesToAnEmptyListJustCreatesTheDirectory() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages([], to: tempDir)

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    // MARK: - Helpers and fixtures

    private static func outcome(_ results: [SlideImageDownloadResult], _ objectId: String) -> SlideImageDownloadOutcome? {
        results.first { $0.objectId == objectId }?.outcome
    }

    /// A minimal but valid PNG signature plus a byte of payload.
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
    /// A JPEG SOI + APP0 marker start.
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    /// A "GIF89a" header.
    static let gif = Data("GIF89a".utf8)
    /// A "RIFF....WEBP" header.
    static let webp = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
}
