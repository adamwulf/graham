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
