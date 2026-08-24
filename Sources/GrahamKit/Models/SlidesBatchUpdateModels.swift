import Foundation

// The models in this file follow the Google Slides v1 `presentations.batchUpdate`
// schema. Unlike the read models, request fields are required when the API
// operation requires them, so an invalid request fails to compile instead of
// failing at the server. Response fields stay optional and decode defensively.

// MARK: - Request union

/// One operation in a `presentations.batchUpdate` call.
///
/// The API takes a list of request objects, and each object sets exactly one
/// operation field: `{"createSlide": {...}}`, `{"deleteObject": {...}}`, and
/// so on. This enum mirrors that union: one case per operation, encoded under
/// the operation's JSON key. Later operations (create element, geometry, text,
/// appearance) join this union as new cases, so every write shares one
/// batch-update path.
public enum SlidesBatchUpdateRequest: Encodable, Sendable, Equatable {
    /// Creates a new slide.
    case createSlide(CreateSlideRequest)
    /// Creates a shape page element.
    case createShape(CreateShapeRequest)
    /// Creates an image page element.
    case createImage(CreateImageRequest)
    /// Creates a video page element.
    case createVideo(CreateVideoRequest)
    /// Creates a line page element.
    case createLine(CreateLineRequest)
    /// Creates a table page element.
    case createTable(CreateTableRequest)
    /// Creates a page element from a Sheets embedded chart.
    case createSheetsChart(CreateSheetsChartRequest)
    /// Groups page elements under a new group object.
    case groupObjects(GroupObjectsRequest)
    /// Removes groups while keeping their children in place.
    case ungroupObjects(UngroupObjectsRequest)
    /// Inserts text into a shape or other text-bearing page element.
    case insertText(InsertTextRequest)
    /// Moves slides to a new position.
    case updateSlidesPosition(UpdateSlidesPositionRequest)
    /// Moves, scales, and rotates a page element by setting its transform.
    case updatePageElementTransform(UpdatePageElementTransformRequest)
    /// Reorders page elements front-to-back on their slide.
    case updatePageElementsZOrder(UpdatePageElementsZOrderRequest)
    /// Deletes a slide or a page element by its exact object id.
    case deleteObject(DeleteObjectRequest)

    private enum CodingKeys: String, CodingKey {
        case createSlide
        case createShape
        case createImage
        case createVideo
        case createLine
        case createTable
        case createSheetsChart
        case groupObjects
        case ungroupObjects
        case insertText
        case updateSlidesPosition
        case updatePageElementTransform
        case updatePageElementsZOrder
        case deleteObject
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createSlide(let request):
            try container.encode(request, forKey: .createSlide)
        case .createShape(let request):
            try container.encode(request, forKey: .createShape)
        case .createImage(let request):
            try container.encode(request, forKey: .createImage)
        case .createVideo(let request):
            try container.encode(request, forKey: .createVideo)
        case .createLine(let request):
            try container.encode(request, forKey: .createLine)
        case .createTable(let request):
            try container.encode(request, forKey: .createTable)
        case .createSheetsChart(let request):
            try container.encode(request, forKey: .createSheetsChart)
        case .groupObjects(let request):
            try container.encode(request, forKey: .groupObjects)
        case .ungroupObjects(let request):
            try container.encode(request, forKey: .ungroupObjects)
        case .insertText(let request):
            try container.encode(request, forKey: .insertText)
        case .updateSlidesPosition(let request):
            try container.encode(request, forKey: .updateSlidesPosition)
        case .updatePageElementTransform(let request):
            try container.encode(request, forKey: .updatePageElementTransform)
        case .updatePageElementsZOrder(let request):
            try container.encode(request, forKey: .updatePageElementsZOrder)
        case .deleteObject(let request):
            try container.encode(request, forKey: .deleteObject)
        }
    }
}

/// The body of a `presentations.batchUpdate` POST.
struct SlidesBatchUpdateRequestBody: Encodable, Sendable {
    let requests: [SlidesBatchUpdateRequest]
}

// MARK: - Operation requests

/// The `createSlide` operation.
///
/// Every field is optional in the API: with no fields set, Google appends a
/// slide with the `BLANK` predefined layout and assigns an object id.
public struct CreateSlideRequest: Codable, Sendable, Equatable {
    /// A user-supplied object id for the new slide. `nil` lets Google assign
    /// one, which the reply then reports.
    public let objectId: String?
    /// The zero-based index to insert the slide at. `nil` appends at the end.
    public let insertionIndex: Int?
    /// The layout of the new slide. `nil` uses the `BLANK` predefined layout.
    public let slideLayoutReference: SlideLayoutReference?

    public init(
        objectId: String? = nil,
        insertionIndex: Int? = nil,
        slideLayoutReference: SlideLayoutReference? = nil
    ) {
        self.objectId = objectId
        self.insertionIndex = insertionIndex
        self.slideLayoutReference = slideLayoutReference
    }
}

/// A reference to a slide layout. Exactly one field is set: a predefined
/// layout name, or the object id of a layout in the presentation.
public struct SlideLayoutReference: Codable, Sendable, Equatable {
    /// A predefined layout name, for example `BLANK` or `TITLE_AND_BODY`.
    public let predefinedLayout: String?
    /// The object id of a layout in the presentation.
    public let layoutId: String?

    public init(predefinedLayout: String) {
        self.predefinedLayout = predefinedLayout
        self.layoutId = nil
    }

    public init(layoutId: String) {
        self.predefinedLayout = nil
        self.layoutId = layoutId
    }
}

/// The `createShape` operation. The shape type and target page are required by
/// the API; size and transform are optional because Google supplies defaults.
public struct CreateShapeRequest: Codable, Sendable, Equatable {
    /// A user-supplied object id for the new shape. `nil` lets Google assign
    /// one, which the reply then reports.
    public let objectId: String?
    /// The page and optional geometry for the new shape.
    public let elementProperties: PageElementProperties
    /// A Slides shape type, for example `TEXT_BOX`.
    public let shapeType: String

    public init(
        objectId: String? = nil,
        elementProperties: PageElementProperties,
        shapeType: String
    ) {
        self.objectId = objectId
        self.elementProperties = elementProperties
        self.shapeType = shapeType
    }
}

/// The `createImage` operation. The target page and source URL are required;
/// size and transform are optional because Google supplies defaults.
///
/// The URL must be public and at most 2 kB. The image may be at most 50 MB and
/// 25 megapixels, and its format must be PNG, JPEG, or GIF.
public struct CreateImageRequest: Codable, Sendable, Equatable {
    public let objectId: String?
    public let elementProperties: PageElementProperties
    public let url: String

    public init(
        objectId: String? = nil,
        elementProperties: PageElementProperties,
        url: String
    ) {
        self.objectId = objectId
        self.elementProperties = elementProperties
        self.url = url
    }
}

/// Sources accepted by the Slides `createVideo` operation.
public enum VideoSource: String, Codable, Sendable {
    case youtube = "YOUTUBE"
    case drive = "DRIVE"
}

/// The `createVideo` operation. A Drive video requires a Drive OAuth scope;
/// graham's default scopes already include one.
public struct CreateVideoRequest: Codable, Sendable, Equatable {
    public let objectId: String?
    public let elementProperties: PageElementProperties
    public let source: VideoSource
    public let id: String

    public init(
        objectId: String? = nil,
        elementProperties: PageElementProperties,
        source: VideoSource,
        id: String
    ) {
        self.objectId = objectId
        self.elementProperties = elementProperties
        self.source = source
        self.id = id
    }
}

/// Categories accepted by the Slides `createLine` operation.
public enum LineCategory: String, Codable, Sendable {
    case straight = "STRAIGHT"
    case bent = "BENT"
    case curved = "CURVED"
}

/// The `createLine` operation.
///
/// The wire key is `category`. The Slides API's separate `lineCategory` field
/// is deprecated and deliberately not modeled here.
public struct CreateLineRequest: Codable, Sendable, Equatable {
    public let objectId: String?
    public let elementProperties: PageElementProperties
    public let category: LineCategory

    public init(
        objectId: String? = nil,
        elementProperties: PageElementProperties,
        category: LineCategory
    ) {
        self.objectId = objectId
        self.elementProperties = elementProperties
        self.category = category
    }
}

/// The `createTable` operation. Rows, columns, and the target page are
/// required by the API.
///
/// A table transform must use scale 1 and no shear. The shared geometry helper
/// in ``SlidesClient`` guarantees that constraint.
public struct CreateTableRequest: Codable, Sendable, Equatable {
    public let objectId: String?
    public let elementProperties: PageElementProperties
    public let rows: Int
    public let columns: Int

    public init(
        objectId: String? = nil,
        elementProperties: PageElementProperties,
        rows: Int,
        columns: Int
    ) {
        self.objectId = objectId
        self.elementProperties = elementProperties
        self.rows = rows
        self.columns = columns
    }
}

/// Linking modes accepted by the Slides `createSheetsChart` operation.
public enum ChartLinkingMode: String, Codable, Sendable {
    case notLinkedImage = "NOT_LINKED_IMAGE"
    case linked = "LINKED"
}

/// The `createSheetsChart` operation. A linked chart requires a Sheets or
/// Drive OAuth scope.
public struct CreateSheetsChartRequest: Codable, Sendable, Equatable {
    public let objectId: String?
    public let elementProperties: PageElementProperties
    public let spreadsheetId: String
    public let chartId: Int
    /// `nil` omits the key and uses the API default, `NOT_LINKED_IMAGE`.
    public let linkingMode: ChartLinkingMode?

    public init(
        objectId: String? = nil,
        elementProperties: PageElementProperties,
        spreadsheetId: String,
        chartId: Int,
        linkingMode: ChartLinkingMode? = nil
    ) {
        self.objectId = objectId
        self.elementProperties = elementProperties
        self.spreadsheetId = spreadsheetId
        self.chartId = chartId
        self.linkingMode = linkingMode
    }
}

/// The `groupObjects` operation.
///
/// At least two children are required. They must all be on the same page and
/// none may already be in a group. Videos, tables, and placeholders cannot be
/// grouped.
public struct GroupObjectsRequest: Codable, Sendable, Equatable {
    public let groupObjectId: String?
    public let childrenObjectIds: [String]

    public init(groupObjectId: String? = nil, childrenObjectIds: [String]) {
        self.groupObjectId = groupObjectId
        self.childrenObjectIds = childrenObjectIds
    }
}

/// The `ungroupObjects` operation.
///
/// Only top-level groups may be ungrouped, and they must all be on the same
/// page. Their children keep their visual positions and the group is deleted.
public struct UngroupObjectsRequest: Codable, Sendable, Equatable {
    public let objectIds: [String]

    public init(objectIds: [String]) {
        self.objectIds = objectIds
    }
}

/// The target page and optional geometry of a newly created page element.
public struct PageElementProperties: Codable, Sendable, Equatable {
    public let pageObjectId: String
    public let size: ElementSize?
    public let transform: ElementTransform?

    public init(
        pageObjectId: String,
        size: ElementSize? = nil,
        transform: ElementTransform? = nil
    ) {
        self.pageObjectId = pageObjectId
        self.size = size
        self.transform = transform
    }
}

/// The required width and height of a write-side page element.
public struct ElementSize: Codable, Sendable, Equatable {
    public let width: ElementDimension
    public let height: ElementDimension

    public init(width: ElementDimension, height: ElementDimension) {
        self.width = width
        self.height = height
    }
}

/// One write-side geometry dimension.
public struct ElementDimension: Codable, Sendable, Equatable {
    public let magnitude: Double
    public let unit: ElementUnit

    public init(magnitude: Double, unit: ElementUnit) {
        self.magnitude = magnitude
        self.unit = unit
    }
}

/// Units accepted by the Slides API for page-element geometry.
public enum ElementUnit: String, Codable, Sendable {
    case emu = "EMU"
    case pt = "PT"
}

/// The affine transform of a write-side page element.
///
/// A transform field omitted on the wire defaults to zero, so an omitted
/// scale makes a degenerate, invisible element. Requiring both scale values
/// prevents such an invalid partial transform from compiling.
public struct ElementTransform: Codable, Sendable, Equatable {
    public let scaleX: Double
    public let scaleY: Double
    public let shearX: Double?
    public let shearY: Double?
    public let translateX: Double
    public let translateY: Double
    public let unit: ElementUnit

    public init(
        scaleX: Double = 1,
        scaleY: Double = 1,
        shearX: Double? = nil,
        shearY: Double? = nil,
        translateX: Double,
        translateY: Double,
        unit: ElementUnit
    ) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.shearX = shearX
        self.shearY = shearY
        self.translateX = translateX
        self.translateY = translateY
        self.unit = unit
    }
}

// MARK: - Transform math (pure, unit-testable)

/// The affine-transform math the geometry edits rely on.
///
/// A transform maps element-local coordinates into the parent's space (the
/// page, or the group for a grouped element), using the Slides matrix layout:
///
///     | scaleX  shearX  translateX |     | a  c  tx |
///     | shearY  scaleY  translateY |  =  | b  d  ty |
///     | 0       0       1          |     | 0  0  1  |
///
/// Every helper here is pure and unit-agnostic: the math runs in whatever unit
/// the caller supplies, because the Slides API does not convert units between a
/// transform update and an element's existing transform. Each helper that
/// returns a transform sets all six matrix fields explicitly (shears included,
/// even when 0), so a computed result never relies on the wire model's
/// omit-shear default.
extension ElementTransform {
    /// The `a`, `b`, `c`, `d`, `tx`, `ty` matrix entries, with a missing shear
    /// read as 0 (the scale and translate fields are always present on the
    /// write-side transform). Named to match the matrix layout above
    /// (`a = scaleX`, `b = shearY`, `c = shearX`, `d = scaleY`).
    private var matrix: (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        (a: scaleX, b: shearY ?? 0, c: shearX ?? 0, d: scaleY, tx: translateX, ty: translateY)
    }

    /// Concatenates `update × existing`: the transform that applies `existing`
    /// first and then `update` (the API's `RELATIVE` semantics, `B × T`).
    ///
    /// Order matters — `update × existing` is not `existing × update`. The
    /// result carries `update`'s unit; the caller must ensure both transforms
    /// share that unit, because affine concatenation mixes their translations
    /// and the API never converts units.
    public static func concatenate(
        _ update: ElementTransform,
        with existing: ElementTransform
    ) -> ElementTransform {
        let b = update.matrix
        let t = existing.matrix
        // Standard 3×3 affine product B × T.
        let a = b.a * t.a + b.c * t.b
        let c = b.a * t.c + b.c * t.d
        let bb = b.b * t.a + b.d * t.b
        let d = b.b * t.c + b.d * t.d
        let tx = b.a * t.tx + b.c * t.ty + b.tx
        let ty = b.b * t.tx + b.d * t.ty + b.ty
        return ElementTransform(
            scaleX: a,
            scaleY: d,
            shearX: c,
            shearY: bb,
            translateX: tx,
            translateY: ty,
            unit: update.unit
        )
    }

    /// The element's center in the parent's coordinate space, given the raw
    /// (unscaled) size. `cx = a·(w/2) + c·(h/2) + tx`,
    /// `cy = b·(w/2) + d·(h/2) + ty`.
    public static func center(
        of transform: ElementTransform,
        width: Double,
        height: Double
    ) -> (x: Double, y: Double) {
        let m = transform.matrix
        let halfWidth = width / 2
        let halfHeight = height / 2
        let x = m.a * halfWidth + m.c * halfHeight + m.tx
        let y = m.b * halfWidth + m.d * halfHeight + m.ty
        return (x: x, y: y)
    }

    /// A rotation by `degrees` about the point `(aboutX, y)`, positive degrees
    /// rotating clockwise on screen (y grows downward), matching the read
    /// facade's `SlideElementGeometry.rotationDegrees`.
    ///
    /// Left-multiply the result onto the element's existing transform (or use
    /// it directly with an already-composed transform) to rotate the element
    /// about that fixed point.
    public static func rotation(
        degrees: Double,
        aboutX: Double,
        y aboutY: Double,
        unit: ElementUnit
    ) -> ElementTransform {
        let theta = degrees * .pi / 180
        let cosTheta = cos(theta)
        let sinTheta = sin(theta)
        // B rotates about (aboutX, aboutY): translate to origin, rotate, back.
        return ElementTransform(
            scaleX: cosTheta,
            scaleY: cosTheta,
            shearX: -sinTheta,
            shearY: sinTheta,
            translateX: aboutX - aboutX * cosTheta + aboutY * sinTheta,
            translateY: aboutY - aboutX * sinTheta - aboutY * cosTheta,
            unit: unit
        )
    }

    /// A scale by `(x, y)` about the point `(aboutX, aboutY)`, which leaves that
    /// point fixed (resize-in-place when the point is the element center).
    public static func scale(
        x: Double,
        y: Double,
        aboutX: Double,
        aboutY: Double,
        unit: ElementUnit
    ) -> ElementTransform {
        // B scales about (aboutX, aboutY), so the fixed point does not move.
        ElementTransform(
            scaleX: x,
            scaleY: y,
            shearX: 0,
            shearY: 0,
            translateX: (1 - x) * aboutX,
            translateY: (1 - y) * aboutY,
            unit: unit
        )
    }

    /// The current rotation of this transform in degrees: `atan2(b, a)`, that
    /// is `atan2(shearY, scaleX)`, with a missing shear read as 0.
    ///
    /// This mirrors ``SlideElementGeometry/rotationDegrees(scaleX:shearY:)`` but
    /// stays unrounded, so a `rotate --to` delta (`target − current`) is exact.
    public var rotationDegrees: Double {
        atan2(shearY ?? 0, scaleX) * 180 / .pi
    }
}

/// The `insertText` operation. The insertion index is required by the API and
/// defaults to the start of the element's text.
public struct InsertTextRequest: Codable, Sendable, Equatable {
    public let objectId: String
    public let text: String
    public let insertionIndex: Int

    public init(objectId: String, text: String, insertionIndex: Int = 0) {
        self.objectId = objectId
        self.text = text
        self.insertionIndex = insertionIndex
    }
}

/// The `updateSlidesPosition` operation. Both fields are required by the API.
///
/// `insertionIndex` is zero-based and refers to the slide order **before** the
/// move. Callers use ``SlidesClient/moveSlide(presentationId:slideId:to:)``,
/// which translates a one-based final position into this index.
public struct UpdateSlidesPositionRequest: Codable, Sendable, Equatable {
    /// The object ids of the slides to move, in their current relative order.
    public let slideObjectIds: [String]
    /// The zero-based insertion index, based on the order before the move.
    public let insertionIndex: Int

    public init(slideObjectIds: [String], insertionIndex: Int) {
        self.slideObjectIds = slideObjectIds
        self.insertionIndex = insertionIndex
    }
}

/// How an `updatePageElementTransform` operation applies its matrix.
///
/// `RELATIVE` left-multiplies the update matrix `B` onto the element's existing
/// transform `T`, giving `B × T`. `ABSOLUTE` replaces `T` with the update
/// matrix outright. The API never accepts an unspecified mode, so this enum has
/// no default and both cases are always sent.
public enum TransformApplyMode: String, Codable, Sendable {
    case relative = "RELATIVE"
    case absolute = "ABSOLUTE"
}

/// The `updatePageElementTransform` operation. Every field is required by the
/// API.
///
/// The API does not convert units between the update matrix and the element's
/// existing transform, so a `RELATIVE` update must be expressed in the same
/// unit as the element already uses. graham's computed edits therefore read the
/// element, do the math in its native unit, and send one precomputed
/// `ABSOLUTE` transform (Google's documented recommendation).
public struct UpdatePageElementTransformRequest: Codable, Sendable, Equatable {
    /// The object id of the page element to transform.
    public let objectId: String
    /// The affine transform to apply, interpreted per ``applyMode``.
    public let transform: ElementTransform
    /// Whether the transform is left-multiplied onto the element's existing
    /// transform (`RELATIVE`) or replaces it (`ABSOLUTE`).
    public let applyMode: TransformApplyMode

    public init(
        objectId: String,
        transform: ElementTransform,
        applyMode: TransformApplyMode
    ) {
        self.objectId = objectId
        self.transform = transform
        self.applyMode = applyMode
    }
}

/// The front-to-back reorder operations of `updatePageElementsZOrder`.
///
/// `BRING_FORWARD` and `SEND_BACKWARD` move by one step; `BRING_TO_FRONT` and
/// `SEND_TO_BACK` move all the way. When several elements are reordered at once
/// their relative order among themselves is preserved.
public enum ZOrderOperation: String, Codable, Sendable {
    case bringToFront = "BRING_TO_FRONT"
    case bringForward = "BRING_FORWARD"
    case sendBackward = "SEND_BACKWARD"
    case sendToBack = "SEND_TO_BACK"
}

/// The `updatePageElementsZOrder` operation. Both fields are required by the
/// API.
///
/// All the given page elements must be on the same page and none may be
/// grouped. When several are given their relative order is kept.
public struct UpdatePageElementsZOrderRequest: Codable, Sendable, Equatable {
    /// The object ids of the page elements to reorder, all on the same page.
    public let pageElementObjectIds: [String]
    /// The reorder operation to apply.
    public let operation: ZOrderOperation

    public init(pageElementObjectIds: [String], operation: ZOrderOperation) {
        self.pageElementObjectIds = pageElementObjectIds
        self.operation = operation
    }
}

/// The `deleteObject` operation. The API requires the object id, and it must
/// be a slide or a page element in the presentation.
public struct DeleteObjectRequest: Codable, Sendable, Equatable {
    public let objectId: String

    public init(objectId: String) {
        self.objectId = objectId
    }
}

// MARK: - Response

/// The response of a `presentations.batchUpdate` call.
public struct SlidesBatchUpdateResponse: Codable, Sendable {
    public let presentationId: String?
    /// One reply per request, in request order. An operation with no return
    /// value (for example a move or a delete) gets an empty reply object, so
    /// a caller must not require an object id in every reply.
    public let replies: [SlidesBatchUpdateReply]?
}

/// One reply in a batch-update response. Each field matches the request case
/// with the same name; an operation with nothing to report sets none of them.
public struct SlidesBatchUpdateReply: Codable, Sendable {
    public let createSlide: CreateSlideReply?
    public let createShape: CreateShapeReply?
    public let createImage: CreateImageReply?
    public let createVideo: CreateVideoReply?
    public let createLine: CreateLineReply?
    public let createTable: CreateTableReply?
    public let createSheetsChart: CreateSheetsChartReply?
    public let groupObjects: GroupObjectsReply?
}

/// The reply of a `createSlide` operation.
public struct CreateSlideReply: Codable, Sendable {
    /// The object id of the new slide.
    public let objectId: String?
}

/// The reply of a `createShape` operation.
public struct CreateShapeReply: Codable, Sendable {
    /// The object id of the new shape.
    public let objectId: String?
}

/// The reply of a `createImage` operation.
public struct CreateImageReply: Codable, Sendable {
    public let objectId: String?
}

/// The reply of a `createVideo` operation.
public struct CreateVideoReply: Codable, Sendable {
    public let objectId: String?
}

/// The reply of a `createLine` operation.
public struct CreateLineReply: Codable, Sendable {
    public let objectId: String?
}

/// The reply of a `createTable` operation.
public struct CreateTableReply: Codable, Sendable {
    public let objectId: String?
}

/// The reply of a `createSheetsChart` operation.
public struct CreateSheetsChartReply: Codable, Sendable {
    public let objectId: String?
}

/// The reply of a `groupObjects` operation.
public struct GroupObjectsReply: Codable, Sendable {
    public let objectId: String?
}
