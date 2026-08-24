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
    /// Sets a shape's fill, outline, shadow, and content alignment.
    case updateShapeProperties(UpdateShapePropertiesRequest)
    /// Sets an image's outline (the only appearance the API lets a write set).
    case updateImageProperties(UpdateImagePropertiesRequest)
    /// Sets a line's fill, weight, dash style, and arrow ends.
    case updateLineProperties(UpdateLinePropertiesRequest)
    /// Sets a video's playback options and outline.
    case updateVideoProperties(UpdateVideoPropertiesRequest)
    /// Refreshes a linked Sheets chart to its latest data.
    case refreshSheetsChart(RefreshSheetsChartRequest)
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
        case updateShapeProperties
        case updateImageProperties
        case updateLineProperties
        case updateVideoProperties
        case refreshSheetsChart
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
        case .updateShapeProperties(let request):
            try container.encode(request, forKey: .updateShapeProperties)
        case .updateImageProperties(let request):
            try container.encode(request, forKey: .updateImageProperties)
        case .updateLineProperties(let request):
            try container.encode(request, forKey: .updateLineProperties)
        case .updateVideoProperties(let request):
            try container.encode(request, forKey: .updateVideoProperties)
        case .refreshSheetsChart(let request):
            try container.encode(request, forKey: .refreshSheetsChart)
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

// MARK: - Element style values (write side)
//
// These mirror the Slides v1 appearance schema used by the `update*Properties`
// requests. They are the write-side counterparts of the `Slide`-prefixed read
// models in `SlidesModels.swift`; the two sets are kept separate on purpose so
// the write side can make a field required when the operation requires it and
// omit read-only fields entirely.

/// The theme colors the Slides API recognizes for an ``OpaqueColor``.
///
/// The cases are the sixteen values verified against the Slides v1 discovery
/// document; the raw values are the exact wire spellings.
public enum ThemeColorName: String, Codable, Sendable {
    case dark1 = "DARK1"
    case light1 = "LIGHT1"
    case dark2 = "DARK2"
    case light2 = "LIGHT2"
    case accent1 = "ACCENT1"
    case accent2 = "ACCENT2"
    case accent3 = "ACCENT3"
    case accent4 = "ACCENT4"
    case accent5 = "ACCENT5"
    case accent6 = "ACCENT6"
    case hyperlink = "HYPERLINK"
    case followedHyperlink = "FOLLOWED_HYPERLINK"
    case text1 = "TEXT1"
    case background1 = "BACKGROUND1"
    case text2 = "TEXT2"
    case background2 = "BACKGROUND2"
}

/// An explicit RGB color. Each channel is a float from 0 to 1.
public struct RgbColor: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// A solid color: exactly one of an explicit RGB color or a theme color.
///
/// The one-of is enforced by the two inits, following the ``SlideLayoutReference``
/// precedent: whichever init a caller uses, the other field stays `nil` and is
/// omitted on the wire, so the value encodes as either
/// `{"rgbColor":{...}}` or `{"themeColor":"ACCENT1"}`.
public struct OpaqueColor: Codable, Sendable, Equatable {
    public let rgbColor: RgbColor?
    public let themeColor: ThemeColorName?

    /// An explicit RGB color. Each channel is a float from 0 to 1.
    public init(red: Double, green: Double, blue: Double) {
        self.rgbColor = RgbColor(red: red, green: green, blue: blue)
        self.themeColor = nil
    }

    /// A named theme color.
    public init(theme: ThemeColorName) {
        self.rgbColor = nil
        self.themeColor = theme
    }

    /// Parses a color from a CLI-friendly string.
    ///
    /// This is the one color-parsing seam for the whole tool; the CLI never
    /// parses colors itself. Accepted forms:
    ///
    /// - A hex color, with an optional leading `#`, either `RRGGBB` or the
    ///   short `RGB` form (each nibble is doubled, so `#F00` is `#FF0000`).
    ///   Hex is case-insensitive and each channel maps to `component / 255`.
    /// - A theme color name, matched case-insensitively (`accent1`, `DARK1`).
    ///
    /// Anything else throws ``GrahamError/invalidArgument(_:)`` naming the
    /// input.
    public static func parse(_ input: String) throws -> OpaqueColor {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexBody = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if let rgb = parseHex(hexBody) {
            return rgb
        }
        if let theme = ThemeColorName(rawValue: trimmed.uppercased()) {
            return OpaqueColor(theme: theme)
        }
        throw GrahamError.invalidArgument(
            "could not parse \"\(input)\" as a color; use a hex value like #FF0000 "
            + "or #F00, or a theme color name like accent1")
    }

    /// Parses a bare hex body (no `#`) of exactly three or six hex digits,
    /// returning `nil` for any other length or a non-hex character so the
    /// caller can fall through to a theme-name lookup.
    private static func parseHex(_ hex: String) -> OpaqueColor? {
        let normalized: String
        switch hex.count {
        case 3:
            // Expand each nibble: F00 -> FF0000.
            normalized = hex.map { "\($0)\($0)" }.joined()
        case 6:
            normalized = hex
        default:
            return nil
        }
        let digits = Array(normalized)
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        func channel(_ start: Int) -> Double {
            Double(Int(String(digits[start..<start + 2]), radix: 16) ?? 0) / 255
        }
        return OpaqueColor(red: channel(0), green: channel(2), blue: channel(4))
    }
}

/// A solid color fill with an optional opacity.
public struct SolidFill: Codable, Sendable, Equatable {
    public let color: OpaqueColor?
    /// The opacity, from 0 to 1.
    public let alpha: Double?

    public init(color: OpaqueColor? = nil, alpha: Double? = nil) {
        self.color = color
        self.alpha = alpha
    }
}

/// The render state of a fill, outline, or shadow.
public enum PropertyState: String, Codable, Sendable {
    case rendered = "RENDERED"
    case notRendered = "NOT_RENDERED"
    case inherit = "INHERIT"
}

/// A shape's background fill.
///
/// Updating the `solidFill` implicitly renders the fill; a caller that wants
/// to clear a fill sets ``propertyState`` to ``PropertyState/notRendered``.
public struct ShapeBackgroundFill: Codable, Sendable, Equatable {
    public let propertyState: PropertyState?
    public let solidFill: SolidFill?

    public init(propertyState: PropertyState? = nil, solidFill: SolidFill? = nil) {
        self.propertyState = propertyState
        self.solidFill = solidFill
    }
}

/// The dash style of an outline or a line.
public enum DashStyle: String, Codable, Sendable {
    case solid = "SOLID"
    case dot = "DOT"
    case dash = "DASH"
    case dashDot = "DASH_DOT"
    case longDash = "LONG_DASH"
    case longDashDot = "LONG_DASH_DOT"
}

/// The fill of an outline.
public struct OutlineFill: Codable, Sendable, Equatable {
    public let solidFill: SolidFill

    public init(solidFill: SolidFill) {
        self.solidFill = solidFill
    }
}

/// The outline (border) of a shape, image, or video.
public struct Outline: Codable, Sendable, Equatable {
    public let outlineFill: OutlineFill?
    public let weight: ElementDimension?
    public let dashStyle: DashStyle?
    public let propertyState: PropertyState?

    public init(
        outlineFill: OutlineFill? = nil,
        weight: ElementDimension? = nil,
        dashStyle: DashStyle? = nil,
        propertyState: PropertyState? = nil
    ) {
        self.outlineFill = outlineFill
        self.weight = weight
        self.dashStyle = dashStyle
        self.propertyState = propertyState
    }
}

/// A drop shadow.
///
/// Only the fields the Slides API accepts on a write are modeled. The API's
/// `type`, `alignment`, and `rotateWithShape` are read-only and deliberately
/// absent here.
public struct Shadow: Codable, Sendable, Equatable {
    public let color: OpaqueColor?
    /// The opacity of the shadow, from 0 to 1.
    public let alpha: Double?
    public let blurRadius: ElementDimension?
    public let transform: ElementTransform?
    public let propertyState: PropertyState?

    public init(
        color: OpaqueColor? = nil,
        alpha: Double? = nil,
        blurRadius: ElementDimension? = nil,
        transform: ElementTransform? = nil,
        propertyState: PropertyState? = nil
    ) {
        self.color = color
        self.alpha = alpha
        self.blurRadius = blurRadius
        self.transform = transform
        self.propertyState = propertyState
    }
}

/// The fill of a line.
public struct LineFill: Codable, Sendable, Equatable {
    public let solidFill: SolidFill

    public init(solidFill: SolidFill) {
        self.solidFill = solidFill
    }
}

/// The arrow style at a line's start or end.
public enum ArrowStyle: String, Codable, Sendable {
    case none = "NONE"
    case stealthArrow = "STEALTH_ARROW"
    case fillArrow = "FILL_ARROW"
    case fillCircle = "FILL_CIRCLE"
    case fillSquare = "FILL_SQUARE"
    case fillDiamond = "FILL_DIAMOND"
    case openArrow = "OPEN_ARROW"
    case openCircle = "OPEN_CIRCLE"
    case openSquare = "OPEN_SQUARE"
    case openDiamond = "OPEN_DIAMOND"
}

/// The vertical alignment of a shape's text.
public enum ContentAlignment: String, Codable, Sendable {
    case top = "TOP"
    case middle = "MIDDLE"
    case bottom = "BOTTOM"
}

/// The writable subset of a shape's appearance.
///
/// Every field is optional; the request's field mask, not this container,
/// decides which properties the API applies.
public struct ShapeStyle: Codable, Sendable, Equatable {
    public let shapeBackgroundFill: ShapeBackgroundFill?
    public let outline: Outline?
    public let shadow: Shadow?
    public let contentAlignment: ContentAlignment?

    public init(
        shapeBackgroundFill: ShapeBackgroundFill? = nil,
        outline: Outline? = nil,
        shadow: Shadow? = nil,
        contentAlignment: ContentAlignment? = nil
    ) {
        self.shapeBackgroundFill = shapeBackgroundFill
        self.outline = outline
        self.shadow = shadow
        self.contentAlignment = contentAlignment
    }
}

/// The writable subset of an image's appearance.
///
/// The Slides API only lets a write set an image's `outline` (and its link,
/// which belongs to a later milestone). `cropProperties`, `transparency`,
/// `brightness`, `contrast`, `recolor`, and `shadow` are all read-only in the
/// API, so they are not modeled on the write side.
public struct ImageStyle: Codable, Sendable, Equatable {
    public let outline: Outline?

    public init(outline: Outline? = nil) {
        self.outline = outline
    }
}

/// The writable subset of a line's appearance.
///
/// `startConnection`, `endConnection`, and `link` are left out of this slice.
public struct LineStyle: Codable, Sendable, Equatable {
    public let lineFill: LineFill?
    public let weight: ElementDimension?
    public let dashStyle: DashStyle?
    public let startArrow: ArrowStyle?
    public let endArrow: ArrowStyle?

    public init(
        lineFill: LineFill? = nil,
        weight: ElementDimension? = nil,
        dashStyle: DashStyle? = nil,
        startArrow: ArrowStyle? = nil,
        endArrow: ArrowStyle? = nil
    ) {
        self.lineFill = lineFill
        self.weight = weight
        self.dashStyle = dashStyle
        self.startArrow = startArrow
        self.endArrow = endArrow
    }
}

/// The writable subset of a video's appearance and playback.
///
/// `start` and `end` are whole seconds into the clip.
public struct VideoStyle: Codable, Sendable, Equatable {
    public let autoPlay: Bool?
    public let mute: Bool?
    public let start: Int?
    public let end: Int?
    public let outline: Outline?

    public init(
        autoPlay: Bool? = nil,
        mute: Bool? = nil,
        start: Int? = nil,
        end: Int? = nil,
        outline: Outline? = nil
    ) {
        self.autoPlay = autoPlay
        self.mute = mute
        self.start = start
        self.end = end
        self.outline = outline
    }
}

// MARK: - Element style operation requests

/// The `updateShapeProperties` operation. `fields` is a comma-separated field
/// mask of the ``ShapeStyle`` paths to apply; at least one path is required.
public struct UpdateShapePropertiesRequest: Codable, Sendable, Equatable {
    public let objectId: String
    public let shapeProperties: ShapeStyle
    public let fields: String

    public init(objectId: String, shapeProperties: ShapeStyle, fields: String) {
        self.objectId = objectId
        self.shapeProperties = shapeProperties
        self.fields = fields
    }
}

/// The `updateImageProperties` operation. `fields` is a comma-separated field
/// mask of the ``ImageStyle`` paths to apply; at least one path is required.
public struct UpdateImagePropertiesRequest: Codable, Sendable, Equatable {
    public let objectId: String
    public let imageProperties: ImageStyle
    public let fields: String

    public init(objectId: String, imageProperties: ImageStyle, fields: String) {
        self.objectId = objectId
        self.imageProperties = imageProperties
        self.fields = fields
    }
}

/// The `updateLineProperties` operation. `fields` is a comma-separated field
/// mask of the ``LineStyle`` paths to apply; at least one path is required.
public struct UpdateLinePropertiesRequest: Codable, Sendable, Equatable {
    public let objectId: String
    public let lineProperties: LineStyle
    public let fields: String

    public init(objectId: String, lineProperties: LineStyle, fields: String) {
        self.objectId = objectId
        self.lineProperties = lineProperties
        self.fields = fields
    }
}

/// The `updateVideoProperties` operation. `fields` is a comma-separated field
/// mask of the ``VideoStyle`` paths to apply; at least one path is required.
public struct UpdateVideoPropertiesRequest: Codable, Sendable, Equatable {
    public let objectId: String
    public let videoProperties: VideoStyle
    public let fields: String

    public init(objectId: String, videoProperties: VideoStyle, fields: String) {
        self.objectId = objectId
        self.videoProperties = videoProperties
        self.fields = fields
    }
}

/// The `refreshSheetsChart` operation. The API takes only the object id, and
/// it works only on a chart that was embedded with `LINKED` linking mode.
public struct RefreshSheetsChartRequest: Codable, Sendable, Equatable {
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
