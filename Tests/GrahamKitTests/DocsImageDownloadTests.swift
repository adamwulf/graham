import XCTest
@testable import GrahamKit

/// Offline coverage for `docs images`: the image-list extraction (inline plus
/// positioned) from a document fixture, the no-auth download seam, safe
/// deterministic file names, the download run, and Google error propagation on
/// the API request. Every download goes through a ``StubTransport`` with static
/// bytes, and every file is written under a fresh temporary directory, so no
/// test touches the network or the user's disk outside `tmp`. Mirrors
/// ``SlidesImageDownloadTests``.
final class DocsImageDownloadTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("graham-docs-tests-\(ProcessInfo.processInfo.globallyUniqueString)")
        // Deliberately NOT created here: some tests assert that the download
        // creates the directory itself.
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Image list extraction

    /// A document with two inline images and one positioned image, one of them
    /// carrying a size and both URIs, another only a content URI.
    private static let extractionJSON = #"""
    {
      "documentId": "doc-1",
      "inlineObjects": {
        "kix.b": {"objectId": "kix.b", "inlineObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/b"}
        }}},
        "kix.a": {"objectId": "kix.a", "inlineObjectProperties": {"embeddedObject": {
          "size": {"width": {"magnitude": 120, "unit": "PT"},
                   "height": {"magnitude": 60.4, "unit": "PT"}},
          "imageProperties": {"sourceUri": "https://src/a", "contentUri": "https://c.example/a"}
        }}}
      },
      "positionedObjects": {
        "kix.p": {"objectId": "kix.p", "positionedObjectProperties": {"embeddedObject": {
          "size": {"width": {"magnitude": 200, "unit": "PT"},
                   "height": {"magnitude": 100, "unit": "PT"}},
          "imageProperties": {"sourceUri": "https://src/p", "contentUri": "https://c.example/p"}
        }}}
      }
    }
    """#

    func testImageRowsExtractsInlineThenPositionedInSortedOrder() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(Self.extractionJSON.utf8))
        let rows = document.imageRows

        // Inline images first (sorted by object id: kix.a before kix.b), then
        // positioned images.
        XCTAssertEqual(rows.map(\.objectId), ["kix.a", "kix.b", "kix.p"])
        XCTAssertEqual(rows.map(\.origin), [.inline, .inline, .positioned])

        // The inline image with a size and both URIs is fully extracted.
        let a = rows[0]
        XCTAssertEqual(a.width, 120)
        XCTAssertEqual(a.height, 60.4)
        XCTAssertEqual(a.widthUnit, "PT")
        XCTAssertEqual(a.sourceUri, "https://src/a")
        XCTAssertEqual(a.contentUri, "https://c.example/a")

        // The inline image with only a content URI keeps the rest nil.
        let b = rows[1]
        XCTAssertNil(b.width)
        XCTAssertNil(b.sourceUri)
        XCTAssertEqual(b.contentUri, "https://c.example/b")

        // The positioned image is labelled positioned and fully extracted.
        let p = rows[2]
        XCTAssertEqual(p.origin, .positioned)
        XCTAssertEqual(p.sourceUri, "https://src/p")
        XCTAssertEqual(p.contentUri, "https://c.example/p")
    }

    func testImageRowsIsEmptyWhenTheDocumentHasNoObjects() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(#"{"documentId":"d"}"#.utf8))
        XCTAssertTrue(document.imageRows.isEmpty)
    }

    /// An embedded object without `imageProperties` is a drawing or linked
    /// content, not an image, and must not be listed — otherwise `docs images`
    /// emits a bogus row for a drawing that has no URIs to download.
    private static let drawingJSON = #"""
    {
      "documentId": "doc-1",
      "inlineObjects": {
        "img": {"objectId": "img", "inlineObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/img"}}}},
        "drawing": {"objectId": "drawing", "inlineObjectProperties": {"embeddedObject": {
          "embeddedDrawingProperties": {}}}}
      },
      "positionedObjects": {
        "posdrawing": {"objectId": "posdrawing", "positionedObjectProperties": {"embeddedObject": {
          "embeddedDrawingProperties": {}}}}
      }
    }
    """#

    func testImageRowsExcludesNonImageEmbeddedObjects() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(Self.drawingJSON.utf8))
        // Only the object with image data is listed; the inline and positioned
        // drawings (no imageProperties) are skipped.
        XCTAssertEqual(document.imageRows.map(\.objectId), ["img"])
    }

    func testImageRowRendersSizeInPoints() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(Self.extractionJSON.utf8))
        let rows = document.imageRows
        // 60.4 rounds to 60; a missing size renders empty.
        XCTAssertEqual(rows[0].tableValues, ["inline", "kix.a", "120x60", "https://src/a", "https://c.example/a"])
        XCTAssertEqual(rows[1].tableValues[2], "")
        XCTAssertEqual(rows[0].idValue, "kix.a")
    }

    // MARK: - File extension sniffing

    func testFileExtensionSniffsKnownFormats() {
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Self.png), "png")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Self.jpeg), "jpg")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Self.gif), "gif")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Self.webp), "webp")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Data([0x42, 0x4D, 0x00])), "bmp")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Data([0x49, 0x49, 0x2A, 0x00])), "tiff")
    }

    func testFileExtensionFallsBackToBinForUnknownOrShortData() {
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Data([0x00, 0x01, 0x02, 0x03])), "bin")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Data([0x89])), "bin")
        XCTAssertEqual(DocImageFile.fileExtension(forBytes: Data()), "bin")
    }

    // MARK: - Safe file names

    func testSanitizeReplacesUnsafeCharactersAndNeverEmpty() {
        // Path separators, dots, spaces, and other punctuation all become "_",
        // so no name can traverse a directory or hide as a dotfile.
        XCTAssertEqual(DocImageFile.sanitize("kix.abc/../x"), "kix_abc____x")
        XCTAssertEqual(DocImageFile.sanitize("..;/"), "____")
        XCTAssertEqual(DocImageFile.sanitize("keeps-OK_09"), "keeps-OK_09")
        XCTAssertEqual(DocImageFile.sanitize(""), "image")
    }

    func testFilenameIsDeterministicSafeAndSequenced() {
        let inline = DocImageFile.filename(
            sequence: 3, origin: .inline, objectId: "kix.12/ab", fileExtension: "png")
        XCTAssertEqual(inline, "003-inline-kix_12_ab.png")
        XCTAssertFalse(inline.contains("/"))
        XCTAssertFalse(inline.contains(".."))

        let positioned = DocImageFile.filename(
            sequence: 12, origin: .positioned, objectId: nil, fileExtension: "bin")
        XCTAssertEqual(positioned, "012-positioned-image.bin")
    }

    // MARK: - The download seam

    func testDownloadImageSendsNoAuthorizationHeader() async throws {
        // The content URI is a pre-authorized, short-lived URL on a Google
        // user-content host. Attaching the API bearer would leak the token to
        // that host, so the download must send a plain GET with no auth.
        let transport = StubTransport()
        transport.stub(urlContains: "usercontent", responses: [
            HTTPResponse(statusCode: 200, body: Self.png),
        ])
        let client = DocsClient(
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
        let client = DocsClient(
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
        let client = DocsClient(
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

    /// Six images: two inline known formats, one inline with no content URI
    /// (skipped), one inline that fails with a 500 (recorded, without stopping
    /// the rest), and two positioned images whose object ids sanitize to the
    /// same stem (to exercise collision-free naming).
    private static let downloadJSON = #"""
    {
      "documentId": "doc-1",
      "inlineObjects": {
        "img-a": {"objectId": "img-a", "inlineObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/png"}}}},
        "img-b": {"objectId": "img-b", "inlineObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/jpg"}}}},
        "img-nourl": {"objectId": "img-nourl", "inlineObjectProperties": {"embeddedObject": {
          "imageProperties": {"sourceUri": "https://src/none"}}}},
        "img-zfail": {"objectId": "img-zfail", "inlineObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/fail"}}}}
      },
      "positionedObjects": {
        "pos.dup": {"objectId": "pos.dup", "positionedObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/pos1"}}}},
        "pos:dup": {"objectId": "pos:dup", "positionedObjectProperties": {"embeddedObject": {
          "imageProperties": {"contentUri": "https://c.example/pos2"}}}}
      }
    }
    """#

    private func makeDownloadClient() -> (DocsClient, StubTransport) {
        let transport = StubTransport()
        transport.stub(urlContains: "c.example/png", responses: [
            HTTPResponse(statusCode: 200, body: Self.png),
        ])
        transport.stub(urlContains: "c.example/jpg", responses: [
            HTTPResponse(statusCode: 200, body: Self.jpeg),
        ])
        transport.stub(urlContains: "c.example/pos1", responses: [
            HTTPResponse(statusCode: 200, body: Self.gif),
        ])
        transport.stub(urlContains: "c.example/pos2", responses: [
            HTTPResponse(statusCode: 200, body: Self.gif),
        ])
        transport.stub(urlContains: "c.example/fail", responses: [
            HTTPResponse(statusCode: 500, body: Data("boom".utf8)),
        ])
        let client = DocsClient(
            api: TestSupport.makeAPI(transport: transport),
            downloadTransport: transport
        )
        return (client, transport)
    }

    private func imageRows() throws -> [DocImageRow] {
        try GoogleJSON.decoder.decode(Document.self, from: Data(Self.downloadJSON.utf8)).imageRows
    }

    func testDownloadImagesCreatesTheDirectoryAndWritesFiles() async throws {
        let (client, _) = makeDownloadClient()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // The directory was created on demand.
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // One result per row, inline (sorted) then positioned (sorted).
        XCTAssertEqual(
            results.map(\.objectId),
            ["img-a", "img-b", "img-nourl", "img-zfail", "pos.dup", "pos:dup"])
    }

    func testDownloadImagesNamesFilesSafelyAndWritesTheBytes() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // The two known inline formats get sniffed extensions and sequenced
        // names, prefixed by their origin.
        XCTAssertEqual(Self.outcome(results, "img-a"), .downloaded(filename: "001-inline-img-a.png", byteCount: Self.png.count))
        XCTAssertEqual(Self.outcome(results, "img-b"), .downloaded(filename: "002-inline-img-b.jpg", byteCount: Self.jpeg.count))

        // The bytes on disk match what the transport returned.
        let pngURL = tempDir.appendingPathComponent("001-inline-img-a.png")
        XCTAssertEqual(try Data(contentsOf: pngURL), Self.png)
    }

    func testDownloadImagesAvoidsCollisionsForCollidingSanitizedNames() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // Both positioned images sanitize to "pos_dup" but the sequence prefix
        // keeps their file names distinct, so neither overwrites the other.
        // The skipped and failed inline images did not advance the sequence
        // past 3, so the two positioned images take 004 and 005.
        let names = ["pos.dup", "pos:dup"].compactMap { objectId -> String? in
            if case let .downloaded(filename, _)? = Self.outcome(results, objectId) { return filename }
            return nil
        }
        XCTAssertEqual(names, ["004-positioned-pos_dup.gif", "005-positioned-pos_dup.gif"])
        XCTAssertEqual(Set(names).count, 2)
        for name in names {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(name).path))
        }
    }

    func testDownloadImagesSkipsRowsWithNoContentUri() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        XCTAssertEqual(Self.outcome(results, "img-nourl"), .skipped(reason: "no content URI"))
    }

    func testDownloadImagesRecordsFailuresWithoutStoppingOthers() async throws {
        let (client, _) = makeDownloadClient()

        let results = try await client.downloadImages(try imageRows(), to: tempDir)

        // The 500 is recorded as a failure...
        guard case .failed = Self.outcome(results, "img-zfail") else {
            return XCTFail("img-zfail should have failed: \(String(describing: Self.outcome(results, "img-zfail")))")
        }
        // ...yet the images before and after it still succeeded.
        guard case .downloaded = Self.outcome(results, "img-a") else {
            return XCTFail("img-a should have downloaded")
        }
        guard case .downloaded = Self.outcome(results, "pos.dup") else {
            return XCTFail("pos.dup should have downloaded")
        }
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

    func testDownloadImagesRefusesToWriteThroughAPrePlantedSymlink() async throws {
        // One inline image whose deterministic name is "001-inline-img-a.png".
        let json = #"""
        {
          "documentId": "doc-1",
          "inlineObjects": {
            "img-a": {"objectId": "img-a", "inlineObjectProperties": {"embeddedObject": {
              "imageProperties": {"contentUri": "https://c.example/png"}}}}
          }
        }
        """#
        let transport = StubTransport()
        transport.stub(urlContains: "c.example/png", responses: [
            HTTPResponse(statusCode: 200, body: Self.png),
        ])
        let client = DocsClient(
            api: TestSupport.makeAPI(transport: transport),
            downloadTransport: transport
        )
        let rows = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8)).imageRows

        // The directory must exist so the symlink can be planted before the run.
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let linkURL = tempDir.appendingPathComponent("001-inline-img-a.png")
        // The symlink points OUTSIDE the target directory; if the write followed
        // it, the bytes would land at `escapeTarget`.
        let escapeTarget = tempDir.deletingLastPathComponent()
            .appendingPathComponent("graham-docs-escape-\(ProcessInfo.processInfo.globallyUniqueString).png")
        defer { try? FileManager.default.removeItem(at: escapeTarget) }
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: escapeTarget)

        let results = try await client.downloadImages(rows, to: tempDir)

        // The write is refused and recorded as a failure, not a crash.
        guard case .failed = Self.outcome(results, "img-a") else {
            return XCTFail(
                "a symlinked target must fail: \(String(describing: Self.outcome(results, "img-a")))")
        }
        // Nothing was written through the link: the escape target never appears.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: escapeTarget.path),
            "the download must not follow the symlink out of the directory")
        // The symlink itself is left in place, untouched.
        let attributes = try FileManager.default.attributesOfItem(atPath: linkURL.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    // MARK: - API error propagation

    func testDocumentPropagatesGoogleErrorEnvelope() async {
        let transport = StubTransport()
        transport.stubTokenEndpoint()
        transport.stub(
            urlContains: "/v1/documents/",
            json: #"{"error":{"code":403,"message":"No access","status":"PERMISSION_DENIED"}}"#,
            status: 403
        )
        let client = DocsClient(
            api: TestSupport.makeAPI(transport: transport),
            downloadTransport: transport
        )

        do {
            _ = try await client.document(id: "doc-1")
            XCTFail("Expected an error")
        } catch GrahamError.googleAPIError(let code, let status, let message) {
            XCTAssertEqual(code, 403)
            XCTAssertEqual(status, "PERMISSION_DENIED")
            XCTAssertEqual(message, "No access")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Helpers and fixtures

    private static func outcome(_ results: [DocImageDownloadResult], _ objectId: String) -> DocImageDownloadOutcome? {
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
