import Foundation

/// The high-level client for the Slides v1 API.
public struct SlidesClient: Sendable {
    public static let baseURL = "https://slides.googleapis.com/v1"

    private let api: GoogleAPI
    private let downloadTransport: any HTTPTransport

    /// Builds the client.
    ///
    /// - Parameters:
    ///   - api: The low-level executor for Slides API calls (with the OAuth
    ///     bearer, retry, and backoff).
    ///   - downloadTransport: A separate transport for image downloads. It is
    ///     deliberately not the ``GoogleAPI`` path: an image ``contentUrl`` is a
    ///     pre-authorized, short-lived URL on a Google user-content host, not on
    ///     the Slides API host, so a download must **not** attach the Slides API
    ///     bearer token — doing so would leak the token to a different host and
    ///     is unnecessary. Tests inject a stub here; production uses a plain
    ///     `URLSession`.
    public init(api: GoogleAPI, downloadTransport: any HTTPTransport = URLSessionTransport()) {
        self.api = api
        self.downloadTransport = downloadTransport
    }

    /// Gets one presentation, with its slides.
    ///
    /// - Parameters:
    ///   - id: The presentation id.
    ///   - fields: An optional field mask, for example `slides.objectId`, so a
    ///     caller that needs only the slide order does not pull the full deck.
    ///     `nil` returns every field.
    public func presentation(id: String, fields: String? = nil) async throws -> Presentation {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/presentations/\(GoogleURL.escapePathComponent(id))",
            query: [("fields", fields)]
        )
        return try await api.getJSON(Presentation.self, from: url)
    }

    // MARK: - Batch update (the shared write path)

    /// Sends one `presentations.batchUpdate` call with `requests`, in order.
    ///
    /// This is the one write path for Slides. Every high-level write method
    /// builds typed ``SlidesBatchUpdateRequest`` values and goes through here,
    /// so the endpoint, the escaped path, and the response decoding live in
    /// exactly one place.
    public func batchUpdate(
        presentationId: String,
        requests: [SlidesBatchUpdateRequest]
    ) async throws -> SlidesBatchUpdateResponse {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/presentations/\(GoogleURL.escapePathComponent(presentationId)):batchUpdate"
        )
        let body = SlidesBatchUpdateRequestBody(requests: requests)
        return try await api.sendJSON(SlidesBatchUpdateResponse.self, method: "POST", url: url, body: body)
    }

    /// Creates one slide and returns the new slide's object id.
    ///
    /// - Parameters:
    ///   - presentationId: The presentation to add the slide to.
    ///   - position: The one-based final position of the new slide, matching
    ///     the slide numbers that `slides cat` and `slides list` print. `nil`
    ///     appends the slide at the end. Only the lower bound is checked here;
    ///     the upper bound is left to Google, so an add stays a single write
    ///     with no extra read of the deck.
    ///   - layout: A predefined layout name, for example `BLANK` or
    ///     `TITLE_AND_BODY`. The name is normalized (trimmed, uppercased, `-`
    ///     and spaces become `_`), so `title-and-body` also works. Google
    ///     rejects a name it does not know.
    public func createSlide(
        presentationId: String,
        at position: Int? = nil,
        layout: String = "BLANK"
    ) async throws -> String {
        if let position, position < 1 {
            throw GrahamError.invalidArgument(
                "slide position must be 1 or greater, got \(position)")
        }
        let normalized = Self.normalizeLayout(layout)
        guard !normalized.isEmpty else {
            throw GrahamError.invalidArgument("the layout name is empty")
        }
        let request = CreateSlideRequest(
            insertionIndex: position.map { $0 - 1 },
            slideLayoutReference: SlideLayoutReference(predefinedLayout: normalized)
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createSlide(request)]
        )
        guard let objectId = response.replies?.first?.createSlide?.objectId else {
            throw GrahamError.invalidResponse(
                "the createSlide reply carries no object id")
        }
        return objectId
    }

    /// Creates a text box on one slide, optionally inserts its initial text,
    /// and returns the new element's object id.
    ///
    /// Geometry is measured in points. Shape creation and non-empty text
    /// insertion are sent together in one atomic batch update.
    public func createTextBox(
        presentationId: String,
        slideId: String,
        text: String,
        objectId: String? = nil,
        x: Double = 50,
        y: Double = 50,
        width: Double = 300,
        height: Double = 50
    ) async throws -> String {
        let sentObjectId = objectId ?? "graham-\(UUID().uuidString)"
        let size = ElementSize(
            width: ElementDimension(magnitude: width, unit: .pt),
            height: ElementDimension(magnitude: height, unit: .pt)
        )
        let transform = ElementTransform(
            translateX: x,
            translateY: y,
            unit: .pt
        )
        let createShape = CreateShapeRequest(
            objectId: sentObjectId,
            elementProperties: PageElementProperties(
                pageObjectId: slideId,
                size: size,
                transform: transform
            ),
            shapeType: "TEXT_BOX"
        )
        var requests: [SlidesBatchUpdateRequest] = [.createShape(createShape)]
        if !text.isEmpty {
            requests.append(.insertText(InsertTextRequest(
                objectId: sentObjectId,
                text: text,
                insertionIndex: 0
            )))
        }

        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: requests
        )
        return response.replies?.first?.createShape?.objectId ?? sentObjectId
    }

    /// Creates an image on one slide and returns the new element's object id.
    /// Geometry is measured in points; when omitted, Google keeps the image's
    /// native size and chooses its placement.
    public func createImage(
        presentationId: String,
        slideId: String,
        url: String,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard !url.isEmpty else {
            throw GrahamError.invalidArgument("the image URL is empty")
        }
        let sentObjectId = objectId ?? "graham-\(UUID().uuidString)"
        let request = CreateImageRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            url: url
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createImage(request)]
        )
        return response.replies?.first?.createImage?.objectId ?? sentObjectId
    }

    /// Creates a YouTube or Drive video on one slide and returns the new
    /// element's object id. Geometry is measured in points.
    public func createVideo(
        presentationId: String,
        slideId: String,
        source: VideoSource = .youtube,
        videoId: String,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard !videoId.isEmpty else {
            throw GrahamError.invalidArgument("the video id is empty")
        }
        let sentObjectId = objectId ?? "graham-\(UUID().uuidString)"
        let request = CreateVideoRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            source: source,
            id: videoId
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createVideo(request)]
        )
        return response.replies?.first?.createVideo?.objectId ?? sentObjectId
    }

    /// Creates a line on one slide and returns the new element's object id.
    /// Geometry is measured in points.
    public func createLine(
        presentationId: String,
        slideId: String,
        category: LineCategory = .straight,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        let sentObjectId = objectId ?? "graham-\(UUID().uuidString)"
        let request = CreateLineRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            category: category
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createLine(request)]
        )
        return response.replies?.first?.createLine?.objectId ?? sentObjectId
    }

    /// Creates a table on one slide and returns the new element's object id.
    /// Geometry is measured in points.
    public func createTable(
        presentationId: String,
        slideId: String,
        rows: Int,
        columns: Int,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard rows >= 1 else {
            throw GrahamError.invalidArgument("table rows must be 1 or greater, got \(rows)")
        }
        guard columns >= 1 else {
            throw GrahamError.invalidArgument(
                "table columns must be 1 or greater, got \(columns)")
        }
        let sentObjectId = objectId ?? "graham-\(UUID().uuidString)"
        let request = CreateTableRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            rows: rows,
            columns: columns
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createTable(request)]
        )
        return response.replies?.first?.createTable?.objectId ?? sentObjectId
    }

    /// Creates a page element from a Sheets embedded chart and returns its
    /// object id. Geometry is measured in points.
    public func createSheetsChart(
        presentationId: String,
        slideId: String,
        spreadsheetId: String,
        chartId: Int,
        linked: Bool = false,
        objectId: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) async throws -> String {
        guard !spreadsheetId.isEmpty else {
            throw GrahamError.invalidArgument("the spreadsheet id is empty")
        }
        let sentObjectId = objectId ?? "graham-\(UUID().uuidString)"
        let request = CreateSheetsChartRequest(
            objectId: sentObjectId,
            elementProperties: try makeElementProperties(
                slideId: slideId, x: x, y: y, width: width, height: height),
            spreadsheetId: spreadsheetId,
            chartId: chartId,
            linkingMode: linked ? .linked : nil
        )
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.createSheetsChart(request)]
        )
        return response.replies?.first?.createSheetsChart?.objectId ?? sentObjectId
    }

    /// Groups page elements and returns the new group's object id.
    public func groupElements(
        presentationId: String,
        childIds: [String],
        groupObjectId: String? = nil
    ) async throws -> String {
        guard childIds.count >= 2 else {
            throw GrahamError.invalidArgument("a group requires at least 2 child object ids")
        }
        let sentObjectId = groupObjectId ?? "graham-\(UUID().uuidString)"
        let response = try await batchUpdate(
            presentationId: presentationId,
            requests: [.groupObjects(GroupObjectsRequest(
                groupObjectId: sentObjectId,
                childrenObjectIds: childIds
            ))]
        )
        return response.replies?.first?.groupObjects?.objectId ?? sentObjectId
    }

    /// Removes top-level groups while keeping their children in place.
    public func ungroupElements(
        presentationId: String,
        objectIds: [String]
    ) async throws {
        guard !objectIds.isEmpty else {
            throw GrahamError.invalidArgument("ungroup requires at least 1 group object id")
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.ungroupObjects(UngroupObjectsRequest(objectIds: objectIds))]
        )
    }

    /// Builds optional creation geometry shared by every non-shape element.
    private func makeElementProperties(
        slideId: String,
        x: Double?,
        y: Double?,
        width: Double?,
        height: Double?
    ) throws -> PageElementProperties {
        guard (width == nil) == (height == nil) else {
            throw GrahamError.invalidArgument("width and height must be provided together")
        }

        let size: ElementSize?
        if let width, let height {
            guard width > 0 else {
                throw GrahamError.invalidArgument("width must be greater than zero")
            }
            guard height > 0 else {
                throw GrahamError.invalidArgument("height must be greater than zero")
            }
            size = ElementSize(
                width: ElementDimension(magnitude: width, unit: .pt),
                height: ElementDimension(magnitude: height, unit: .pt)
            )
        } else {
            size = nil
        }

        let transform: ElementTransform?
        if x != nil || y != nil {
            transform = ElementTransform(
                translateX: x ?? 0,
                translateY: y ?? 0,
                unit: .pt
            )
        } else {
            transform = nil
        }

        return PageElementProperties(
            pageObjectId: slideId,
            size: size,
            transform: transform
        )
    }

    /// Inserts text into a text-bearing page element.
    ///
    /// Empty text is a no-op and sends no network request.
    public func insertText(
        presentationId: String,
        objectId: String,
        text: String,
        insertionIndex: Int = 0
    ) async throws {
        guard !text.isEmpty else { return }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.insertText(InsertTextRequest(
                objectId: objectId,
                text: text,
                insertionIndex: insertionIndex
            ))]
        )
    }

    /// Moves one slide so it ends at a one-based final position.
    ///
    /// The API's `updateSlidesPosition.insertionIndex` is zero-based and refers
    /// to the slide order **before** the move. So this method first reads the
    /// current slide order, then translates: for a final zero-based index `f`
    /// and a current index `c`, the insertion index is `f` when the slide moves
    /// backward (`f < c`) and `f + 1` when it moves forward (`f > c`), because
    /// the slide's own pre-move position still counts in the insertion order.
    /// When the slide is already at `position`, no write is sent.
    ///
    /// - Parameters:
    ///   - presentationId: The presentation that holds the slide.
    ///   - slideId: The exact object id of the slide to move.
    ///   - position: The one-based final position, matching the slide numbers
    ///     that `slides cat` and `slides list` print.
    public func moveSlide(
        presentationId: String,
        slideId: String,
        to position: Int
    ) async throws {
        guard position >= 1 else {
            throw GrahamError.invalidArgument(
                "slide position must be 1 or greater, got \(position)")
        }
        // Only the slide order is needed, so the read pulls just the ids.
        let presentation = try await self.presentation(
            id: presentationId, fields: "slides.objectId")
        let slides = presentation.slides ?? []
        guard let currentIndex = slides.firstIndex(where: { $0.objectId == slideId }) else {
            throw GrahamError.invalidArgument(
                "no slide with id \"\(slideId)\" in presentation \(presentationId)")
        }
        guard position <= slides.count else {
            throw GrahamError.invalidArgument(
                "slide position \(position) is out of range; "
                + "the presentation has \(slides.count) slide(s)")
        }
        let targetIndex = position - 1
        if targetIndex == currentIndex {
            return
        }
        let insertionIndex = targetIndex > currentIndex ? targetIndex + 1 : targetIndex
        let request = UpdateSlidesPositionRequest(
            slideObjectIds: [slideId],
            insertionIndex: insertionIndex
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateSlidesPosition(request)]
        )
    }

    /// Deletes one slide or page element by its exact object id.
    ///
    /// The id is sent as given: this method never infers, expands, or looks up
    /// a target. Google rejects an id that does not exist.
    public func deleteObject(presentationId: String, objectId: String) async throws {
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.deleteObject(DeleteObjectRequest(objectId: objectId))]
        )
    }

    /// Normalizes a predefined layout name: trims whitespace, uppercases, and
    /// maps `-` and spaces to `_`, so `title-and-body` becomes `TITLE_AND_BODY`.
    static func normalizeLayout(_ layout: String) -> String {
        layout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - Image download

    /// Downloads the bytes at an image `contentUrl`.
    ///
    /// The request is a plain GET with no `Authorization` header. A Slides
    /// `Image.contentUrl` has a ~30-minute lifetime and is "tagged with the
    /// account of the requester"; the URL itself carries the authorization, and
    /// it points at a Google user-content host rather than the Slides API host.
    /// Attaching the API OAuth bearer would therefore both leak the token to a
    /// third-party host and be redundant, so the download bypasses
    /// ``GoogleAPI`` and goes straight through the injected transport.
    ///
    /// See the Slides `Image.contentUrl` reference:
    /// https://developers.google.com/slides/api/reference/rest/v1/presentations.pages
    public func downloadImage(from contentUrl: String) async throws -> Data {
        guard let url = URL(string: contentUrl), url.scheme != nil else {
            throw GrahamError.invalidURL(contentUrl)
        }
        let response = try await downloadTransport.send(HTTPRequest(method: "GET", url: url))
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: response.body, encoding: .utf8) ?? ""
            throw GrahamError.httpError(statusCode: response.statusCode, body: String(text.prefix(500)))
        }
        return response.body
    }

    /// Downloads every image in `rows` into `directory`.
    ///
    /// The directory is created if it does not exist. Each image is fetched in
    /// order and written under a deterministic, collision-free name (see
    /// ``SlideImageFile``). A row with no content URL is skipped, and a fetch or
    /// write that fails is recorded and does not stop the rest — so one bad
    /// image never loses the others. The returned results are in the same order
    /// as `rows`, one per row.
    public func downloadImages(
        _ rows: [SlideImageRow],
        to directory: URL
    ) async throws -> [SlideImageDownloadResult] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.standardizedFileURL

        var results: [SlideImageDownloadResult] = []
        var sequence = 0
        for row in rows {
            guard let contentUrl = row.contentUrl, !contentUrl.isEmpty else {
                results.append(SlideImageDownloadResult(
                    objectId: row.objectId,
                    slideIndex: row.slideIndex,
                    contentUrl: row.contentUrl,
                    outcome: .skipped(reason: "no content URL")
                ))
                continue
            }
            sequence += 1
            do {
                let data = try await downloadImage(from: contentUrl)
                let filename = SlideImageFile.filename(
                    sequence: sequence,
                    slideIndex: row.slideIndex,
                    objectId: row.objectId,
                    fileExtension: SlideImageFile.fileExtension(forBytes: data)
                )
                let fileURL = directory.appendingPathComponent(filename)
                // Defense in depth: the name is already sanitized, but confirm
                // the resolved file still sits directly inside the directory.
                guard fileURL.deletingLastPathComponent().standardizedFileURL == target else {
                    results.append(SlideImageDownloadResult(
                        objectId: row.objectId,
                        slideIndex: row.slideIndex,
                        contentUrl: contentUrl,
                        outcome: .failed(reason: "unsafe file path for \(filename)")
                    ))
                    continue
                }
                try data.write(to: fileURL)
                results.append(SlideImageDownloadResult(
                    objectId: row.objectId,
                    slideIndex: row.slideIndex,
                    contentUrl: contentUrl,
                    outcome: .downloaded(filename: filename, byteCount: data.count)
                ))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                results.append(SlideImageDownloadResult(
                    objectId: row.objectId,
                    slideIndex: row.slideIndex,
                    contentUrl: contentUrl,
                    outcome: .failed(reason: reason)
                ))
            }
        }
        return results
    }
}
