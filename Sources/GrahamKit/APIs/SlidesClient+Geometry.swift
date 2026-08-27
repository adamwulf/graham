import Foundation

extension SlidesClient {
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
        guard factorX.isFinite, factorX > 0 else {
            throw GrahamError.invalidArgument("horizontal scale factor must be greater than zero")
        }
        guard factorY.isFinite, factorY > 0 else {
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
}
