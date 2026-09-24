import Foundation

/// A slide background to write with
/// ``SlidesClient/setSlideProperties(presentationId:slideId:skipped:background:)``.
public enum SlideBackground: Sendable, Equatable {
    /// A solid color: an explicit RGB color or a theme color.
    case color(OpaqueColor)
    /// A picture stretched to fill the slide. Google fetches the public URL
    /// once and stores a copy; the picture must be PNG, JPEG, or GIF, at most
    /// 50 MB and 25 megapixels, and the URL at most 2 kB.
    case image(url: String)
    /// No background fill (the CLI keyword `none`). Named `noFill`, not
    /// `none`, so it never collides with `Optional.none` on a
    /// `SlideBackground?`.
    case noFill
    /// The background of the layout the slide is based on. This resets the
    /// slide's own fill.
    case inherit

    /// Parses a background from the CLI spelling that
    /// ``SlidePropertiesRow/background`` prints: `none`, `inherit`, or a color
    /// that ``OpaqueColor/parse(_:)`` accepts (`#RRGGBB`, `#RGB`, or a theme
    /// name like `accent1`). Keywords are case-insensitive. A picture has no
    /// keyword form; build ``image(url:)`` directly.
    public static func parse(_ input: String) throws -> SlideBackground {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": return .noFill
        case "inherit": return .inherit
        default:
            guard let color = try? OpaqueColor.parse(input) else {
                throw GrahamError.invalidArgument(
                    "could not parse \"\(input)\" as a background; use a hex color like "
                    + "#FF0000 or #F00, a theme color name like accent1, none, or inherit")
            }
            return .color(color)
        }
    }
}

extension SlidesClient {
    // MARK: - Slide properties
    //
    // Two slide-level settings: whether presentation mode skips the slide
    // (`SlideProperties.isSkipped`, the editor's "Skip slide", often called a
    // hidden slide), and the slide's background
    // (`PageProperties.pageBackgroundFill`). Both are read with one masked
    // `presentations.get` and written in one atomic batch update.

    /// The mask that limits a read to each slide's id, skipped flag, and
    /// background fill.
    private static let slidePropertiesFields =
        "slides.objectId,slides.slideProperties.isSkipped,"
        + "slides.pageProperties.pageBackgroundFill"

    /// Reads every slide's skipped flag and background, one row per slide.
    ///
    /// This is a single `presentations.get`, masked to the slide ids, the
    /// skipped flags, and the background fills. See
    /// ``Presentation/slidePropertiesRows``.
    public func slideProperties(presentationId: String) async throws -> [SlidePropertiesRow] {
        let presentation = try await self.presentation(
            id: presentationId, fields: Self.slidePropertiesFields)
        return presentation.slidePropertiesRows
    }

    /// Sets whether presentation mode skips a slide, its background, or both.
    ///
    /// `skipped` sends an `updateSlideProperties` masked to `isSkipped`;
    /// `background` sends an `updatePageProperties` on the slide. When both
    /// are given they go in one atomic batch. `nil` leaves that setting
    /// unchanged; passing neither throws ``GrahamError/invalidArgument(_:)``
    /// before any request. The slide id is sent as given, and Google rejects
    /// an id that does not exist.
    public func setSlideProperties(
        presentationId: String,
        slideId: String,
        skipped: Bool? = nil,
        background: SlideBackground? = nil
    ) async throws {
        var requests: [SlidesBatchUpdateRequest] = []
        if let skipped {
            requests.append(.updateSlideProperties(UpdateSlidePropertiesRequest(
                objectId: slideId,
                slideProperties: SlidePropertiesValue(isSkipped: skipped),
                fields: "isSkipped"
            )))
        }
        if let background {
            requests.append(.updatePageProperties(
                Self.backgroundRequest(slideId: slideId, background: background)))
        }
        guard !requests.isEmpty else {
            throw GrahamError.invalidArgument(
                "set slide properties requires a skipped value or a background")
        }
        _ = try await batchUpdate(presentationId: presentationId, requests: requests)
    }

    /// Builds the `updatePageProperties` request for one background.
    ///
    /// A color or a picture masks only the value it sets, which implicitly
    /// renders the fill. `noFill` sets the property state to `NOT_RENDERED`.
    /// `inherit` masks the whole `pageBackgroundFill` and leaves it unset,
    /// which the API reads as "reset", so the slide shows its layout's
    /// background again.
    static func backgroundRequest(
        slideId: String,
        background: SlideBackground
    ) -> UpdatePagePropertiesRequest {
        let fill: PageBackgroundFill?
        let fields: String
        switch background {
        case .color(let color):
            fill = PageBackgroundFill(solidFill: SolidFill(color: color))
            fields = "pageBackgroundFill.solidFill.color"
        case .image(let url):
            fill = PageBackgroundFill(stretchedPictureFill: StretchedPictureFill(contentUrl: url))
            fields = "pageBackgroundFill.stretchedPictureFill.contentUrl"
        case .noFill:
            fill = PageBackgroundFill(propertyState: .notRendered)
            fields = "pageBackgroundFill.propertyState"
        case .inherit:
            fill = nil
            fields = "pageBackgroundFill"
        }
        return UpdatePagePropertiesRequest(
            objectId: slideId,
            pageProperties: PagePropertiesValue(pageBackgroundFill: fill),
            fields: fields
        )
    }
}
