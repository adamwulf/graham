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
}

/// One slide (a page) in a presentation.
public struct SlidePage: Codable, Sendable {
    public let objectId: String?
    public let pageElements: [PageElement]?

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
        return .unknown
    }

    /// The text this element adds to ``SlidePage/plainText``. Empty if the
    /// element has no text.
    public var plainText: String {
        if let shape { return shape.text?.plainText ?? "" }
        if let table { return table.plainText }
        if let wordArt { return wordArt.renderedText ?? "" }
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
public enum PageElementKind: String, Sendable, Equatable {
    case group
    case shape
    case image
    case video
    case line
    case table
    case sheetsChart
    case wordArt
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
/// This is an affine transform. It maps the element to the page. The position
/// is `translateX` and `translateY`. The scale is `scaleX` and `scaleY`. The
/// rotation and any skew come from `shearX` and `shearY` together with the
/// scale. A reader computes the rotation angle from these fields.
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
