import Foundation

extension Document {
    /// The document body rendered as GitHub-flavored Markdown.
    ///
    /// A pure, deterministic function over the read model. It renders the body
    /// only (headers, footers, and footnote segments are separate, like
    /// ``plainText`` and the write commands), and produces the same output for
    /// the same input every time:
    ///
    /// - `namedStyleType` `TITLE` and `HEADING_1`..`HEADING_6` map to `#`
    ///   through `######` (`TITLE` maps to a single `#`, like `HEADING_1`).
    /// - `bold`, `italic`, and `strikethrough` from a run's ``DocTextStyle`` wrap
    ///   the text with `**`, `_`, and `~~`, nesting inner to outer in that order;
    ///   a `link.url` wraps the styled text as `[text](url)`.
    /// - A paragraph with a ``DocBullet`` becomes a list item: `1.` when the
    ///   list level's ``DocNestingLevel/glyphType`` is numeric, otherwise `-`,
    ///   indented four spaces per nesting level so the nesting survives on
    ///   GitHub even under an ordered parent.
    /// - A ``DocTable`` renders as a GitHub pipe table (header row, separator
    ///   row, body rows) with each cell collapsed to a single line.
    /// - A `horizontalRule` renders as `---`; a `pageBreak` as an HTML comment
    ///   marker; a `footnoteReference` as an inline `[^n]` plus a footnotes
    ///   section at the end; an `inlineObjectElement` as `![alt](sourceUri)`;
    ///   and `person`, `richLink`, and `dateElement` as their display text.
    ///
    /// The U+E907 placeholder the API writes into a run where a non-text element
    /// sits is stripped. The result has no trailing newline; a caller that
    /// prints it adds its own.
    public var markdown: String {
        var renderer = DocsMarkdownRenderer(document: self)
        return renderer.render()
    }
}

/// Renders a ``Document`` body to GitHub-flavored Markdown. Pure and
/// deterministic; all extraction lives here in GrahamKit so a command stays
/// thin. Blocks are joined by a blank line; a run of consecutive list-item
/// paragraphs that share a list id joins into one list block, and a change of
/// list id (or any non-list block) starts a fresh one.
private struct DocsMarkdownRenderer {
    let document: Document

    /// The placeholder the Docs API places in a ``DocTextRun`` where a non-text
    /// element (image, break, chip) sits. It carries no visible text.
    static let objectPlaceholder = "\u{E907}"

    /// The `glyphType` values that make a list level ordered (numbered). Every
    /// other value — or an absent one, which means a bullet glyph — is
    /// unordered.
    static let orderedGlyphTypes: Set<String> = [
        "DECIMAL", "ZERO_DECIMAL", "UPPER_ALPHA", "ALPHA", "UPPER_ROMAN", "ROMAN",
    ]

    /// Footnotes in first-reference order, so the trailing footnotes section
    /// matches the inline `[^n]` markers; a repeated reference reuses the number
    /// already assigned to its id.
    private var footnotes: [(number: String, id: String)] = []

    init(document: Document) {
        self.document = document
    }

    // MARK: - Top level

    mutating func render() -> String {
        var blocks: [String] = []
        var pendingList: [String] = []
        var pendingListId: String?

        func flushList() {
            guard !pendingList.isEmpty else { return }
            blocks.append(pendingList.joined(separator: "\n"))
            pendingList.removeAll()
            pendingListId = nil
        }

        for element in document.body?.content ?? [] {
            // A list item joins the open list; a different list id starts a new
            // list, and any non-list block ends the open one.
            if let paragraph = element.paragraph, let bullet = paragraph.bullet {
                if !pendingList.isEmpty, bullet.listId != pendingListId { flushList() }
                pendingList.append(renderListItem(paragraph))
                pendingListId = bullet.listId
                continue
            }
            flushList()

            if let paragraph = element.paragraph {
                let content = renderInline(paragraph.elements ?? [])
                guard !content.isEmpty else { continue }
                if let prefix = Self.headingPrefix(for: paragraph.paragraphStyle?.namedStyleType) {
                    blocks.append("\(prefix) \(content)")
                } else {
                    blocks.append(content)
                }
            } else if let table = element.table {
                let rendered = renderTable(table)
                if !rendered.isEmpty { blocks.append(rendered) }
            }
            // A section break, a table of contents, and an unknown block render
            // no Markdown of their own.
        }
        flushList()

        if !footnotes.isEmpty {
            let section = footnotes
                .map { "[^\($0.number)]: \(collapse(document.footnotes?[$0.id]?.plainText ?? ""))" }
                .joined(separator: "\n")
            blocks.append(section)
        }

        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Paragraphs and lists

    /// Four spaces of indent per nesting level. A nested list item must indent
    /// to at least its parent marker's content column to stay nested in
    /// GFM/CommonMark — under an ordered `1. ` parent that column is 3, so two
    /// spaces renders the sublist flat. Four is a safe uniform width: it clears
    /// the widest marker graham emits (the ordered `1. `) yet stays under the
    /// four-past-content threshold that would turn the line into a code block.
    static let listIndentWidth = 4

    /// Renders a bulleted paragraph as one list item, indented by its nesting
    /// level and marked ordered or unordered by its list level's glyph.
    private mutating func renderListItem(_ paragraph: DocParagraph) -> String {
        let level = max(0, paragraph.bullet?.nestingLevel ?? 0)
        let ordered = isOrdered(listId: paragraph.bullet?.listId, level: level)
        let indent = String(repeating: " ", count: level * Self.listIndentWidth)
        let marker = ordered ? "1." : "-"
        let content = renderInline(paragraph.elements ?? [])
        return content.isEmpty ? "\(indent)\(marker)" : "\(indent)\(marker) \(content)"
    }

    /// Whether the given list level is numbered. A missing list, an
    /// out-of-range level, or a non-numeric glyph type is unordered.
    private func isOrdered(listId: String?, level: Int) -> Bool {
        guard let listId,
              let levels = document.lists?[listId]?.listProperties?.nestingLevels,
              level >= 0, level < levels.count else { return false }
        return Self.orderedGlyphTypes.contains(levels[level].glyphType ?? "")
    }

    // MARK: - Inline elements

    /// Renders a paragraph's elements in reading order, then trims trailing
    /// whitespace so a Markdown line never ends in stray spaces.
    private mutating func renderInline(_ elements: [DocParagraphElement]) -> String {
        var out = ""
        for element in elements {
            out += renderElement(element)
        }
        return trimTrailingWhitespace(out)
    }

    private mutating func renderElement(_ element: DocParagraphElement) -> String {
        if let run = element.textRun { return renderTextRun(run) }
        if let object = element.inlineObjectElement { return renderInlineObject(object) }
        if element.horizontalRule != nil { return "---" }
        if element.pageBreak != nil { return "<!-- page break -->" }
        if let footnote = element.footnoteReference { return renderFootnoteReference(footnote) }
        if let person = element.person {
            return person.personProperties?.name ?? person.personProperties?.email ?? ""
        }
        if let richLink = element.richLink {
            return richLink.richLinkProperties?.title ?? richLink.richLinkProperties?.uri ?? ""
        }
        if let date = element.dateElement {
            return date.dateElementProperties?.displayText ?? ""
        }
        // A column break, an equation, auto text, and an unknown element carry
        // no rendered text.
        return ""
    }

    /// Renders one text run: strips the placeholder and the line-ending and soft
    /// line-break control characters (each Docs paragraph is one Markdown line),
    /// then wraps the text with the emphasis and link the run's style asks for.
    ///
    /// Any leading or trailing whitespace stays OUTSIDE the emphasis and link
    /// delimiters — CommonMark renders a delimiter wrapped around a space
    /// literally (`** bold **` shows the stars), so the delimiter must hug the
    /// visible text and the surrounding spaces sit beside it.
    private func renderTextRun(_ run: DocTextRun) -> String {
        var text = run.content ?? ""
        text = text.replacingOccurrences(of: Self.objectPlaceholder, with: "")
        for control in ["\r", "\n", "\u{000B}"] {
            text = text.replacingOccurrences(of: control, with: "")
        }
        guard !text.isEmpty else { return "" }

        let characters = Array(text)
        guard let start = characters.firstIndex(where: { !$0.isWhitespace }),
              let last = characters.lastIndex(where: { !$0.isWhitespace }) else {
            // The run is all whitespace: nothing to emphasize, emit it as-is.
            return text
        }
        let leading = String(characters[..<start])
        let trailing = String(characters[(last + 1)...])
        var core = String(characters[start...last])

        let style = run.textStyle
        if style?.italic == true { core = "_\(core)_" }
        if style?.bold == true { core = "**\(core)**" }
        if style?.strikethrough == true { core = "~~\(core)~~" }
        if let url = style?.link?.url, !url.isEmpty {
            core = "[\(core)](\(url))"
        }
        return leading + core + trailing
    }

    /// Renders an inline object as an image, using the embedded object's title
    /// (then description) as alt text and the image's `sourceUri` as the URL.
    private func renderInlineObject(_ element: DocInlineObjectElement) -> String {
        guard let id = element.inlineObjectId,
              let embedded = document.inlineObjects?[id]?.embeddedObject else { return "" }
        let alt = embedded.title ?? embedded.description ?? ""
        let uri = embedded.imageProperties?.sourceUri ?? ""
        return "![\(alt)](\(uri))"
    }

    /// Renders a footnote reference as `[^n]` and records the footnote so the
    /// section at the end can define it. A repeated id reuses its first number.
    private mutating func renderFootnoteReference(_ reference: DocFootnoteReference) -> String {
        guard let id = reference.footnoteId else { return "" }
        if let existing = footnotes.first(where: { $0.id == id }) {
            return "[^\(existing.number)]"
        }
        let number = reference.footnoteNumber ?? String(footnotes.count + 1)
        footnotes.append((number: number, id: id))
        return "[^\(number)]"
    }

    // MARK: - Tables

    /// Renders a table as a GitHub pipe table: the first row is the header, a
    /// separator row follows, then the remaining rows. Each cell collapses to a
    /// single line and escapes any pipe.
    private mutating func renderTable(_ table: DocTable) -> String {
        let rows = table.tableRows ?? []
        guard let headerRow = rows.first else { return "" }
        let header = cellTexts(headerRow)
        let columnCount = max(header.count, 1)

        var lines = [pipeRow(header)]
        lines.append(pipeRow(Array(repeating: "---", count: columnCount)))
        for row in rows.dropFirst() {
            lines.append(pipeRow(cellTexts(row)))
        }
        return lines.joined(separator: "\n")
    }

    private mutating func cellTexts(_ row: DocTableRow) -> [String] {
        (row.tableCells ?? []).map { cellText($0) }
    }

    /// Renders one cell to a single line of inline Markdown, using the same
    /// inline renderer as a body paragraph — so a cell's styling, links,
    /// footnote references, and inline images survive (a footnote referenced
    /// only in a cell still reaches the footnotes section). A cell cannot hold a
    /// block-level table in GFM, so a nested table is flattened to its inline
    /// text rather than dropped. Whitespace collapses to one line and pipes are
    /// escaped last.
    private mutating func cellText(_ cell: DocTableCell) -> String {
        var parts: [String] = []
        for element in cell.content ?? [] {
            if let paragraph = element.paragraph {
                let rendered = renderInline(paragraph.elements ?? [])
                if !rendered.isEmpty { parts.append(rendered) }
            } else if let table = element.table {
                let flat = collapse(table.plainText)
                if !flat.isEmpty { parts.append(flat) }
            }
            // A section break, a table of contents, and an unknown block carry
            // no cell text.
        }
        return collapse(parts.joined(separator: " "))
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private func pipeRow(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    // MARK: - Helpers

    /// The Markdown heading prefix for a named style, or `nil` when the style is
    /// not a heading. `TITLE` and `HEADING_1` both yield a single `#`.
    static func headingPrefix(for namedStyleType: String?) -> String? {
        guard let named = namedStyleType else { return nil }
        if named == "TITLE" { return "#" }
        if let level = DocBlockRow.headingLevel(forNamedStyleType: named) {
            return String(repeating: "#", count: level)
        }
        return nil
    }

    /// Strips the placeholder, then collapses every run of whitespace (spaces,
    /// tabs, newlines) to a single space and trims the ends — so multi-line
    /// content fits on one line (a table cell, a footnote definition).
    private func collapse(_ text: String) -> String {
        text
            .replacingOccurrences(of: Self.objectPlaceholder, with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func trimTrailingWhitespace(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isWhitespace {
            result.removeLast()
        }
        return result
    }
}
