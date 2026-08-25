import XCTest
@testable import GrahamKit

/// Tests for the pure affine-transform math on ``ElementTransform`` and for the
/// exact JSON encoding of the two geometry batch-update requests. Every test is
/// offline: the math helpers are pure functions and the encoding uses the
/// shared sorted-keys encoder, so the strings are deterministic. Client
/// behavior (reads, unit conversion, error propagation) is covered separately
/// in the write tests.
final class SlidesTransformMathTests: XCTestCase {
    /// Applies a transform to a point, in the transform's own unit, using the
    /// Slides matrix layout (`a = scaleX`, `b = shearY`, `c = shearX`,
    /// `d = scaleY`). A missing shear counts as 0.
    private func apply(_ t: ElementTransform, x: Double, y: Double) -> (x: Double, y: Double) {
        let a = t.scaleX
        let b = t.shearY ?? 0
        let c = t.shearX ?? 0
        let d = t.scaleY
        return (x: a * x + c * y + t.translateX, y: b * x + d * y + t.translateY)
    }

    /// Asserts a transform carries all six matrix values explicitly, so a
    /// computed result never relies on the wire model's omit-shear default.
    private func assertAllSixSet(
        _ t: ElementTransform,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(t.shearX, "shearX must be set explicitly", file: file, line: line)
        XCTAssertNotNil(t.shearY, "shearY must be set explicitly", file: file, line: line)
    }

    // MARK: - Concatenation order (B × T, not T × B)

    func testConcatenateComputesUpdateTimesExisting() throws {
        // Existing T scales by 2 about the origin; update B translates by (10, 20).
        let existing = ElementTransform(
            scaleX: 2, scaleY: 2, shearX: 0, shearY: 0,
            translateX: 0, translateY: 0, unit: .emu
        )
        let update = ElementTransform(
            scaleX: 1, scaleY: 1, shearX: 0, shearY: 0,
            translateX: 10, translateY: 20, unit: .emu
        )

        let result = ElementTransform.concatenate(update, with: existing)

        // B × T keeps the scale and translates by B's own translation, (10, 20).
        // The wrong order, T × B, would scale B's translation to (20, 40), so
        // this case fails loudly if the product is computed backwards.
        XCTAssertEqual(result.scaleX, 2, accuracy: 1e-9)
        XCTAssertEqual(result.scaleY, 2, accuracy: 1e-9)
        XCTAssertEqual(result.translateX, 10, accuracy: 1e-9)
        XCTAssertEqual(result.translateY, 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result.shearX), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result.shearY), 0, accuracy: 1e-9)
        // The result carries the update's unit and all six values.
        XCTAssertEqual(result.unit, .emu)
        assertAllSixSet(result)
    }

    func testConcatenateIsOrderSensitive() {
        // A non-commuting pair: a shear and a scale. B × T and T × B differ, so
        // the helper must not silently compute the reverse.
        let shear = ElementTransform(
            scaleX: 1, scaleY: 1, shearX: 1, shearY: 0,
            translateX: 0, translateY: 0, unit: .emu
        )
        let scale = ElementTransform(
            scaleX: 2, scaleY: 3, shearX: 0, shearY: 0,
            translateX: 0, translateY: 0, unit: .emu
        )

        let bThenT = ElementTransform.concatenate(shear, with: scale) // shear × scale
        let tThenB = ElementTransform.concatenate(scale, with: shear) // scale × shear

        // shear × scale puts the scale's scaleY into shearX (1·3), while
        // scale × shear scales the shear by scaleX (2·1). The two differ.
        XCTAssertEqual(bThenT.shearX ?? .nan, 3, accuracy: 1e-9)
        XCTAssertEqual(tThenB.shearX ?? .nan, 2, accuracy: 1e-9)
        XCTAssertNotEqual(bThenT.shearX ?? .nan, tThenB.shearX ?? .nan)
    }

    // MARK: - Rotation about a known center

    func testRotationBy90AboutCenter() throws {
        let b = ElementTransform.rotation(degrees: 90, aboutX: 100, y: 50, unit: .emu)

        // cos90 = 0, sin90 = 1.
        XCTAssertEqual(b.scaleX, 0, accuracy: 1e-9)
        XCTAssertEqual(b.scaleY, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.shearX), -1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.shearY), 1, accuracy: 1e-9)
        XCTAssertEqual(b.translateX, 150, accuracy: 1e-9)
        XCTAssertEqual(b.translateY, -50, accuracy: 1e-9)
        assertAllSixSet(b)

        // The rotation center is a fixed point.
        let moved = apply(b, x: 100, y: 50)
        XCTAssertEqual(moved.x, 100, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 50, accuracy: 1e-9)
    }

    func testRotationBy180AboutCenter() throws {
        let b = ElementTransform.rotation(degrees: 180, aboutX: 100, y: 50, unit: .emu)

        // cos180 = -1, sin180 = 0.
        XCTAssertEqual(b.scaleX, -1, accuracy: 1e-9)
        XCTAssertEqual(b.scaleY, -1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.shearX), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.shearY), 0, accuracy: 1e-9)
        XCTAssertEqual(b.translateX, 200, accuracy: 1e-9)
        XCTAssertEqual(b.translateY, 100, accuracy: 1e-9)
        assertAllSixSet(b)

        // The center is still fixed under a half turn.
        let moved = apply(b, x: 100, y: 50)
        XCTAssertEqual(moved.x, 100, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 50, accuracy: 1e-9)
    }

    func testRotationDegreesIsClockwiseAndMatchesTheReadFacade() {
        // A positive rotation about the origin yields scaleX = cosθ and
        // shearY = sinθ, exactly the read facade's convention.
        let b = ElementTransform.rotation(degrees: 30, aboutX: 0, y: 0, unit: .emu)
        XCTAssertEqual(b.rotationDegrees, 30, accuracy: 1e-9)
        XCTAssertEqual(
            SlideElementGeometry.rotationDegrees(scaleX: b.scaleX, shearY: b.shearY) ?? .nan,
            30,
            accuracy: 1e-4
        )
    }

    // MARK: - Scale about a center (resize in place)

    func testScaleLeavesTheCenterFixed() throws {
        let b = ElementTransform.scale(x: 2, y: 3, aboutX: 200, aboutY: 100, unit: .emu)

        XCTAssertEqual(b.scaleX, 2, accuracy: 1e-9)
        XCTAssertEqual(b.scaleY, 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.shearX), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.shearY), 0, accuracy: 1e-9)
        XCTAssertEqual(b.translateX, -200, accuracy: 1e-9) // (1 - 2)·200
        XCTAssertEqual(b.translateY, -200, accuracy: 1e-9) // (1 - 3)·100
        assertAllSixSet(b)

        // The point scaled about does not move.
        let moved = apply(b, x: 200, y: 100)
        XCTAssertEqual(moved.x, 200, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 100, accuracy: 1e-9)
    }

    func testScaleAboutElementCenterPreservesTheCenterAfterConcatenation() {
        // A real resize-in-place: read an element's transform, find its center,
        // scale about that center, and left-multiply. The element's center in
        // parent space must not move, because the size is unchanged.
        let existing = ElementTransform(
            scaleX: 1, scaleY: 1, shearX: 0, shearY: 0,
            translateX: 100, translateY: 200, unit: .emu
        )
        let width = 400.0
        let height = 300.0
        let center = ElementTransform.center(of: existing, width: width, height: height)

        let b = ElementTransform.scale(
            x: 1.5, y: 0.5, aboutX: center.x, aboutY: center.y, unit: .emu
        )
        let resized = ElementTransform.concatenate(b, with: existing)

        let newCenter = ElementTransform.center(of: resized, width: width, height: height)
        XCTAssertEqual(newCenter.x, center.x, accuracy: 1e-6)
        XCTAssertEqual(newCenter.y, center.y, accuracy: 1e-6)
    }

    // MARK: - Center

    func testCenterFromScaleAndTranslate() {
        let t = ElementTransform(
            scaleX: 2, scaleY: 2, shearX: 0, shearY: 0,
            translateX: 100, translateY: 200, unit: .emu
        )
        // cx = 2·25 + 0·15 + 100 = 150; cy = 0·25 + 2·15 + 200 = 230.
        let center = ElementTransform.center(of: t, width: 50, height: 30)
        XCTAssertEqual(center.x, 150, accuracy: 1e-9)
        XCTAssertEqual(center.y, 230, accuracy: 1e-9)
    }

    func testCenterAccountsForShear() {
        let t = ElementTransform(
            scaleX: 1, scaleY: 1, shearX: 0.5, shearY: 0.25,
            translateX: 10, translateY: 20, unit: .emu
        )
        // cx = 1·20 + 0.5·40 + 10 = 50; cy = 0.25·20 + 1·40 + 20 = 65.
        let center = ElementTransform.center(of: t, width: 40, height: 80)
        XCTAssertEqual(center.x, 50, accuracy: 1e-9)
        XCTAssertEqual(center.y, 65, accuracy: 1e-9)
    }

    // MARK: - Current rotation

    func testRotationDegreesReadsTheAngleFromTheMatrix() {
        let half = 0.70710678 // cos/sin 45°
        let rotated = ElementTransform(
            scaleX: half, scaleY: half, shearX: -half, shearY: half,
            translateX: 0, translateY: 0, unit: .emu
        )
        XCTAssertEqual(rotated.rotationDegrees, 45, accuracy: 1e-4)

        // A quarter turn: scaleX = 0, shearY = 1 → 90°.
        let quarter = ElementTransform(
            scaleX: 0, scaleY: 0, shearX: -1, shearY: 1,
            translateX: 0, translateY: 0, unit: .emu
        )
        XCTAssertEqual(quarter.rotationDegrees, 90, accuracy: 1e-9)
    }

    func testRotationDegreesTreatsAMissingShearAsZero() {
        // The default init omits both shears; an unrotated element reads as 0°.
        let unrotated = ElementTransform(translateX: 0, translateY: 0, unit: .emu)
        XCTAssertNil(unrotated.shearY)
        XCTAssertEqual(unrotated.rotationDegrees, 0, accuracy: 1e-9)
    }

    func testRotationDegreesIsNegativeForACounterClockwiseTurn() {
        let b = ElementTransform.rotation(degrees: -45, aboutX: 0, y: 0, unit: .emu)
        XCTAssertEqual(b.rotationDegrees, -45, accuracy: 1e-9)
    }

    // MARK: - Exact JSON union encoding

    /// Encodes one union request with the shared encoder (sorted keys).
    private func encode(_ request: SlidesBatchUpdateRequest) throws -> String {
        let data = try GoogleJSON.encoder.encode(request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testUpdatePageElementTransformAbsoluteEncodesAllSixFields() throws {
        let request = SlidesBatchUpdateRequest.updatePageElementTransform(
            UpdatePageElementTransformRequest(
                objectId: "elem-1",
                transform: ElementTransform(
                    scaleX: 2, scaleY: 3, shearX: 0, shearY: 0,
                    translateX: 100, translateY: 200, unit: .emu
                ),
                applyMode: .absolute
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updatePageElementTransform":{"applyMode":"ABSOLUTE","objectId":"elem-1","transform":{"scaleX":2,"scaleY":3,"shearX":0,"shearY":0,"translateX":100,"translateY":200,"unit":"EMU"}}}"#
        )
    }

    func testUpdatePageElementTransformRelativeOmitsNilShears() throws {
        // The default init leaves the shears nil, so a relative update omits
        // them on the wire (Slides treats an omitted shear as 0).
        let request = SlidesBatchUpdateRequest.updatePageElementTransform(
            UpdatePageElementTransformRequest(
                objectId: "elem-2",
                transform: ElementTransform(
                    scaleX: 1, scaleY: 1, translateX: 10, translateY: 20, unit: .emu
                ),
                applyMode: .relative
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updatePageElementTransform":{"applyMode":"RELATIVE","objectId":"elem-2","transform":{"scaleX":1,"scaleY":1,"translateX":10,"translateY":20,"unit":"EMU"}}}"#
        )
    }

    func testUpdatePageElementsZOrderEncodesOperationAndIds() throws {
        let request = SlidesBatchUpdateRequest.updatePageElementsZOrder(
            UpdatePageElementsZOrderRequest(
                pageElementObjectIds: ["a", "b"],
                operation: .bringToFront
            )
        )
        XCTAssertEqual(
            try encode(request),
            #"{"updatePageElementsZOrder":{"operation":"BRING_TO_FRONT","pageElementObjectIds":["a","b"]}}"#
        )
    }

    func testUpdatePageElementsZOrderEncodesEachOperationName() throws {
        func encodedOperation(_ operation: ZOrderOperation) throws -> String {
            try encode(.updatePageElementsZOrder(
                UpdatePageElementsZOrderRequest(pageElementObjectIds: ["x"], operation: operation)
            ))
        }
        XCTAssertTrue(try encodedOperation(.bringForward).contains(#""operation":"BRING_FORWARD""#))
        XCTAssertTrue(try encodedOperation(.sendBackward).contains(#""operation":"SEND_BACKWARD""#))
        XCTAssertTrue(try encodedOperation(.sendToBack).contains(#""operation":"SEND_TO_BACK""#))
    }
}
