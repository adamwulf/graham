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
    /// Moves slides to a new position.
    case updateSlidesPosition(UpdateSlidesPositionRequest)
    /// Deletes a slide or a page element by its exact object id.
    case deleteObject(DeleteObjectRequest)

    private enum CodingKeys: String, CodingKey {
        case createSlide
        case updateSlidesPosition
        case deleteObject
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createSlide(let request):
            try container.encode(request, forKey: .createSlide)
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
}

/// The reply of a `createSlide` operation.
public struct CreateSlideReply: Codable, Sendable {
    /// The object id of the new slide.
    public let objectId: String?
}
