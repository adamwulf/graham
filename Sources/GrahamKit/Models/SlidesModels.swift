import Foundation

// The models in this file follow the Google Slides v1 REST schema. graham
// reads presentations, so every field is optional except a true invariant.
// Google can add fields, so the decoder ignores fields that this file does
// not model. Property names are equal to the JSON keys, so no `CodingKeys`
// map is necessary.

// MARK: - Presentation and pages

/// A Google Slides presentation.
public struct Presentation: Codable, Sendable {
    public let presentationId: String?
    public let title: String?
    public let slides: [SlidePage]?
    /// The slide layouts a new slide can be created from.
    public let layouts: [SlideLayoutPage]?
}

/// One slide layout in a presentation.
///
/// A layout is a template a slide can be created from. graham reads its object
/// id and name; a layout id feeds `slides add --layout-id`.
public struct SlideLayoutPage: Codable, Sendable {
    public let objectId: String?
    public let layoutProperties: SlideLayoutProperties?
}

/// The properties of a slide layout.
public struct SlideLayoutProperties: Codable, Sendable {
    /// The API name of the layout, for example `TITLE_AND_BODY`.
    public let name: String?
    /// The human-readable name of the layout.
    public let displayName: String?
    /// The object id of the master this layout belongs to.
    public let masterObjectId: String?
}

/// One slide (a page) in a presentation.
public struct SlidePage: Codable, Sendable {
    public let objectId: String?
    public let pageElements: [PageElement]?
    /// The slide-level properties graham reads: its notes page.
    public let slideProperties: SlideSlideProperties?

    /// All visible text on the slide, one text block per line.
    ///
    /// Each shape gives its text. A table gives its cells, with a tab between
    /// the cells in a row and a new line between the rows. A group gives the
    /// text of its children, and this includes groups inside groups. Word art
    /// gives its rendered text. Elements with no text add nothing.
    public var plainText: String {
        (pageElements ?? [])
            .map(\.plainText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - Speaker notes
//
// A slide's `slideProperties.notesPage` is itself a full `Page`, but a
// `SlidePage` cannot contain another `SlidePage` without becoming recursive.
// graham only needs the notes shape id and its text, so these reduced,
// non-recursive types model just that slice. The notes page is read-only:
// notes are edited through the normal text operations against the speaker-notes
// shape id, in the same batch update as any other write.

/// The reduced slide-level properties graham reads: a slide's notes page.
public struct SlideSlideProperties: Codable, Sendable {
    public let notesPage: SlideNotesPage?
}

/// A slide's notes page, holding the speaker-notes shape.
///
/// ``notesProperties`` names the speaker-notes shape, and ``pageElements``
/// holds that shape among any others. Google notes that the shape "may not
/// always exist on the notes page — inserting text using this object ID will
/// automatically create the shape", so the element may be absent until notes
/// are first set.
public struct SlideNotesPage: Codable, Sendable {
    public let objectId: String?
    public let notesProperties: SlideNotesProperties?
    public let pageElements: [PageElement]?
}

/// The notes-page properties: the object id of the speaker-notes shape.
public struct SlideNotesProperties: Codable, Sendable {
    public let speakerNotesObjectId: String?
}

// MARK: - Page element

/// One element on a slide.
///
/// A page element has common properties (`objectId`, `size`, `transform`,
/// `title`, `description`) and is exactly one type. The type property that is
/// set tells you which type it is; ``kind`` reports this. Alt text is in
/// `title` and `description`.
public struct PageElement: Codable, Sendable {
    // Common properties.
    public let objectId: String?
    public let size: SlideSize?
    public let transform: SlideTransform?
    /// The alt-text title.
    public let title: String?
    /// The alt-text description.
    public let description: String?

    // Element type. Exactly one of these is set.
    public let elementGroup: SlideGroup?
    public let shape: SlideShape?
    public let image: SlideImage?
    public let video: SlideVideo?
    public let line: SlideLine?
    public let table: SlideTable?
    public let sheetsChart: SlideSheetsChart?
    public let wordArt: SlideWordArt?
    public let speakerSpotlight: SlideSpeakerSpotlight?

    /// The type of this element. `.unknown` if no known type is set, for
    /// example when Google adds a new type.
    public var kind: PageElementKind {
        if elementGroup != nil { return .group }
        if shape != nil { return .shape }
        if image != nil { return .image }
        if video != nil { return .video }
        if line != nil { return .line }
        if table != nil { return .table }
        if sheetsChart != nil { return .sheetsChart }
        if wordArt != nil { return .wordArt }
        if speakerSpotlight != nil { return .speakerSpotlight }
        return .unknown
    }

    /// The text this element adds to ``SlidePage/plainText``. Empty if the
    /// element has no text. Internal, like the other per-element text helpers;
    /// callers read the public ``SlidePage/plainText``.
    var plainText: String {
        if let shape { return shape.text?.plainText ?? "" }
        if let table { return table.plainText }
        if let wordArt {
            // Trim like shape and table text, so all sources are consistent.
            return (wordArt.renderedText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let elementGroup {
            return (elementGroup.children ?? [])
                .map(\.plainText)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        return ""
    }
}

/// The type of a page element.
public enum PageElementKind: String, Codable, Sendable, Equatable {
    case group
    case shape
    case image
    case video
    case line
    case table
    case sheetsChart
    case wordArt
    case speakerSpotlight
    case unknown
}

// MARK: - Geometry

/// The width and height of an element.
public struct SlideSize: Codable, Sendable {
    public let width: SlideDimension?
    public let height: SlideDimension?
}

/// A length: a magnitude and its unit (`EMU` or `PT`).
public struct SlideDimension: Codable, Sendable {
    public let magnitude: Double?
    public let unit: String?
}

/// The position, scale, and rotation of an element.
///
/// This is an affine transform. The position is `translateX` and
/// `translateY`. The scale is `scaleX` and `scaleY`. The rotation and any
/// skew come from `shearX` and `shearY` together with the scale. A reader
/// computes the rotation angle from these fields.
///
/// The coordinate space depends on the parent. For an element that is not in
/// a group, the transform maps the element to the page. For a child of a
/// group, the transform maps the child into the group coordinate space; the
/// group transform then maps the group to the page. To get the child position
/// on the page, combine the two transforms.
public struct SlideTransform: Codable, Sendable {
    public let scaleX: Double?
    public let scaleY: Double?
    public let shearX: Double?
    public let shearY: Double?
    public let translateX: Double?
    public let translateY: Double?
    public let unit: String?
}

// MARK: - Group

/// A group of page elements. A group can hold more groups.
public struct SlideGroup: Codable, Sendable {
    public let children: [PageElement]?
}

// MARK: - Shape (text boxes, placeholders, and other shapes)

/// A shape. This includes text boxes, text blocks, and placeholders.
public struct SlideShape: Codable, Sendable {
    /// The shape type, for example `TEXT_BOX` or `RECTANGLE`.
    public let shapeType: String?
    public let text: SlideText?
    public let placeholder: SlidePlaceholder?
    public let shapeProperties: SlideShapeProperties?
}

/// The placeholder role of a shape on a layout or a slide.
public struct SlidePlaceholder: Codable, Sendable {
    /// The placeholder type, for example `TITLE` or `BODY`.
    public let type: String?
    public let index: Int?
    public let parentObjectId: String?
}

/// The properties of a shape. graham reads the link.
public struct SlideShapeProperties: Codable, Sendable {
    public let link: SlideLink?
}

// MARK: - Text

/// The text in a shape or a table cell.
public struct SlideText: Codable, Sendable {
    public let textElements: [SlideTextElement]?

    /// The text of all runs, joined and trimmed. Auto-text (for example a
    /// slide number) and paragraph markers add nothing, so the result is the
    /// text the user typed.
    var plainText: String {
        (textElements ?? [])
            .compactMap { $0.textRun?.content }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One part of the text: a text run, a paragraph marker, or auto-text.
public struct SlideTextElement: Codable, Sendable {
    public let startIndex: Int?
    public let endIndex: Int?
    public let paragraphMarker: SlideParagraphMarker?
    public let textRun: SlideTextRun?
    public let autoText: SlideAutoText?
}

/// The start of a paragraph. graham does not read its style yet.
public struct SlideParagraphMarker: Codable, Sendable {}

/// A run of text with one style.
public struct SlideTextRun: Codable, Sendable {
    public let content: String?
    public let style: SlideTextStyle?
}

/// Text that Google fills in, for example a slide number.
public struct SlideAutoText: Codable, Sendable {
    /// The auto-text type, for example `SLIDE_NUMBER`.
    public let type: String?
    public let content: String?
    public let style: SlideTextStyle?
}

/// The style of a text run. graham reads the link (the hyperlink).
public struct SlideTextStyle: Codable, Sendable {
    public let link: SlideLink?
}

/// A hyperlink. Exactly one target field is set.
public struct SlideLink: Codable, Sendable {
    /// A link to a web page.
    public let url: String?
    /// A link to another slide by relation, for example `NEXT_SLIDE`.
    public let relativeLink: String?
    /// A link to a slide by its object id.
    public let pageObjectId: String?
    /// A link to a slide by its zero-based index.
    public let slideIndex: Int?
}

// MARK: - Image

/// An image.
public struct SlideImage: Codable, Sendable {
    /// A URL to the image. The URL is short-lived.
    public let contentUrl: String?
    /// The URL the image came from, if Google keeps it.
    public let sourceUrl: String?
    public let imageProperties: SlideImageProperties?
    /// Set when the image fills a picture placeholder from a layout or a
    /// master. The image then inherits from that parent placeholder.
    public let placeholder: SlidePlaceholder?
}

/// The properties of an image. graham reads the link.
public struct SlideImageProperties: Codable, Sendable {
    public let link: SlideLink?
}

// MARK: - Video

/// A video from YouTube or Google Drive.
public struct SlideVideo: Codable, Sendable {
    /// The video URL.
    public let url: String?
    /// The video source, for example `YOUTUBE` or `DRIVE`.
    public let source: String?
    /// The video id at the source.
    public let id: String?
    public let videoProperties: SlideVideoProperties?
}

/// The properties of a video.
public struct SlideVideoProperties: Codable, Sendable {
    public let autoPlay: Bool?
    public let mute: Bool?
    public let start: Int?
    public let end: Int?
}

// MARK: - Line and connector

/// A line or a connector.
public struct SlideLine: Codable, Sendable {
    /// The line type, for example `STRAIGHT_CONNECTOR_1`.
    public let lineType: String?
    /// The line category, for example `STRAIGHT`, `BENT`, or `CURVED`.
    public let lineCategory: String?
    public let lineProperties: SlideLineProperties?
}

/// The properties of a line. graham reads the link.
public struct SlideLineProperties: Codable, Sendable {
    public let link: SlideLink?
    public let weight: SlideDimension?
    public let dashStyle: String?
}

// MARK: - Table

/// A table of cells.
public struct SlideTable: Codable, Sendable {
    public let rows: Int?
    public let columns: Int?
    public let tableRows: [SlideTableRow]?

    /// The text of the table. Cells in a row have a tab between them. Rows
    /// have a new line between them. Empty if the table has no text.
    var plainText: String {
        let rows = (tableRows ?? []).map { row in
            (row.tableCells ?? [])
                .map { $0.text?.plainText ?? "" }
                .joined(separator: "\t")
        }
        let joined = rows.joined(separator: "\n")
        return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : joined
    }
}

/// One row of a table.
public struct SlideTableRow: Codable, Sendable {
    public let rowHeight: SlideDimension?
    public let tableCells: [SlideTableCell]?
}

/// One cell of a table. A cell can span more than one row or column.
public struct SlideTableCell: Codable, Sendable {
    public let location: SlideTableCellLocation?
    public let rowSpan: Int?
    public let columnSpan: Int?
    public let text: SlideText?
}

/// The row and column of a cell, both zero-based.
public struct SlideTableCellLocation: Codable, Sendable {
    public let rowIndex: Int?
    public let columnIndex: Int?
}

// MARK: - Chart from Sheets

/// A chart that comes from a Google Sheets spreadsheet.
public struct SlideSheetsChart: Codable, Sendable {
    public let spreadsheetId: String?
    public let chartId: Int?
    /// A URL to the chart image. The URL is short-lived.
    public let contentUrl: String?
}

// MARK: - Word art

/// Word art, a shape that shows styled text.
public struct SlideWordArt: Codable, Sendable {
    public let renderedText: String?
}

// MARK: - Speaker spotlight

/// A speaker spotlight. It shows the presenter's camera feed on the slide.
/// It has no text, no link, and no source URL. graham reports its type,
/// geometry, and alt text like any other element.
public struct SlideSpeakerSpotlight: Codable, Sendable {
    public let speakerSpotlightProperties: SlideSpeakerSpotlightProperties?
}

/// The properties of a speaker spotlight: its outline and its shadow.
public struct SlideSpeakerSpotlightProperties: Codable, Sendable {
    public let outline: SlideOutline?
    public let shadow: SlideShadow?
}

// MARK: - Shared outline, shadow, fill, and color

/// The outline (the border) of an element.
public struct SlideOutline: Codable, Sendable {
    public let outlineFill: SlideOutlineFill?
    public let weight: SlideDimension?
    /// The dash style, for example `SOLID` or `DASH`.
    public let dashStyle: String?
    /// The state of the property, for example `RENDERED` or `NOT_RENDERED`.
    public let propertyState: String?
}

/// The fill of an outline.
public struct SlideOutlineFill: Codable, Sendable {
    public let solidFill: SlideSolidFill?
}

/// A solid color fill with an opacity.
public struct SlideSolidFill: Codable, Sendable {
    public let color: SlideOpaqueColor?
    /// The opacity, from 0 to 1.
    public let alpha: Double?
}

/// A color. It is a theme color or an explicit RGB color.
public struct SlideOpaqueColor: Codable, Sendable {
    /// A theme color name, for example `DARK1` or `ACCENT1`.
    public let themeColor: String?
    public let rgbColor: SlideRgbColor?
}

/// An RGB color. Each channel is from 0 to 1.
public struct SlideRgbColor: Codable, Sendable {
    public let red: Double?
    public let green: Double?
    public let blue: Double?
}

/// A drop shadow on an element.
public struct SlideShadow: Codable, Sendable {
    /// The shadow type, for example `OUTER`.
    public let type: String?
    public let transform: SlideTransform?
    /// Where the shadow aligns, for example `BOTTOM_RIGHT`.
    public let alignment: String?
    public let blurRadius: SlideDimension?
    public let color: SlideOpaqueColor?
    /// The opacity of the shadow, from 0 to 1.
    public let alpha: Double?
    public let rotateWithShape: Bool?
    /// The state of the property, for example `RENDERED`.
    public let propertyState: String?
}

// MARK: - Detailed read representation (the flattened facade)
//
// The models above mirror the Slides v1 wire schema. The types below are the
// reader's view: a flat, per-element representation that a command renders in
// any ``OutputFormat``. All the flattening and extraction logic lives here in
// GrahamKit, so the CLI stays thin.

/// The geometry of one element: its raw transform and size, plus a derived
/// rotation.
///
/// The raw transform and size are preserved exactly as the API returns them,
/// including the unit, so nothing is lost. ``rotationDegrees`` is a derived
/// summary computed from the transform (see ``init(size:transform:)``).
///
/// The coordinate space of the transform depends on the parent: a top-level
/// element maps to the page, but a group child maps into the group's space.
/// The raw values are reported unchanged, so a consumer that needs page-space
/// coordinates can combine a child's transform with its group's transform.
public struct SlideElementGeometry: Codable, Sendable, Equatable {
    // Raw transform.
    public let translateX: Double?
    public let translateY: Double?
    public let scaleX: Double?
    public let scaleY: Double?
    public let shearX: Double?
    public let shearY: Double?
    /// The unit of the transform's translation, for example `EMU`.
    public let transformUnit: String?

    // Raw size (before the transform's scale is applied).
    public let width: Double?
    public let height: Double?
    /// The unit of the size, for example `EMU`.
    public let sizeUnit: String?

    /// The rotation of the element, in degrees, derived from the transform.
    ///
    /// This assumes the transform is a rotation with scaling (the common case)
    /// and reports the angle only; it does not attempt to recover a general
    /// skew. `nil` when the transform lacks the fields needed to compute it.
    public let rotationDegrees: Double?

    /// The number of EMU (English Metric Units) in one point. Slides returns
    /// most lengths in EMU; a point is a friendlier unit for a human summary.
    static let emuPerPoint = 12700.0

    public init(size: SlideSize?, transform: SlideTransform?) {
        translateX = transform?.translateX
        translateY = transform?.translateY
        scaleX = transform?.scaleX
        scaleY = transform?.scaleY
        shearX = transform?.shearX
        shearY = transform?.shearY
        transformUnit = transform?.unit
        width = size?.width?.magnitude
        height = size?.height?.magnitude
        // The size's width and height can carry different units, but Slides
        // uses the same unit for both, so reporting the width's unit is exact.
        sizeUnit = size?.width?.unit ?? size?.height?.unit
        rotationDegrees = Self.rotationDegrees(scaleX: transform?.scaleX, shearY: transform?.shearY)
    }

    /// Derives the rotation angle in degrees from an affine transform.
    ///
    /// Slides applies `[x' y'] = [scaleX*x + shearX*y + translateX,
    /// shearY*x + scaleY*y + translateY]`. For a rotation by `θ` with scale
    /// `(sx, sy)`, `scaleX = sx·cosθ` and `shearY = sx·sinθ`, so
    /// `θ = atan2(shearY, scaleX)`. The result is rounded to four decimals so
    /// the output is stable and readable.
    static func rotationDegrees(scaleX: Double?, shearY: Double?) -> Double? {
        guard let scaleX, let shearY else { return nil }
        let degrees = atan2(shearY, scaleX) * 180 / .pi
        return (degrees * 10000).rounded() / 10000
    }

    /// Converts a length in this element's units to points, for a human table.
    static func points(_ magnitude: Double?, unit: String?) -> Double? {
        guard let magnitude else { return nil }
        switch unit {
        case "PT": return magnitude
        // Slides defaults to EMU when the unit is unspecified.
        case "EMU", "UNIT_UNSPECIFIED", nil: return magnitude / emuPerPoint
        default: return magnitude
        }
    }
}

/// One hyperlink that is relevant to an element or to its text.
///
/// A Slides ``SlideLink`` has exactly one target set; this record mirrors that
/// and adds where the link came from and, for a text-run link, the text it
/// sits on.
public struct SlideElementLink: Codable, Sendable, Equatable {
    /// Where the link comes from: `shape`, `textRun`, `image`, `line`,
    /// `table`, or `video`.
    public let source: String
    /// The visible text the link sits on, for a `textRun` or `table` link.
    /// `nil` for a link that belongs to the whole element.
    public let text: String?
    /// A link to a web page.
    public let url: String?
    /// A link to another slide by relation, for example `NEXT_SLIDE`.
    public let relativeLink: String?
    /// A link to a slide by its object id.
    public let pageObjectId: String?
    /// A link to a slide by its zero-based index.
    public let slideIndex: Int?

    public init(
        source: String,
        text: String?,
        url: String? = nil,
        relativeLink: String? = nil,
        pageObjectId: String? = nil,
        slideIndex: Int? = nil
    ) {
        self.source = source
        self.text = text
        self.url = url
        self.relativeLink = relativeLink
        self.pageObjectId = pageObjectId
        self.slideIndex = slideIndex
    }

    init(source: String, text: String?, link: SlideLink) {
        self.init(
            source: source,
            text: text,
            url: link.url,
            relativeLink: link.relativeLink,
            pageObjectId: link.pageObjectId,
            slideIndex: link.slideIndex
        )
    }
}

/// One element on one slide, flattened out of the presentation tree.
///
/// A group appears as its own row (``kind`` is ``PageElementKind/group``) and
/// each of its children appears as its own row too, with ``parentObjectId``
/// set and ``depth`` increased. A group row carries no text or links of its
/// own; those live on the child rows, so nothing is double-counted.
public struct SlideElementRow: Codable, Sendable, Equatable {
    /// The zero-based index of the slide this element is on.
    public let slideIndex: Int
    /// The object id of the slide.
    public let slideId: String?
    /// The object id of this element.
    public let objectId: String?
    /// The element type.
    public let kind: PageElementKind
    /// The object id of the enclosing group, or `nil` for a top-level element.
    public let parentObjectId: String?
    /// The nesting depth: `0` for a top-level element, `1` for a group child.
    public let depth: Int
    /// The element's geometry.
    public let geometry: SlideElementGeometry
    /// The visible text this element carries on its own. Empty for a group
    /// (its text lives on the child rows) and for elements with no text.
    public let text: String
    /// Every hyperlink on this element or its text.
    public let links: [SlideElementLink]
    /// The alt-text title.
    public let title: String?
    /// The alt-text description.
    public let description: String?
    /// For an image, the short-lived content URL.
    public let imageContentUrl: String?
    /// For an image, the source URL the image came from.
    public let imageSourceUrl: String?

    init(
        element: PageElement,
        slideIndex: Int,
        slideId: String?,
        parentObjectId: String?,
        depth: Int
    ) {
        self.slideIndex = slideIndex
        self.slideId = slideId
        objectId = element.objectId
        kind = element.kind
        self.parentObjectId = parentObjectId
        self.depth = depth
        geometry = SlideElementGeometry(size: element.size, transform: element.transform)
        text = element.directText
        links = element.elementLinks
        title = element.title
        description = element.description
        imageContentUrl = element.image?.contentUrl
        imageSourceUrl = element.image?.sourceUrl
    }
}

/// One image on one slide, flattened out of the presentation tree.
///
/// Unlike ``SlideElementRow`` this is images only, so a command that lists or
/// downloads pictures does not have to filter. Images inside groups are
/// included, however deep they nest.
public struct SlideImageRow: Codable, Sendable, Equatable {
    /// The zero-based index of the slide this image is on.
    public let slideIndex: Int
    /// The object id of the slide.
    public let slideId: String?
    /// The object id of the image element.
    public let objectId: String?
    /// The short-lived content URL of the image. `nil` only if the `fields`
    /// mask omitted it; a download needs it.
    public let contentUrl: String?
    /// The source URL the image came from, if Google keeps it.
    public let sourceUrl: String?
    /// The alt-text title.
    public let title: String?
    /// The alt-text description.
    public let description: String?

    init(element: PageElement, slideIndex: Int, slideId: String?) {
        self.slideIndex = slideIndex
        self.slideId = slideId
        objectId = element.objectId
        contentUrl = element.image?.contentUrl
        sourceUrl = element.image?.sourceUrl
        title = element.title
        description = element.description
    }
}

/// One slide's speaker notes, flattened out of the presentation tree.
///
/// One row per slide, in slide order. The notes shape id comes from the
/// slide's `slideProperties.notesPage.notesProperties.speakerNotesObjectId`,
/// and the notes text is the plain text of the matching shape on the notes
/// page. When the notes shape is absent from the notes page, or has no text,
/// the notes are the empty string.
public struct SlideSpeakerNotesRow: Codable, Sendable, Equatable {
    /// The one-based slide number, matching `slides cat` and `slides list`.
    public let slideNumber: Int
    /// The object id of the slide.
    public let slideId: String?
    /// The object id of the speaker-notes shape, when the notes page names one.
    public let notesShapeId: String?
    /// The plain text of the speaker notes; empty when the shape is missing or
    /// has no text.
    public let notes: String

    public init(slideNumber: Int, slideId: String?, notesShapeId: String?, notes: String) {
        self.slideNumber = slideNumber
        self.slideId = slideId
        self.notesShapeId = notesShapeId
        self.notes = notes
    }
}

/// One slide layout, flattened for the CLI: its object id, API name, and
/// display name. A layout id feeds `slides add --layout-id`.
public struct SlideLayoutRow: Codable, Sendable, Equatable {
    /// The object id of the layout.
    public let objectId: String?
    /// The API name of the layout, for example `TITLE_AND_BODY`.
    public let name: String?
    /// The human-readable name of the layout.
    public let displayName: String?

    public init(objectId: String?, name: String?, displayName: String?) {
        self.objectId = objectId
        self.name = name
        self.displayName = displayName
    }
}

// MARK: - Per-element extraction helpers

extension PageElement {
    /// The text this element carries on its own. Unlike ``plainText`` this does
    /// not recurse into a group's children, because the flattener lists each
    /// child as its own row.
    var directText: String {
        switch kind {
        case .shape: return shape?.text?.plainText ?? ""
        case .table: return table?.plainText ?? ""
        case .wordArt:
            return (wordArt?.renderedText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        default: return ""
        }
    }

    /// Every hyperlink on this element or its text. A group returns none of
    /// its own; its children carry their links as separate rows.
    var elementLinks: [SlideElementLink] {
        var links: [SlideElementLink] = []
        switch kind {
        case .shape:
            if let link = shape?.shapeProperties?.link {
                links.append(SlideElementLink(source: "shape", text: nil, link: link))
            }
            links.append(contentsOf: Self.textLinks(shape?.text, source: "textRun"))
        case .image:
            if let link = image?.imageProperties?.link {
                links.append(SlideElementLink(source: "image", text: nil, link: link))
            }
        case .line:
            if let link = line?.lineProperties?.link {
                links.append(SlideElementLink(source: "line", text: nil, link: link))
            }
        case .table:
            for row in table?.tableRows ?? [] {
                for cell in row.tableCells ?? [] {
                    links.append(contentsOf: Self.textLinks(cell.text, source: "table"))
                }
            }
        case .video:
            // A video's URL is its media source, reported as a link so no
            // targetable URL on the element is lost.
            if let url = video?.url {
                links.append(SlideElementLink(source: "video", text: nil, url: url))
            }
        default:
            break
        }
        return links
    }

    /// The links on the runs of one text body, each labelled with `source` and
    /// with the text it sits on.
    private static func textLinks(_ text: SlideText?, source: String) -> [SlideElementLink] {
        (text?.textElements ?? []).compactMap { element in
            guard let link = element.textRun?.style?.link else { return nil }
            let content = element.textRun?.content?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SlideElementLink(
                source: source,
                text: (content?.isEmpty ?? true) ? nil : content,
                link: link
            )
        }
    }
}

// MARK: - Flattening the presentation

extension Presentation {
    /// Every element on every slide, flattened depth-first.
    ///
    /// The order is: slide order, then the element order within a slide; a
    /// group is followed immediately by its children (and their children).
    /// This order is deterministic, so the output is stable.
    public var elementRows: [SlideElementRow] {
        var rows: [SlideElementRow] = []
        for (index, slide) in (slides ?? []).enumerated() {
            for element in slide.pageElements ?? [] {
                Self.flatten(
                    element,
                    slideIndex: index,
                    slideId: slide.objectId,
                    parentObjectId: nil,
                    depth: 0,
                    into: &rows
                )
            }
        }
        return rows
    }

    /// Every image on every slide, flattened depth-first, groups included.
    public var imageRows: [SlideImageRow] {
        var rows: [SlideImageRow] = []
        for (index, slide) in (slides ?? []).enumerated() {
            for element in slide.pageElements ?? [] {
                Self.collectImages(element, slideIndex: index, slideId: slide.objectId, into: &rows)
            }
        }
        return rows
    }

    /// One speaker-notes row per slide, in slide order.
    ///
    /// For each slide, the notes shape id comes from
    /// `slideProperties.notesPage.notesProperties.speakerNotesObjectId`, and the
    /// notes text is the plain text of the matching shape on the notes page.
    /// When the notes shape is absent or empty, the notes are the empty string.
    /// The extraction lives here in GrahamKit; the command only fetches and
    /// renders. See ``SlideSpeakerNotesRow``.
    public var speakerNotesRows: [SlideSpeakerNotesRow] {
        (slides ?? []).enumerated().map { index, slide in
            let notesPage = slide.slideProperties?.notesPage
            let shapeId = notesPage?.notesProperties?.speakerNotesObjectId
            return SlideSpeakerNotesRow(
                slideNumber: index + 1,
                slideId: slide.objectId,
                notesShapeId: shapeId,
                notes: Self.speakerNotesText(notesPage: notesPage, shapeId: shapeId)
            )
        }
    }

    /// The plain text of the speaker-notes shape named by `shapeId` on
    /// `notesPage`, or the empty string when the shape is missing or empty.
    static func speakerNotesText(notesPage: SlideNotesPage?, shapeId: String?) -> String {
        guard let shapeId else { return "" }
        for element in notesPage?.pageElements ?? [] where element.objectId == shapeId {
            return element.shape?.text?.plainText ?? ""
        }
        return ""
    }

    /// Every slide layout, in the order the API returns them. See
    /// ``SlideLayoutRow``.
    public var layoutRows: [SlideLayoutRow] {
        (layouts ?? []).map { layout in
            SlideLayoutRow(
                objectId: layout.objectId,
                name: layout.layoutProperties?.name,
                displayName: layout.layoutProperties?.displayName
            )
        }
    }

    /// Finds one page element anywhere in the presentation by its object id.
    ///
    /// The search is depth-first across every slide and recurses into nested
    /// groups, so a group child is found however deeply it nests. It follows
    /// the same order as ``elementRows`` — slide order, then element order, a
    /// group before its children — and returns the first match. `nil` if no
    /// element has the id.
    public func findElement(objectId: String) -> PageElement? {
        for slide in slides ?? [] {
            for element in slide.pageElements ?? [] {
                if let found = Self.findElement(element, objectId: objectId) {
                    return found
                }
            }
        }
        return nil
    }

    private static func flatten(
        _ element: PageElement,
        slideIndex: Int,
        slideId: String?,
        parentObjectId: String?,
        depth: Int,
        into rows: inout [SlideElementRow]
    ) {
        rows.append(SlideElementRow(
            element: element,
            slideIndex: slideIndex,
            slideId: slideId,
            parentObjectId: parentObjectId,
            depth: depth
        ))
        for child in element.elementGroup?.children ?? [] {
            flatten(
                child,
                slideIndex: slideIndex,
                slideId: slideId,
                parentObjectId: element.objectId,
                depth: depth + 1,
                into: &rows
            )
        }
    }

    private static func collectImages(
        _ element: PageElement,
        slideIndex: Int,
        slideId: String?,
        into rows: inout [SlideImageRow]
    ) {
        if element.kind == .image {
            rows.append(SlideImageRow(element: element, slideIndex: slideIndex, slideId: slideId))
        }
        for child in element.elementGroup?.children ?? [] {
            collectImages(child, slideIndex: slideIndex, slideId: slideId, into: &rows)
        }
    }

    /// Depth-first search of one element and its nested group children for the
    /// object id. Returns the matching element, or `nil`.
    private static func findElement(_ element: PageElement, objectId: String) -> PageElement? {
        if element.objectId == objectId { return element }
        for child in element.elementGroup?.children ?? [] {
            if let found = findElement(child, objectId: objectId) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Table and id output

extension SlideElementRow: GrahamRow {
    public static var tableColumns: [String] {
        ["SLIDE", "ELEMENT", "TYPE", "POS(pt)", "SIZE(pt)", "LINKS", "TEXT"]
    }

    public var tableValues: [String] {
        [
            // The slide is shown one-based, to match `slides cat`.
            String(slideIndex + 1),
            objectId ?? "",
            // Indent by nesting depth so a group's children read as nested.
            String(repeating: "  ", count: depth) + kind.rawValue,
            Self.pointPair(geometry.translateX, geometry.translateY, unit: geometry.transformUnit),
            Self.pointPair(geometry.width, geometry.height, unit: geometry.sizeUnit, separator: "x"),
            links.isEmpty ? "" : String(links.count),
            Self.oneLine(text),
        ]
    }

    public var idValue: String { objectId ?? "" }

    /// Formats a pair of lengths as points, rounded, for a table cell.
    private static func pointPair(
        _ first: Double?,
        _ second: Double?,
        unit: String?,
        separator: String = ","
    ) -> String {
        guard
            let a = SlideElementGeometry.points(first, unit: unit),
            let b = SlideElementGeometry.points(second, unit: unit)
        else { return "" }
        return "\(round(a))\(separator)\(round(b))"
    }

    private static func round(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// Collapses text to a single trimmed line for a table cell, so a tab or a
    /// newline never breaks the row layout.
    static func oneLine(_ text: String, limit: Int = 60) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " / ")
            .replacingOccurrences(of: "\t", with: " ")
        if flat.count <= limit { return flat }
        return String(flat.prefix(limit - 1)) + "\u{2026}"
    }
}

extension SlideImageRow: GrahamRow {
    public static var tableColumns: [String] {
        ["SLIDE", "ELEMENT", "ALT", "SOURCE_URL", "CONTENT_URL"]
    }

    public var tableValues: [String] {
        [
            String(slideIndex + 1),
            objectId ?? "",
            SlideElementRow.oneLine(altText, limit: 40),
            sourceUrl ?? "",
            // The content URL is long and last, so it is not padded.
            contentUrl ?? "",
        ]
    }

    public var idValue: String { objectId ?? "" }

    /// The alt text as one string: title, then description, when both are set.
    var altText: String {
        [title, description]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{2014} ")
    }
}

extension SlideSpeakerNotesRow: GrahamRow {
    public static var tableColumns: [String] {
        ["SLIDE", "SLIDE_ID", "NOTES_SHAPE", "NOTES"]
    }

    public var tableValues: [String] {
        [
            String(slideNumber),
            slideId ?? "",
            notesShapeId ?? "",
            // The notes text is last and can be long, so it is collapsed to one
            // line but not padded.
            SlideElementRow.oneLine(notes),
        ]
    }

    public var idValue: String { slideId ?? "" }
}

extension SlideLayoutRow: GrahamRow {
    public static var tableColumns: [String] {
        ["LAYOUT", "NAME", "DISPLAY_NAME"]
    }

    public var tableValues: [String] {
        [objectId ?? "", name ?? "", displayName ?? ""]
    }

    public var idValue: String { objectId ?? "" }
}

// MARK: - Image download: filenames and results

/// The naming policy for downloaded images.
///
/// A Slides image ``SlideImage/contentUrl`` is an opaque, short-lived URL that
/// carries no dependable file name or extension, so a name is built here
/// instead of trusted from the URL. A name is:
///
///     <seq>-slide<n>-<objectId>.<ext>
///
/// where `seq` is a zero-padded position in the download order (so two images
/// can never collide, even with an equal or missing object id), `n` is the
/// one-based slide number, `objectId` is sanitized to a safe character set,
/// and `ext` is chosen by sniffing the downloaded bytes (never guessed from
/// the URL). Sanitizing drops every path separator and dot from the object id,
/// so a name can never traverse out of the target directory.
public enum SlideImageFile {
    /// The characters kept in a sanitized name component. Note that `.` is not
    /// in the set, so a component can never form `..` or a hidden file.
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// Replaces every unsafe character in a name component with `_`.
    public static func sanitize(_ component: String) -> String {
        let mapped = String(component.map { safe.contains($0) ? $0 : "_" })
        return mapped.isEmpty ? "image" : mapped
    }

    /// Builds the file name for the image at `sequence` in the download order.
    public static func filename(
        sequence: Int,
        slideIndex: Int,
        objectId: String?,
        fileExtension: String
    ) -> String {
        let seq = String(format: "%03d", sequence)
        let name = sanitize(objectId ?? "image")
        return "\(seq)-slide\(slideIndex + 1)-\(name).\(fileExtension)"
    }

    /// Chooses a file extension by sniffing the leading "magic" bytes of the
    /// image, never by trusting the URL. Returns `bin` for an unrecognized
    /// format, so an unknown image is still saved with a safe, generic name.
    ///
    /// Slides serves PNG, JPEG, or GIF for pictures; the extra formats are
    /// recognized so a future or unusual response is still labelled correctly.
    public static func fileExtension(forBytes bytes: Data) -> String {
        func startsWith(_ prefix: [UInt8]) -> Bool {
            guard bytes.count >= prefix.count else { return false }
            for (index, byte) in prefix.enumerated() where bytes[bytes.startIndex + index] != byte {
                return false
            }
            return true
        }
        func matches(_ ascii: String, at offset: Int) -> Bool {
            let prefix = Array(ascii.utf8)
            guard bytes.count >= offset + prefix.count else { return false }
            for (index, byte) in prefix.enumerated()
            where bytes[bytes.startIndex + offset + index] != byte {
                return false
            }
            return true
        }

        if startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if startsWith([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if startsWith([0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if matches("RIFF", at: 0) && matches("WEBP", at: 8) { return "webp" }
        if startsWith([0x42, 0x4D]) { return "bmp" }
        if startsWith([0x49, 0x49, 0x2A, 0x00]) || startsWith([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return "bin"
    }
}

/// What happened to one image in a download run.
public enum SlideImageDownloadOutcome: Sendable, Equatable {
    /// The image was fetched and written. `byteCount` is the size on disk.
    case downloaded(filename: String, byteCount: Int)
    /// The image could not be fetched or written; `reason` explains why.
    case failed(reason: String)
    /// The image had no content URL, so there was nothing to download.
    case skipped(reason: String)
}

/// The result of trying to download one image.
public struct SlideImageDownloadResult: Sendable, Equatable {
    public let objectId: String?
    public let slideIndex: Int
    public let contentUrl: String?
    public let outcome: SlideImageDownloadOutcome

    public init(
        objectId: String?,
        slideIndex: Int,
        contentUrl: String?,
        outcome: SlideImageDownloadOutcome
    ) {
        self.objectId = objectId
        self.slideIndex = slideIndex
        self.contentUrl = contentUrl
        self.outcome = outcome
    }
}
