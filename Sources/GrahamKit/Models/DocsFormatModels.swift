import Foundation

// MARK: - Formatting read facade
//
// The read mirror of the `docs paragraph` and `docs style` setters. The Docs
// API reports only the values set on a paragraph or text run itself; an unset
// field is inherited — a paragraph (or run) from its named style, a named
// style from `NORMAL_TEXT`, and `NORMAL_TEXT` from the Docs editor defaults. A
// list item's indents also come from its list's nesting level when the
// paragraph does not set them.
//
// The rows below carry both the raw `explicit` values and the resolved
// `effective` values, in the units the setters take (points, a percent for
// line spacing, `#RRGGBB` colors, the API enum spellings), so a value read here
// can be passed straight back to `docs paragraph` or `docs style`. Like the
// block rows, all the lookup and resolution lives here; the CLI only fetches
// and renders.

/// The paragraph-level formatting `docs paragraph` can set: alignment,
/// direction, line spacing (a percent of single), spacing and indents (points),
/// the pagination toggles, shading (`#RRGGBB`), spacing mode, and the five
/// borders. Every field is optional; in an `explicit` value nil means "not set
/// on this paragraph" (inherited), in an `effective` value nil means the
/// editor default, which the API does not report.
public struct DocParagraphFormat: Codable, Sendable, Equatable {
    public private(set) var alignment: String?
    public private(set) var direction: String?
    public private(set) var lineSpacing: Double?
    public private(set) var spaceAbove: Double?
    public private(set) var spaceBelow: Double?
    public private(set) var indentStart: Double?
    public private(set) var indentEnd: Double?
    public private(set) var indentFirstLine: Double?
    public private(set) var keepLinesTogether: Bool?
    public private(set) var keepWithNext: Bool?
    public private(set) var avoidWidowAndOrphan: Bool?
    public private(set) var pageBreakBefore: Bool?
    /// The shading (background) color as `#RRGGBB`; nil when unset or
    /// transparent.
    public private(set) var shading: String?
    public private(set) var spacingMode: String?
    public private(set) var borderTop: DocBorderFormat?
    public private(set) var borderBottom: DocBorderFormat?
    public private(set) var borderLeft: DocBorderFormat?
    public private(set) var borderRight: DocBorderFormat?
    public private(set) var borderBetween: DocBorderFormat?

    /// The values a ``DocParagraphStyle`` sets explicitly. A nil style yields
    /// an all-nil format.
    public init(style: DocParagraphStyle?) {
        alignment = style?.alignment
        direction = style?.direction
        lineSpacing = style?.lineSpacing
        spaceAbove = style?.spaceAbove?.points
        spaceBelow = style?.spaceBelow?.points
        indentStart = style?.indentStart?.points
        indentEnd = style?.indentEnd?.points
        indentFirstLine = style?.indentFirstLine?.points
        keepLinesTogether = style?.keepLinesTogether
        keepWithNext = style?.keepWithNext
        avoidWidowAndOrphan = style?.avoidWidowAndOrphan
        pageBreakBefore = style?.pageBreakBefore
        shading = style?.shading?.backgroundColor?.hex
        spacingMode = style?.spacingMode
        borderTop = DocBorderFormat(border: style?.borderTop)
        borderBottom = DocBorderFormat(border: style?.borderBottom)
        borderLeft = DocBorderFormat(border: style?.borderLeft)
        borderRight = DocBorderFormat(border: style?.borderRight)
        borderBetween = DocBorderFormat(border: style?.borderBetween)
    }

    /// Fills every unset field from `parent`, the next link in the
    /// inheritance chain. A field set here always wins.
    func inheriting(from parent: DocParagraphFormat) -> DocParagraphFormat {
        var merged = self
        merged.alignment = alignment ?? parent.alignment
        merged.direction = direction ?? parent.direction
        merged.lineSpacing = lineSpacing ?? parent.lineSpacing
        merged.spaceAbove = spaceAbove ?? parent.spaceAbove
        merged.spaceBelow = spaceBelow ?? parent.spaceBelow
        merged.indentStart = indentStart ?? parent.indentStart
        merged.indentEnd = indentEnd ?? parent.indentEnd
        merged.indentFirstLine = indentFirstLine ?? parent.indentFirstLine
        merged.keepLinesTogether = keepLinesTogether ?? parent.keepLinesTogether
        merged.keepWithNext = keepWithNext ?? parent.keepWithNext
        merged.avoidWidowAndOrphan = avoidWidowAndOrphan ?? parent.avoidWidowAndOrphan
        merged.pageBreakBefore = pageBreakBefore ?? parent.pageBreakBefore
        merged.shading = shading ?? parent.shading
        merged.spacingMode = spacingMode ?? parent.spacingMode
        merged.borderTop = borderTop ?? parent.borderTop
        merged.borderBottom = borderBottom ?? parent.borderBottom
        merged.borderLeft = borderLeft ?? parent.borderLeft
        merged.borderRight = borderRight ?? parent.borderRight
        merged.borderBetween = borderBetween ?? parent.borderBetween
        return merged
    }

    /// Fills unset indents from a list nesting level — the indents a list item
    /// takes when its own paragraph style does not set them.
    func inheritingIndents(from level: DocNestingLevel) -> DocParagraphFormat {
        var merged = self
        merged.indentStart = indentStart ?? level.indentStart?.points
        merged.indentFirstLine = indentFirstLine ?? level.indentFirstLine?.points
        return merged
    }
}

/// One paragraph border as `docs paragraph` sets it: a `#RRGGBB` color, a
/// width and padding in points, and a dash style (`SOLID`, `DOT`, `DASH`).
public struct DocBorderFormat: Codable, Sendable, Equatable {
    public let color: String?
    public let width: Double?
    public let padding: Double?
    public let dashStyle: String?

    public init(color: String?, width: Double?, padding: Double?, dashStyle: String?) {
        self.color = color
        self.width = width
        self.padding = padding
        self.dashStyle = dashStyle
    }

    /// Nil when the border is absent from the style (inherited).
    init?(border: DocParagraphBorder?) {
        guard let border else { return nil }
        color = border.color?.hex
        width = border.width?.points
        padding = border.padding?.points
        dashStyle = border.dashStyle
    }

    /// Whether the border draws anything: it has a color and a non-zero
    /// width (a width of 0 is how the API hides a border).
    var isVisible: Bool {
        color != nil && (width ?? 0) > 0
    }
}

/// One row of `docs paragraph-style`: a paragraph's index range, named style,
/// list membership, its explicit and effective formatting, and a text preview.
public struct DocParagraphFormatRow: Codable, Sendable, Equatable {
    /// The paragraph's zero-based start index in UTF-16 code units (0 when
    /// the API omits it, which it does only for the first body element).
    public let startIndex: Int?
    /// The paragraph's zero-based end index (exclusive).
    public let endIndex: Int?
    /// The named style, for example `NORMAL_TEXT` or `HEADING_2`.
    public let namedStyleType: String?
    /// The list a list item belongs to; nil for a plain paragraph.
    public let listId: String?
    /// The zero-based nesting level of a list item; nil otherwise.
    public let nestingLevel: Int?
    /// The values set on this paragraph itself, as the API reports them.
    public let explicit: DocParagraphFormat
    /// The values after inheritance from the list nesting level, the named
    /// style, and `NORMAL_TEXT` is resolved — what the paragraph renders with.
    public let effective: DocParagraphFormat
    /// A short, single-line text preview.
    public let preview: String
}

extension DocParagraphFormatRow: GrahamRow {
    /// The table shows the effective values. `LINE` is the line spacing
    /// percent (`--line-spacing`); `ABOVE`/`BELOW` are the space above/below in
    /// points (`--space-above`/`--space-below`); `INDENT`/`END`/`FIRST` are the
    /// start, end, and first-line indents in points (`--indent-start`,
    /// `--indent-end`, `--indent-first-line`). `FLAGS` lists the set toggles
    /// and the rarer settings; the borders' details are in the JSON.
    public static var tableColumns: [String] {
        [
            "RANGE", "STYLE", "ALIGN", "LINE", "ABOVE", "BELOW", "INDENT", "END", "FIRST",
            "FLAGS", "SHADING", "TEXT",
        ]
    }

    public var tableValues: [String] {
        [
            DocFormatText.range(startIndex, endIndex),
            namedStyleType ?? "",
            effective.alignment ?? "",
            DocFormatText.number(effective.lineSpacing),
            DocFormatText.number(effective.spaceAbove),
            DocFormatText.number(effective.spaceBelow),
            DocFormatText.number(effective.indentStart),
            DocFormatText.number(effective.indentEnd),
            DocFormatText.number(effective.indentFirstLine),
            flags,
            effective.shading ?? "",
            preview,
        ]
    }

    /// `--format id` prints the paragraph's start index, one per line.
    public var idValue: String { String(startIndex ?? 0) }

    /// The set toggles and rarer settings, space-separated: the pagination
    /// toggles (`keep-lines`, `keep-next`, `avoid-widows`, `page-break`),
    /// `rtl`, `collapse-lists`, and `border` / `border-between` when a visible
    /// border is set.
    var flags: String {
        var tokens: [String] = []
        if effective.keepLinesTogether == true { tokens.append("keep-lines") }
        if effective.keepWithNext == true { tokens.append("keep-next") }
        if effective.avoidWidowAndOrphan == true { tokens.append("avoid-widows") }
        if effective.pageBreakBefore == true { tokens.append("page-break") }
        if effective.direction == "RIGHT_TO_LEFT" { tokens.append("rtl") }
        if effective.spacingMode == "COLLAPSE_LISTS" { tokens.append("collapse-lists") }
        let outer = [
            effective.borderTop, effective.borderBottom, effective.borderLeft, effective.borderRight,
        ]
        if outer.contains(where: { $0?.isVisible == true }) { tokens.append("border") }
        if effective.borderBetween?.isVisible == true { tokens.append("border-between") }
        return tokens.joined(separator: " ")
    }
}

// MARK: - Text format

/// The text formatting `docs style` can set: the toggles, colors (`#RRGGBB`),
/// font size (points), font family and weight, baseline offset, and link.
/// Every field is optional; in an `explicit` value nil means "not set on this
/// run" (inherited), in an `effective` value nil means the editor default.
public struct DocTextFormat: Codable, Sendable, Equatable {
    public private(set) var bold: Bool?
    public private(set) var italic: Bool?
    public private(set) var underline: Bool?
    public private(set) var strikethrough: Bool?
    public private(set) var smallCaps: Bool?
    /// The text color as `#RRGGBB`; nil when unset or transparent.
    public private(set) var foregroundColor: String?
    /// The highlight color as `#RRGGBB`; nil when unset or transparent.
    public private(set) var backgroundColor: String?
    /// The font size in points.
    public private(set) var fontSize: Double?
    public private(set) var fontFamily: String?
    /// The font weight, a multiple of 100 from 100 to 900.
    public private(set) var fontWeight: Int?
    /// `NONE`, `SUPERSCRIPT`, or `SUBSCRIPT`.
    public private(set) var baselineOffset: String?
    /// A web link's URL, or `heading:<id>`, `bookmark:<id>`, or `tab:<id>` for
    /// an in-document link.
    public private(set) var link: String?

    /// The values a ``DocTextStyle`` sets explicitly. A nil style yields an
    /// all-nil format.
    public init(style: DocTextStyle?) {
        bold = style?.bold
        italic = style?.italic
        underline = style?.underline
        strikethrough = style?.strikethrough
        smallCaps = style?.smallCaps
        foregroundColor = style?.foregroundColor?.hex
        backgroundColor = style?.backgroundColor?.hex
        fontSize = style?.fontSize?.points
        fontFamily = style?.weightedFontFamily?.fontFamily
        fontWeight = style?.weightedFontFamily?.weight
        baselineOffset = style?.baselineOffset
        link = Self.linkText(style?.link)
    }

    static func linkText(_ link: DocLink?) -> String? {
        guard let link else { return nil }
        if let url = link.url { return url }
        if let id = link.headingId { return "heading:\(id)" }
        if let id = link.bookmarkId { return "bookmark:\(id)" }
        if let id = link.tabId { return "tab:\(id)" }
        return nil
    }

    /// Fills every unset field from `parent`, the next link in the
    /// inheritance chain. A field set here always wins.
    func inheriting(from parent: DocTextFormat) -> DocTextFormat {
        var merged = self
        merged.bold = bold ?? parent.bold
        merged.italic = italic ?? parent.italic
        merged.underline = underline ?? parent.underline
        merged.strikethrough = strikethrough ?? parent.strikethrough
        merged.smallCaps = smallCaps ?? parent.smallCaps
        merged.foregroundColor = foregroundColor ?? parent.foregroundColor
        merged.backgroundColor = backgroundColor ?? parent.backgroundColor
        merged.fontSize = fontSize ?? parent.fontSize
        merged.fontFamily = fontFamily ?? parent.fontFamily
        merged.fontWeight = fontWeight ?? parent.fontWeight
        merged.baselineOffset = baselineOffset ?? parent.baselineOffset
        merged.link = link ?? parent.link
        return merged
    }
}

/// One row of `docs text-style`: a text run's index range, its explicit and
/// effective formatting, and its text.
public struct DocTextFormatRow: Codable, Sendable, Equatable {
    /// The run's zero-based start index in UTF-16 code units.
    public let startIndex: Int?
    /// The run's zero-based end index (exclusive).
    public let endIndex: Int?
    /// The values set on this run itself, as the API reports them.
    public let explicit: DocTextFormat
    /// The values after inheritance from the paragraph's named style and
    /// `NORMAL_TEXT` is resolved — what the run renders with.
    public let effective: DocTextFormat
    /// A short, single-line preview of the run's text.
    public let preview: String
}

extension DocTextFormatRow: GrahamRow {
    /// The table shows the effective values. `FLAGS` lists the set toggles
    /// (`bold`, `italic`, `underline`, `strike`, `small-caps`); `SIZE` is in
    /// points; `BASELINE` is `super` or `sub` (blank for normal).
    public static var tableColumns: [String] {
        ["RANGE", "FLAGS", "SIZE", "FONT", "WEIGHT", "COLOR", "BG", "BASELINE", "LINK", "TEXT"]
    }

    public var tableValues: [String] {
        [
            DocFormatText.range(startIndex, endIndex),
            flags,
            DocFormatText.number(effective.fontSize),
            effective.fontFamily ?? "",
            effective.fontWeight.map(String.init) ?? "",
            effective.foregroundColor ?? "",
            effective.backgroundColor ?? "",
            baseline,
            effective.link ?? "",
            preview,
        ]
    }

    /// `--format id` prints the run's start index, one per line.
    public var idValue: String { String(startIndex ?? 0) }

    var flags: String {
        var tokens: [String] = []
        if effective.bold == true { tokens.append("bold") }
        if effective.italic == true { tokens.append("italic") }
        if effective.underline == true { tokens.append("underline") }
        if effective.strikethrough == true { tokens.append("strike") }
        if effective.smallCaps == true { tokens.append("small-caps") }
        return tokens.joined(separator: " ")
    }

    var baseline: String {
        switch effective.baselineOffset {
        case "SUPERSCRIPT": return "super"
        case "SUBSCRIPT": return "sub"
        default: return ""
        }
    }
}

// MARK: - Resolution

/// Resolves the Docs inheritance chain for the paragraphs and text runs in a
/// segment. `lists` supplies a list item's nesting-level indents;
/// `namedStyles` supplies the named-style and `NORMAL_TEXT` links.
struct DocFormatResolver {
    let lists: [String: DocList]?
    let namedStyles: DocNamedStyles?

    static let normalText = "NORMAL_TEXT"

    /// One row per paragraph in `content` (recursing into table cells, like
    /// the block rows) whose range intersects `[from, to)`. A nil bound is
    /// open: nil `from` starts at 0, nil `to` runs to the end.
    func paragraphRows(
        in content: [StructuralElement], from: Int?, to: Int?
    ) -> [DocParagraphFormatRow] {
        paragraphs(in: content, from: from, to: to).map { element, paragraph in
            let explicit = DocParagraphFormat(style: paragraph.paragraphStyle)
            return DocParagraphFormatRow(
                startIndex: element.startIndex,
                endIndex: element.endIndex,
                namedStyleType: paragraph.paragraphStyle?.namedStyleType,
                listId: paragraph.bullet?.listId,
                nestingLevel: paragraph.bullet?.nestingLevel,
                explicit: explicit,
                effective: effectiveParagraphFormat(explicit, for: paragraph),
                preview: DocBlockRow.oneLine(
                    paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines), limit: 40)
            )
        }
    }

    /// One row per text run in `content` whose range intersects `[from, to)`.
    /// A run is reported whole, at the API's granularity, even when the range
    /// cuts through it.
    func textRows(in content: [StructuralElement], from: Int?, to: Int?) -> [DocTextFormatRow] {
        var rows: [DocTextFormatRow] = []
        for (_, paragraph) in paragraphs(in: content, from: from, to: to) {
            let parent = parentTextFormat(for: paragraph)
            for element in paragraph.elements ?? [] {
                guard let run = element.textRun,
                    Self.intersects(start: element.startIndex, end: element.endIndex, from: from, to: to)
                else { continue }
                let explicit = DocTextFormat(style: run.textStyle)
                rows.append(
                    DocTextFormatRow(
                        startIndex: element.startIndex,
                        endIndex: element.endIndex,
                        explicit: explicit,
                        effective: explicit.inheriting(from: parent),
                        preview: DocBlockRow.oneLine(
                            (run.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                            limit: 40)
                    ))
            }
        }
        return rows
    }

    /// The effective paragraph format: the paragraph's own values, then (for a
    /// list item) its nesting level's indents, then its named style, then
    /// `NORMAL_TEXT`.
    func effectiveParagraphFormat(
        _ explicit: DocParagraphFormat, for paragraph: DocParagraph
    ) -> DocParagraphFormat {
        var format = explicit
        if let level = nestingLevel(for: paragraph.bullet) {
            format = format.inheritingIndents(from: level)
        }
        let type = paragraph.paragraphStyle?.namedStyleType
        if let type, type != Self.normalText, let style = namedStyle(type) {
            format = format.inheriting(from: DocParagraphFormat(style: style.paragraphStyle))
        }
        if let normal = namedStyle(Self.normalText) {
            format = format.inheriting(from: DocParagraphFormat(style: normal.paragraphStyle))
        }
        return format
    }

    /// The text format a run in `paragraph` inherits: the paragraph's named
    /// style, then `NORMAL_TEXT`.
    func parentTextFormat(for paragraph: DocParagraph) -> DocTextFormat {
        var format = DocTextFormat(style: nil)
        let type = paragraph.paragraphStyle?.namedStyleType
        if let type, type != Self.normalText, let style = namedStyle(type) {
            format = format.inheriting(from: DocTextFormat(style: style.textStyle))
        }
        if let normal = namedStyle(Self.normalText) {
            format = format.inheriting(from: DocTextFormat(style: normal.textStyle))
        }
        return format
    }

    private func namedStyle(_ type: String) -> DocNamedStyle? {
        namedStyles?.styles?.first { $0.namedStyleType == type }
    }

    private func nestingLevel(for bullet: DocBullet?) -> DocNestingLevel? {
        guard let bullet, let listId = bullet.listId,
            let levels = lists?[listId]?.listProperties?.nestingLevels
        else { return nil }
        let index = bullet.nestingLevel ?? 0
        guard levels.indices.contains(index) else { return nil }
        return levels[index]
    }

    /// Every paragraph in `content`, depth-first through table cells, whose
    /// range intersects `[from, to)`, paired with its structural element (which
    /// carries the indices).
    private func paragraphs(
        in content: [StructuralElement], from: Int?, to: Int?
    ) -> [(StructuralElement, DocParagraph)] {
        var found: [(StructuralElement, DocParagraph)] = []
        func walk(_ elements: [StructuralElement]) {
            for element in elements {
                if let paragraph = element.paragraph,
                    Self.intersects(
                        start: element.startIndex, end: element.endIndex, from: from, to: to)
                {
                    found.append((element, paragraph))
                }
                for row in element.table?.tableRows ?? [] {
                    for cell in row.tableCells ?? [] {
                        walk(cell.content ?? [])
                    }
                }
            }
        }
        walk(content)
        return found
    }

    /// Whether `[start, end)` (an absent start is 0, an absent end is open)
    /// intersects `[from, to)` (a nil bound is open).
    static func intersects(start: Int?, end: Int?, from: Int?, to: Int?) -> Bool {
        let start = start ?? 0
        if let to, start >= to { return false }
        if let from, let end, end <= from { return false }
        return true
    }
}

extension Document {
    /// The formatting of every paragraph in a segment whose range intersects
    /// `[from, to)` — the read mirror of `docs paragraph`. A nil `from` starts
    /// at 0 and a nil `to` runs to the segment end, so no bounds means every
    /// paragraph. `segmentId` names a header, footer, or footnote; nil or empty
    /// is the body. Paragraphs inside table cells are included. Throws
    /// ``GrahamError/invalidArgument(_:)`` for an unknown segment id.
    public func paragraphFormatRows(
        from: Int? = nil, to: Int? = nil, segmentId: String? = nil
    ) throws -> [DocParagraphFormatRow] {
        let content = try segmentContent(segmentId)
        return DocFormatResolver(lists: lists, namedStyles: namedStyles)
            .paragraphRows(in: content, from: from, to: to)
    }

    /// The formatting of every text run in a segment whose range intersects
    /// `[from, to)` — the read mirror of `docs style`. The bounds and segment
    /// follow ``paragraphFormatRows(from:to:segmentId:)``.
    public func textFormatRows(
        from: Int? = nil, to: Int? = nil, segmentId: String? = nil
    ) throws -> [DocTextFormatRow] {
        let content = try segmentContent(segmentId)
        return DocFormatResolver(lists: lists, namedStyles: namedStyles)
            .textRows(in: content, from: from, to: to)
    }

    /// The content of a segment: the body for a nil or empty id, else the
    /// header, footer, or footnote with that id.
    func segmentContent(_ segmentId: String?) throws -> [StructuralElement] {
        guard let segmentId, !segmentId.isEmpty else { return body?.content ?? [] }
        if let header = headers?[segmentId] { return header.content ?? [] }
        if let footer = footers?[segmentId] { return footer.content ?? [] }
        if let footnote = footnotes?[segmentId] { return footnote.content ?? [] }
        throw GrahamError.invalidArgument(
            "no header, footer, or footnote segment with id \"\(segmentId)\"")
    }
}

extension DocTab {
    /// The formatting of the paragraphs in this tab's body whose range
    /// intersects `[from, to)`, resolved against the tab's own lists and named
    /// styles. See ``Document/paragraphFormatRows(from:to:segmentId:)``.
    public func paragraphFormatRows(from: Int? = nil, to: Int? = nil) -> [DocParagraphFormatRow] {
        DocFormatResolver(lists: documentTab?.lists, namedStyles: documentTab?.namedStyles)
            .paragraphRows(in: documentTab?.body?.content ?? [], from: from, to: to)
    }

    /// The formatting of the text runs in this tab's body whose range
    /// intersects `[from, to)`. See ``Document/textFormatRows(from:to:segmentId:)``.
    public func textFormatRows(from: Int? = nil, to: Int? = nil) -> [DocTextFormatRow] {
        DocFormatResolver(lists: documentTab?.lists, namedStyles: documentTab?.namedStyles)
            .textRows(in: documentTab?.body?.content ?? [], from: from, to: to)
    }
}

// MARK: - Rendering helpers

/// Small, deterministic text helpers shared by the format rows.
enum DocFormatText {
    /// `start-end`, with an absent start read as 0 and an absent end blank.
    static func range(_ start: Int?, _ end: Int?) -> String {
        "\(start ?? 0)-\(end.map(String.init) ?? "")"
    }

    /// A number without a trailing `.0`: `18`, `6.5`, `115`. Blank for nil.
    static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
