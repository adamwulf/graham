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

    // MARK: - Element geometry

    /// Moves an element's local origin to an absolute point in its parent's
    /// coordinate space. Coordinates are measured in points. For a top-level
    /// element the parent is the page; for a grouped element it is the group.
    public func moveElement(
        presentationId: String,
        objectId: String,
        toX x: Double,
        toY y: Double
    ) async throws {
        let context = try await elementGeometryContext(
            presentationId: presentationId, objectId: objectId)
        let transform = ElementTransform(
            scaleX: context.a,
            scaleY: context.d,
            shearX: context.c,
            shearY: context.b,
            translateX: context.nativeLength(points: x),
            translateY: context.nativeLength(points: y),
            unit: context.unit
        )
        try await sendAbsoluteTransform(
            presentationId: presentationId, objectId: objectId, transform: transform)
    }

    /// Moves an element's local origin by a point delta in its parent's
    /// coordinate space. For a top-level element the parent is the page; for
    /// a grouped element it is the group.
    public func moveElement(
        presentationId: String,
        objectId: String,
        byX deltaX: Double,
        byY deltaY: Double
    ) async throws {
        let context = try await elementGeometryContext(
            presentationId: presentationId, objectId: objectId)
        let transform = ElementTransform(
            scaleX: context.a,
            scaleY: context.d,
            shearX: context.c,
            shearY: context.b,
            translateX: context.tx + context.nativeLength(points: deltaX),
            translateY: context.ty + context.nativeLength(points: deltaY),
            unit: context.unit
        )
        try await sendAbsoluteTransform(
            presentationId: presentationId, objectId: objectId, transform: transform)
    }

    /// Resizes an element about its center, preserving that center. Both
    /// factors must be greater than zero.
    public func scaleElement(
        presentationId: String,
        objectId: String,
        factorX: Double,
        factorY: Double
    ) async throws {
        guard factorX > 0 else {
            throw GrahamError.invalidArgument("horizontal scale factor must be greater than zero")
        }
        guard factorY > 0 else {
            throw GrahamError.invalidArgument("vertical scale factor must be greater than zero")
        }
        let context = try await elementGeometryContext(
            presentationId: presentationId, objectId: objectId)
        let existing = context.transform
        let center = ElementTransform.center(
            of: existing, width: context.width, height: context.height)
        let update = ElementTransform.scale(
            x: factorX,
            y: factorY,
            aboutX: center.x,
            aboutY: center.y,
            unit: context.unit
        )
        let transform = ElementTransform.concatenate(update, with: existing)
        try await sendAbsoluteTransform(
            presentationId: presentationId, objectId: objectId, transform: transform)
    }

    /// Uniformly resizes an element about its center.
    public func scaleElement(
        presentationId: String,
        objectId: String,
        by factor: Double
    ) async throws {
        try await scaleElement(
            presentationId: presentationId,
            objectId: objectId,
            factorX: factor,
            factorY: factor
        )
    }

    /// Rotates an element clockwise about its center by `degrees`.
    public func rotateElement(
        presentationId: String,
        objectId: String,
        byDegrees degrees: Double
    ) async throws {
        let context = try await elementGeometryContext(
            presentationId: presentationId, objectId: objectId)
        try await rotateElement(
            presentationId: presentationId,
            objectId: objectId,
            byDegrees: degrees,
            context: context
        )
    }

    /// Rotates an element clockwise to an absolute angle. The current angle
    /// is derived from `atan2(shearY, scaleX)`.
    public func rotateElement(
        presentationId: String,
        objectId: String,
        toDegrees degrees: Double
    ) async throws {
        let context = try await elementGeometryContext(
            presentationId: presentationId, objectId: objectId)
        try await rotateElement(
            presentationId: presentationId,
            objectId: objectId,
            byDegrees: degrees - context.transform.rotationDegrees,
            context: context
        )
    }

    /// Sends a raw element transform without reading or precomputing it.
    ///
    /// With `.relative`, `transform.unit` must match the element's existing
    /// transform unit (usually EMU). The Slides API does not convert units
    /// while multiplying a relative update into the existing matrix.
    public func transformElement(
        presentationId: String,
        objectId: String,
        transform: ElementTransform,
        mode: TransformApplyMode
    ) async throws {
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updatePageElementTransform(UpdatePageElementTransformRequest(
                objectId: objectId,
                transform: transform,
                applyMode: mode
            ))]
        )
    }

    /// Reorders one or more ungrouped elements on the same page.
    ///
    /// The Slides API requires every id to identify an ungrouped page element
    /// on one page. When several ids are supplied, their relative order is
    /// preserved.
    public func reorderElements(
        presentationId: String,
        objectIds: [String],
        operation: ZOrderOperation
    ) async throws {
        guard !objectIds.isEmpty else {
            throw GrahamError.invalidArgument("reorder requires at least 1 page-element object id")
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updatePageElementsZOrder(UpdatePageElementsZOrderRequest(
                pageElementObjectIds: objectIds,
                operation: operation
            ))]
        )
    }

    /// The read-side values needed to precompute one absolute edit in the
    /// element's native unit.
    private struct ElementGeometryContext {
        let a: Double
        let b: Double
        let c: Double
        let d: Double
        let tx: Double
        let ty: Double
        let width: Double
        let height: Double
        let unit: ElementUnit

        var transform: ElementTransform {
            ElementTransform(
                scaleX: a,
                scaleY: d,
                shearX: c,
                shearY: b,
                translateX: tx,
                translateY: ty,
                unit: unit
            )
        }

        func nativeLength(points: Double) -> Double {
            unit == .emu ? points * SlideElementGeometry.emuPerPoint : points
        }
    }

    private func elementGeometryContext(
        presentationId: String,
        objectId: String
    ) async throws -> ElementGeometryContext {
        let presentation = try await self.presentation(
            id: presentationId, fields: "slides.pageElements")
        guard let element = presentation.findElement(objectId: objectId) else {
            throw GrahamError.invalidArgument(
                "no page element with id \"\(objectId)\" in presentation \(presentationId)")
        }
        let transform = element.transform
        let unit: ElementUnit = transform?.unit == "PT" ? .pt : .emu
        return ElementGeometryContext(
            a: transform?.scaleX ?? 1,
            b: transform?.shearY ?? 0,
            c: transform?.shearX ?? 0,
            d: transform?.scaleY ?? 1,
            tx: transform?.translateX ?? 0,
            ty: transform?.translateY ?? 0,
            width: element.size?.width?.magnitude ?? 0,
            height: element.size?.height?.magnitude ?? 0,
            unit: unit
        )
    }

    private func rotateElement(
        presentationId: String,
        objectId: String,
        byDegrees degrees: Double,
        context: ElementGeometryContext
    ) async throws {
        let existing = context.transform
        let center = ElementTransform.center(
            of: existing, width: context.width, height: context.height)
        let update = ElementTransform.rotation(
            degrees: degrees,
            aboutX: center.x,
            y: center.y,
            unit: context.unit
        )
        let transform = ElementTransform.concatenate(update, with: existing)
        try await sendAbsoluteTransform(
            presentationId: presentationId, objectId: objectId, transform: transform)
    }

    private func sendAbsoluteTransform(
        presentationId: String,
        objectId: String,
        transform: ElementTransform
    ) async throws {
        try await transformElement(
            presentationId: presentationId,
            objectId: objectId,
            transform: transform,
            mode: .absolute
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

    // MARK: - Element styles
    //
    // Every style method builds a typed style container together with a
    // deterministic field mask: one mask path per provided parameter, in a
    // fixed documented order, so the wire mask is stable and testable. At least
    // one parameter must be provided, or the method throws
    // ``GrahamError/invalidArgument(_:)`` and sends nothing. A `--no-*`
    // parameter clears a fill/outline/shadow by setting its property state to
    // `NOT_RENDERED`, and cannot be combined with any other parameter of the
    // same group. Updating a fill/outline/shadow implicitly renders it, so a
    // set never has to name `propertyState`.

    /// Styles a shape's fill, outline, shadow, and content alignment.
    ///
    /// - Parameters:
    ///   - fillColor / fillAlpha: The solid background fill. `noFill` clears it
    ///     and is mutually exclusive with a fill color or alpha.
    ///   - outlineColor / outlineAlpha / outlineWeight / outlineDash: The
    ///     border. `noOutline` clears it and is mutually exclusive with any
    ///     other outline parameter.
    ///   - shadowColor / shadowAlpha / shadowBlur / shadowOffsetX /
    ///     shadowOffsetY: The drop shadow. The offsets build a single shadow
    ///     transform (a missing axis is 0). `noShadow` clears the shadow and is
    ///     mutually exclusive with any other shadow parameter.
    ///   - contentAlignment: The vertical alignment of the shape's text.
    ///
    /// Weights and the blur are in points and must be greater than zero; every
    /// alpha must be within 0...1.
    public func styleShape(
        presentationId: String,
        objectId: String,
        fillColor: OpaqueColor? = nil,
        fillAlpha: Double? = nil,
        noFill: Bool = false,
        outlineColor: OpaqueColor? = nil,
        outlineAlpha: Double? = nil,
        outlineWeight: Double? = nil,
        outlineDash: DashStyle? = nil,
        noOutline: Bool = false,
        shadowColor: OpaqueColor? = nil,
        shadowAlpha: Double? = nil,
        shadowBlur: Double? = nil,
        shadowOffsetX: Double? = nil,
        shadowOffsetY: Double? = nil,
        noShadow: Bool = false,
        contentAlignment: ContentAlignment? = nil
    ) async throws {
        var mask: [String] = []

        // Fill group.
        var backgroundFill: ShapeBackgroundFill?
        let hasFill = fillColor != nil || fillAlpha != nil
        if noFill {
            guard !hasFill else {
                throw GrahamError.invalidArgument(
                    "no-fill cannot be combined with a fill color or alpha")
            }
            backgroundFill = ShapeBackgroundFill(propertyState: .notRendered)
            mask.append("shapeBackgroundFill.propertyState")
        } else if hasFill {
            if let fillAlpha { try Self.validateAlpha(fillAlpha, label: "fill alpha") }
            backgroundFill = ShapeBackgroundFill(
                solidFill: SolidFill(color: fillColor, alpha: fillAlpha))
            if fillColor != nil { mask.append("shapeBackgroundFill.solidFill.color") }
            if fillAlpha != nil { mask.append("shapeBackgroundFill.solidFill.alpha") }
        }

        // Outline group.
        let outline = try Self.buildOutline(
            color: outlineColor,
            alpha: outlineAlpha,
            weight: outlineWeight,
            dash: outlineDash,
            noOutline: noOutline
        )
        mask.append(contentsOf: outline.mask)

        // Shadow group.
        let shadow = try Self.buildShadow(
            color: shadowColor,
            alpha: shadowAlpha,
            blur: shadowBlur,
            offsetX: shadowOffsetX,
            offsetY: shadowOffsetY,
            noShadow: noShadow
        )
        mask.append(contentsOf: shadow.mask)

        // Content alignment.
        if contentAlignment != nil { mask.append("contentAlignment") }

        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument("style shape requires at least one style option")
        }

        let style = ShapeStyle(
            shapeBackgroundFill: backgroundFill,
            outline: outline.value,
            shadow: shadow.value,
            contentAlignment: contentAlignment
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateShapeProperties(UpdateShapePropertiesRequest(
                objectId: objectId,
                shapeProperties: style,
                fields: mask.joined(separator: ",")
            ))]
        )
    }

    /// Styles an image's outline. This is the only appearance the Slides API
    /// lets a write set on an image.
    ///
    /// The API exposes an image's brightness, contrast, transparency, crop,
    /// recolor, and shadow as **read-only**, so graham cannot change them; only
    /// the outline (and the link, which belongs to a later milestone) is
    /// writable. `noOutline` clears the outline and is mutually exclusive with
    /// any other outline parameter.
    public func styleImage(
        presentationId: String,
        objectId: String,
        outlineColor: OpaqueColor? = nil,
        outlineAlpha: Double? = nil,
        outlineWeight: Double? = nil,
        outlineDash: DashStyle? = nil,
        noOutline: Bool = false
    ) async throws {
        let outline = try Self.buildOutline(
            color: outlineColor,
            alpha: outlineAlpha,
            weight: outlineWeight,
            dash: outlineDash,
            noOutline: noOutline
        )
        guard !outline.mask.isEmpty else {
            throw GrahamError.invalidArgument("style image requires at least one outline option")
        }
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateImageProperties(UpdateImagePropertiesRequest(
                objectId: objectId,
                imageProperties: ImageStyle(outline: outline.value),
                fields: outline.mask.joined(separator: ",")
            ))]
        )
    }

    /// Styles a line's fill, weight, dash style, and arrow ends.
    ///
    /// Lines have no fill property state, so there is no `--no-*` clear here.
    /// The weight is in points and must be greater than zero; the alpha must be
    /// within 0...1.
    public func styleLine(
        presentationId: String,
        objectId: String,
        color: OpaqueColor? = nil,
        alpha: Double? = nil,
        weight: Double? = nil,
        dash: DashStyle? = nil,
        startArrow: ArrowStyle? = nil,
        endArrow: ArrowStyle? = nil
    ) async throws {
        if let alpha { try Self.validateAlpha(alpha, label: "line alpha") }
        if let weight { try Self.validatePositive(weight, label: "line weight") }

        var mask: [String] = []
        var lineFill: LineFill?
        if color != nil || alpha != nil {
            lineFill = LineFill(solidFill: SolidFill(color: color, alpha: alpha))
        }
        if color != nil { mask.append("lineFill.solidFill.color") }
        if alpha != nil { mask.append("lineFill.solidFill.alpha") }
        if weight != nil { mask.append("weight") }
        if dash != nil { mask.append("dashStyle") }
        if startArrow != nil { mask.append("startArrow") }
        if endArrow != nil { mask.append("endArrow") }

        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument("style line requires at least one style option")
        }

        let style = LineStyle(
            lineFill: lineFill,
            weight: weight.map { ElementDimension(magnitude: $0, unit: .pt) },
            dashStyle: dash,
            startArrow: startArrow,
            endArrow: endArrow
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateLineProperties(UpdateLinePropertiesRequest(
                objectId: objectId,
                lineProperties: style,
                fields: mask.joined(separator: ",")
            ))]
        )
    }

    /// Styles a video's playback options and outline.
    ///
    /// `start` and `end` are whole seconds and must be 0 or greater; when both
    /// are given, `end` must be greater than `start`. The outline parameters
    /// match ``styleShape(presentationId:objectId:fillColor:fillAlpha:noFill:outlineColor:outlineAlpha:outlineWeight:outlineDash:noOutline:shadowColor:shadowAlpha:shadowBlur:shadowOffsetX:shadowOffsetY:noShadow:contentAlignment:)``.
    public func styleVideo(
        presentationId: String,
        objectId: String,
        autoPlay: Bool? = nil,
        mute: Bool? = nil,
        start: Int? = nil,
        end: Int? = nil,
        outlineColor: OpaqueColor? = nil,
        outlineAlpha: Double? = nil,
        outlineWeight: Double? = nil,
        outlineDash: DashStyle? = nil,
        noOutline: Bool = false
    ) async throws {
        if let start, start < 0 {
            throw GrahamError.invalidArgument("video start must be 0 or greater, got \(start)")
        }
        if let end, end < 0 {
            throw GrahamError.invalidArgument("video end must be 0 or greater, got \(end)")
        }
        if let start, let end, end <= start {
            throw GrahamError.invalidArgument(
                "video end (\(end)) must be greater than start (\(start))")
        }

        var mask: [String] = []
        if autoPlay != nil { mask.append("autoPlay") }
        if mute != nil { mask.append("mute") }
        if start != nil { mask.append("start") }
        if end != nil { mask.append("end") }

        let outline = try Self.buildOutline(
            color: outlineColor,
            alpha: outlineAlpha,
            weight: outlineWeight,
            dash: outlineDash,
            noOutline: noOutline
        )
        mask.append(contentsOf: outline.mask)

        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument("style video requires at least one style option")
        }

        let style = VideoStyle(
            autoPlay: autoPlay,
            mute: mute,
            start: start,
            end: end,
            outline: outline.value
        )
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.updateVideoProperties(UpdateVideoPropertiesRequest(
                objectId: objectId,
                videoProperties: style,
                fields: mask.joined(separator: ",")
            ))]
        )
    }

    /// Refreshes a linked Sheets chart to its latest spreadsheet data.
    ///
    /// This works only on a chart embedded with `LINKED` linking mode; Google
    /// rejects an object id that is not a linked chart. The reply is empty.
    public func refreshSheetsChart(presentationId: String, objectId: String) async throws {
        _ = try await batchUpdate(
            presentationId: presentationId,
            requests: [.refreshSheetsChart(RefreshSheetsChartRequest(objectId: objectId))]
        )
    }

    /// The outline (border) shared by ``styleShape``, ``styleImage``, and
    /// ``styleVideo``, together with its deterministic mask paths in the fixed
    /// order color, alpha, weight, dash. `noOutline` instead clears the outline
    /// with a single `outline.propertyState` path and rejects any other
    /// outline parameter.
    private static func buildOutline(
        color: OpaqueColor?,
        alpha: Double?,
        weight: Double?,
        dash: DashStyle?,
        noOutline: Bool
    ) throws -> (value: Outline?, mask: [String]) {
        let hasAny = color != nil || alpha != nil || weight != nil || dash != nil
        if noOutline {
            guard !hasAny else {
                throw GrahamError.invalidArgument(
                    "no-outline cannot be combined with other outline options")
            }
            return (Outline(propertyState: .notRendered), ["outline.propertyState"])
        }
        guard hasAny else { return (nil, []) }

        if let alpha { try validateAlpha(alpha, label: "outline alpha") }
        if let weight { try validatePositive(weight, label: "outline weight") }

        var mask: [String] = []
        let outlineFill: OutlineFill?
        if color != nil || alpha != nil {
            outlineFill = OutlineFill(solidFill: SolidFill(color: color, alpha: alpha))
        } else {
            outlineFill = nil
        }
        if color != nil { mask.append("outline.outlineFill.solidFill.color") }
        if alpha != nil { mask.append("outline.outlineFill.solidFill.alpha") }
        if weight != nil { mask.append("outline.weight") }
        if dash != nil { mask.append("outline.dashStyle") }

        let outline = Outline(
            outlineFill: outlineFill,
            weight: weight.map { ElementDimension(magnitude: $0, unit: .pt) },
            dashStyle: dash
        )
        return (outline, mask)
    }

    /// The drop shadow used by ``styleShape``, together with its deterministic
    /// mask paths in the fixed order color, alpha, blurRadius, transform. The
    /// offsets build one shadow transform (scale 1, no shear, a missing axis is
    /// 0). `noShadow` instead clears the shadow with a single
    /// `shadow.propertyState` path and rejects any other shadow parameter.
    private static func buildShadow(
        color: OpaqueColor?,
        alpha: Double?,
        blur: Double?,
        offsetX: Double?,
        offsetY: Double?,
        noShadow: Bool
    ) throws -> (value: Shadow?, mask: [String]) {
        let hasOffset = offsetX != nil || offsetY != nil
        let hasAny = color != nil || alpha != nil || blur != nil || hasOffset
        if noShadow {
            guard !hasAny else {
                throw GrahamError.invalidArgument(
                    "no-shadow cannot be combined with other shadow options")
            }
            return (Shadow(propertyState: .notRendered), ["shadow.propertyState"])
        }
        guard hasAny else { return (nil, []) }

        if let alpha { try validateAlpha(alpha, label: "shadow alpha") }
        if let blur { try validatePositive(blur, label: "shadow blur") }

        var mask: [String] = []
        if color != nil { mask.append("shadow.color") }
        if alpha != nil { mask.append("shadow.alpha") }
        if blur != nil { mask.append("shadow.blurRadius") }
        var transform: ElementTransform?
        if hasOffset {
            transform = ElementTransform(
                scaleX: 1,
                scaleY: 1,
                shearX: 0,
                shearY: 0,
                translateX: offsetX ?? 0,
                translateY: offsetY ?? 0,
                unit: .pt
            )
            mask.append("shadow.transform")
        }

        let shadow = Shadow(
            color: color,
            alpha: alpha,
            blurRadius: blur.map { ElementDimension(magnitude: $0, unit: .pt) },
            transform: transform
        )
        return (shadow, mask)
    }

    /// Throws ``GrahamError/invalidArgument(_:)`` unless `alpha` is within
    /// 0...1.
    private static func validateAlpha(_ alpha: Double, label: String) throws {
        guard (0...1).contains(alpha) else {
            throw GrahamError.invalidArgument(
                "\(label) must be within 0 and 1, got \(alpha)")
        }
    }

    /// Throws ``GrahamError/invalidArgument(_:)`` unless `value` is greater
    /// than zero.
    private static func validatePositive(_ value: Double, label: String) throws {
        guard value > 0 else {
            throw GrahamError.invalidArgument(
                "\(label) must be greater than zero, got \(value)")
        }
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
