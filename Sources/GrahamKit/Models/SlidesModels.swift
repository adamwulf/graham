import Foundation

/// A Google Slides presentation. Only the fields needed for text extraction
/// are modeled; the decoder ignores all other fields.
public struct Presentation: Codable, Sendable {
    public let presentationId: String?
    public let title: String?
    public let slides: [SlidePage]?
}

/// One slide.
public struct SlidePage: Codable, Sendable {
    public let objectId: String?
    public let pageElements: [PageElement]?

    /// The text of all shapes on the slide, one shape per line.
    public var plainText: String {
        (pageElements ?? [])
            .compactMap { element -> String? in
                let text = (element.shape?.text?.textElements ?? [])
                    .compactMap { $0.textRun?.content }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            .joined(separator: "\n")
    }
}

/// One element on a slide. Slides elements are polymorphic (shape, table,
/// image, video, ...); this model reads shapes and ignores the rest.
public struct PageElement: Codable, Sendable {
    public let objectId: String?
    public let shape: SlideShape?
}

public struct SlideShape: Codable, Sendable {
    public let text: SlideText?
}

public struct SlideText: Codable, Sendable {
    public let textElements: [SlideTextElement]?
}

public struct SlideTextElement: Codable, Sendable {
    public let textRun: SlideTextRun?
}

public struct SlideTextRun: Codable, Sendable {
    public let content: String?
}
