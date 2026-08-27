import XCTest
@testable import GrahamKit

/// Tests for the pure ``Document/markdown`` renderer: it turns a decoded
/// ``Document`` into GitHub-flavored Markdown deterministically. Every fixture
/// is static JSON; no test touches the network. The renderer ignores index
/// fields (they matter only to the write commands), so the fixtures omit them
/// and exercise the rendering rules directly.
final class DocsMarkdownTests: XCTestCase {
    /// One document that exercises every rule at once: a `TITLE` and a heading,
    /// bold / italic / strikethrough (each alone and all combined), a link, a
    /// stripped U+E907 placeholder, an unordered nested list and an ordered
    /// nested list, a horizontal rule, a page break, an inline image, a pipe
    /// table, a footnote (inline marker plus the trailing section), and person
    /// / rich-link / date smart chips rendered as their display text. The
    /// `__E907__` token stands in for the placeholder so it can live in a raw
    /// string; ``decode()`` swaps in the real character.
    private static let fullJSON = #"""
    {
      "documentId": "doc-md",
      "title": "Everything",
      "body": {"content": [
        {"sectionBreak": {}},
        {"paragraph": {
          "paragraphStyle": {"namedStyleType": "TITLE"},
          "elements": [{"textRun": {"content": "Doc Title\n"}}]}},
        {"paragraph": {
          "paragraphStyle": {"namedStyleType": "HEADING_2"},
          "elements": [{"textRun": {"content": "Overview\n"}}]}},
        {"paragraph": {"elements": [
          {"textRun": {"content": "Normal "}},
          {"textRun": {"content": "bold", "textStyle": {"bold": true}}},
          {"textRun": {"content": " "}},
          {"textRun": {"content": "italic", "textStyle": {"italic": true}}},
          {"textRun": {"content": " "}},
          {"textRun": {"content": "struck", "textStyle": {"strikethrough": true}}},
          {"textRun": {"content": " and a "}},
          {"textRun": {"content": "link", "textStyle": {
            "link": {"url": "https://example.com"}}}},
          {"textRun": {"content": ".\n"}}
        ]}},
        {"paragraph": {"elements": [
          {"textRun": {"content": "Combined: "}},
          {"textRun": {"content": "all", "textStyle": {
            "bold": true, "italic": true, "strikethrough": true}}},
          {"textRun": {"content": "\n"}}
        ]}},
        {"paragraph": {"elements": [
          {"textRun": {"content": "before__E907__after\n"}}
        ]}},
        {"paragraph": {
          "bullet": {"listId": "kix.ul", "nestingLevel": 0},
          "elements": [{"textRun": {"content": "Fruit\n"}}]}},
        {"paragraph": {
          "bullet": {"listId": "kix.ul", "nestingLevel": 1},
          "elements": [{"textRun": {"content": "Apple\n"}}]}},
        {"paragraph": {"elements": [{"textRun": {"content": "Steps:\n"}}]}},
        {"paragraph": {
          "bullet": {"listId": "kix.ol", "nestingLevel": 0},
          "elements": [{"textRun": {"content": "Step one\n"}}]}},
        {"paragraph": {
          "bullet": {"listId": "kix.ol", "nestingLevel": 1},
          "elements": [{"textRun": {"content": "Sub step\n"}}]}},
        {"paragraph": {"elements": [
          {"horizontalRule": {}},
          {"textRun": {"content": "\n"}}
        ]}},
        {"paragraph": {"elements": [
          {"pageBreak": {}},
          {"textRun": {"content": "\n"}}
        ]}},
        {"paragraph": {"elements": [
          {"inlineObjectElement": {"inlineObjectId": "img1"}},
          {"textRun": {"content": "\n"}}
        ]}},
        {"table": {"rows": 2, "columns": 2, "tableRows": [
          {"tableCells": [
            {"content": [{"paragraph": {"elements": [{"textRun": {"content": "H1\n"}}]}}]},
            {"content": [{"paragraph": {"elements": [{"textRun": {"content": "H2\n"}}]}}]}
          ]},
          {"tableCells": [
            {"content": [{"paragraph": {"elements": [{"textRun": {"content": "C1\n"}}]}}]},
            {"content": [{"paragraph": {"elements": [{"textRun": {"content": "C2\n"}}]}}]}
          ]}
        ]}},
        {"paragraph": {"elements": [
          {"textRun": {"content": "Fact"}},
          {"footnoteReference": {"footnoteId": "fn1", "footnoteNumber": "1"}},
          {"textRun": {"content": ".\n"}}
        ]}},
        {"paragraph": {"elements": [
          {"textRun": {"content": "By "}},
          {"person": {"personProperties": {"name": "Ada"}}},
          {"textRun": {"content": " see "}},
          {"richLink": {"richLinkProperties": {"title": "The Spec"}}},
          {"textRun": {"content": " on "}},
          {"dateElement": {"dateElementProperties": {"displayText": "Jan 1, 2026"}}},
          {"textRun": {"content": ".\n"}}
        ]}},
        {"paragraph": {"elements": [{"textRun": {"content": "\n"}}]}}
      ]},
      "inlineObjects": {
        "img1": {"objectId": "img1", "inlineObjectProperties": {"embeddedObject": {
          "title": "Logo",
          "imageProperties": {"sourceUri": "https://ex.com/logo.png"}}}}
      },
      "footnotes": {
        "fn1": {"footnoteId": "fn1", "content": [
          {"paragraph": {"elements": [{"textRun": {"content": "A cited source.\n"}}]}}]}
      },
      "lists": {
        "kix.ul": {"listProperties": {"nestingLevels": [
          {"glyphSymbol": "●"},
          {"glyphSymbol": "○"}
        ]}},
        "kix.ol": {"listProperties": {"nestingLevels": [
          {"glyphType": "DECIMAL", "glyphFormat": "%0."},
          {"glyphType": "ROMAN", "glyphFormat": "%1."}
        ]}}
      }
    }
    """#

    /// Non-obvious inline and table rules that are easy to regress: a repeated
    /// footnote id keeps the number from its first reference, a nested table is
    /// flattened into its containing cell, and elements with no Markdown
    /// representation do not disturb the visible text around them.
    private static let edgeRulesJSON = #"""
    {
      "documentId": "doc-edge-rules",
      "body": {"content": [
        {"paragraph": {"elements": [
          {"textRun": {"content": "First"}},
          {"footnoteReference": {"footnoteId": "same-note", "footnoteNumber": "7"}},
          {"textRun": {"content": " then again"}},
          {"footnoteReference": {"footnoteId": "same-note", "footnoteNumber": "99"}},
          {"textRun": {"content": ".\n"}}
        ]}},
        {"table": {"tableRows": [
          {"tableCells": [
            {"content": [
              {"paragraph": {"elements": [{"textRun": {"content": "Outer\n"}}]}},
              {"table": {"tableRows": [
                {"tableCells": [
                  {"content": [{"paragraph": {"elements": [
                    {"textRun": {"content": "Nested A\n"}}
                  ]}}]},
                  {"content": [{"paragraph": {"elements": [
                    {"textRun": {"content": "Nested B\n"}}
                  ]}}]}
                ]}
              ]}}
            ]},
            {"content": [{"paragraph": {"elements": [
              {"textRun": {"content": "Tail\n"}}
            ]}}]}
          ]}
        ]}},
        {"paragraph": {"elements": [
          {"textRun": {"content": "Visible"}},
          {"columnBreak": {}},
          {"equation": {}},
          {"autoText": {"type": "PAGE_NUMBER"}},
          {"textRun": {"content": " text.\n"}}
        ]}}
      ]},
      "footnotes": {
        "same-note": {"content": [{"paragraph": {"elements": [
          {"textRun": {"content": "One note.\n"}}
        ]}}]}
      }
    }
    """#

    /// Decodes a fixture, swapping the `__E907__` token for the real placeholder
    /// character the renderer must strip. The token lets the private-use
    /// placeholder live inside a raw-string fixture.
    private func decode(_ json: String) throws -> Document {
        let resolved = json.replacingOccurrences(of: "__E907__", with: "\u{E907}")
        return try GoogleJSON.decoder.decode(Document.self, from: Data(resolved.utf8))
    }

    func testFullDocumentRendersExactMarkdown() throws {
        let document = try decode(Self.fullJSON)
        let expected = [
            "# Doc Title",
            "## Overview",
            "Normal **bold** _italic_ ~~struck~~ and a [link](https://example.com).",
            "Combined: ~~**_all_**~~",
            "beforeafter",
            "- Fruit\n    - Apple",
            "Steps:",
            "1. Step one\n    1. Sub step",
            "---",
            "<!-- page break -->",
            "![Logo](https://ex.com/logo.png)",
            "| H1 | H2 |\n| --- | --- |\n| C1 | C2 |",
            "Fact[^1].",
            "By Ada see The Spec on Jan 1, 2026.",
            "[^1]: A cited source.",
        ].joined(separator: "\n\n")
        XCTAssertEqual(document.markdown, expected)
    }

    // MARK: - Headings

    func testTitleAndHeadingLevelsMapToHashes() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"paragraphStyle": {"namedStyleType": "TITLE"},
            "elements": [{"textRun": {"content": "T\n"}}]}},
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_1"},
            "elements": [{"textRun": {"content": "H1\n"}}]}},
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_2"},
            "elements": [{"textRun": {"content": "H2\n"}}]}},
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_3"},
            "elements": [{"textRun": {"content": "H3\n"}}]}},
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_4"},
            "elements": [{"textRun": {"content": "H4\n"}}]}},
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_5"},
            "elements": [{"textRun": {"content": "H5\n"}}]}},
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_6"},
            "elements": [{"textRun": {"content": "H6\n"}}]}}
        ]}}
        """#
        let document = try decode(json)
        let expected = [
            "# T", "# H1", "## H2", "### H3", "#### H4", "##### H5", "###### H6",
        ].joined(separator: "\n\n")
        XCTAssertEqual(document.markdown, expected)
    }

    /// A `HEADING_7` is out of range, so it is not a heading and renders as a
    /// plain paragraph with no `#` prefix (matching ``DocBlockRow``).
    func testOutOfRangeHeadingRendersAsPlainParagraph() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"paragraphStyle": {"namedStyleType": "HEADING_7"},
            "elements": [{"textRun": {"content": "Bogus\n"}}]}}
        ]}}
        """#
        XCTAssertEqual(try decode(json).markdown, "Bogus")
    }

    // MARK: - Emphasis and control characters

    /// Leading and trailing whitespace inside a styled run moves outside the
    /// emphasis delimiters, which must hug the visible text (CommonMark shows a
    /// delimiter wrapped around a space literally).
    func testEmphasisDelimitersHugTextNotSurroundingSpaces() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"elements": [
            {"textRun": {"content": "A"}},
            {"textRun": {"content": " bold ", "textStyle": {
              "bold": true, "italic": true, "strikethrough": true}}},
            {"textRun": {"content": "end\n"}}
          ]}}
        ]}}
        """#
        XCTAssertEqual(try decode(json).markdown, "A ~~**_bold_**~~ end")
    }

    /// The U+000B soft line break the API can place inside a run is stripped,
    /// just like a newline, so the raw control character never passes through.
    /// The fixture builds the JSON escape for U+000B from an explicit backslash
    /// scalar, so the source file holds no raw control byte.
    func testSoftLineBreakIsStripped() throws {
        let backslash = "\u{5C}"
        let json = "{\"documentId\":\"d\",\"body\":{\"content\":["
            + "{\"paragraph\":{\"elements\":[{\"textRun\":"
            + "{\"content\":\"line\(backslash)u000bbreak\"}}]}}]}}"
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))
        XCTAssertEqual(document.markdown, "linebreak")
    }

    // MARK: - Lists

    /// A list level whose glyph is a symbol (no numeric `glyphType`) is
    /// unordered; a numeric `glyphType` is ordered, at every nesting level.
    func testOrderedAndUnorderedListDetection() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"bullet": {"listId": "u", "nestingLevel": 0},
            "elements": [{"textRun": {"content": "dash\n"}}]}},
          {"paragraph": {"bullet": {"listId": "n", "nestingLevel": 0},
            "elements": [{"textRun": {"content": "num\n"}}]}}
        ]},
        "lists": {
          "u": {"listProperties": {"nestingLevels": [{"glyphSymbol": "●"}]}},
          "n": {"listProperties": {"nestingLevels": [{"glyphType": "ALPHA"}]}}
        }}
        """#
        // A different list id ends the first list, so the two render as separate
        // list blocks (a blank line between them).
        XCTAssertEqual(try decode(json).markdown, "- dash\n\n1. num")
    }

    /// A nested list item indents four spaces per level, so the sublist stays
    /// nested on GitHub even under an ordered parent. A level past the list's
    /// defined levels falls back to an unordered marker.
    func testNestedListIndentsFourSpacesPerLevel() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"bullet": {"listId": "n", "nestingLevel": 0},
            "elements": [{"textRun": {"content": "One\n"}}]}},
          {"paragraph": {"bullet": {"listId": "n", "nestingLevel": 1},
            "elements": [{"textRun": {"content": "Sub\n"}}]}}
        ]},
        "lists": {"n": {"listProperties": {"nestingLevels": [
          {"glyphType": "DECIMAL"}
        ]}}}}
        """#
        // Level 0 is ordered (DECIMAL); level 1 is past the one defined level, so
        // it falls back to unordered, indented four spaces under the "1. " parent.
        XCTAssertEqual(try decode(json).markdown, "1. One\n    - Sub")
    }

    /// A bullet whose list id is missing from the lists map falls back to an
    /// unordered marker.
    func testMissingListFallsBackToUnordered() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"bullet": {"listId": "missing", "nestingLevel": 0},
            "elements": [{"textRun": {"content": "Item\n"}}]}}
        ]}}
        """#
        XCTAssertEqual(try decode(json).markdown, "- Item")
    }

    // MARK: - Tables

    /// A single-row table still emits a header and a separator row.
    func testSingleRowTableHasHeaderAndSeparator() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"table": {"tableRows": [
            {"tableCells": [
              {"content": [{"paragraph": {"elements": [{"textRun": {"content": "A\n"}}]}}]},
              {"content": [{"paragraph": {"elements": [{"textRun": {"content": "B\n"}}]}}]}
            ]}
          ]}}
        ]}}
        """#
        XCTAssertEqual(try decode(json).markdown, "| A | B |\n| --- | --- |")
    }

    /// A pipe inside a cell is escaped, and a multi-paragraph cell collapses to
    /// a single line.
    func testTableCellsEscapePipesAndCollapseLines() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"table": {"tableRows": [
            {"tableCells": [
              {"content": [{"paragraph": {"elements": [{"textRun": {"content": "a|b\n"}}]}}]},
              {"content": [
                {"paragraph": {"elements": [{"textRun": {"content": "one\n"}}]}},
                {"paragraph": {"elements": [{"textRun": {"content": "two\n"}}]}}
              ]}
            ]},
            {"tableCells": [
              {"content": [{"paragraph": {"elements": [{"textRun": {"content": "1\n"}}]}}]},
              {"content": [{"paragraph": {"elements": [{"textRun": {"content": "2\n"}}]}}]}
            ]}
          ]}}
        ]}}
        """#
        XCTAssertEqual(
            try decode(json).markdown,
            "| a\\|b | one two |\n| --- | --- |\n| 1 | 2 |")
    }

    /// A cell renders inline Markdown — styling, a link, and a footnote
    /// reference — collapsed to one line, and a footnote referenced only in a
    /// cell still reaches the footnotes section.
    func testTableCellRendersInlineMarkdownAndCellOnlyFootnote() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"table": {"tableRows": [
            {"tableCells": [
              {"content": [{"paragraph": {"elements": [
                {"textRun": {"content": "Bold", "textStyle": {"bold": true}}},
                {"textRun": {"content": " and "}},
                {"textRun": {"content": "link", "textStyle": {
                  "link": {"url": "https://ex.com"}}}},
                {"footnoteReference": {"footnoteId": "f", "footnoteNumber": "1"}},
                {"textRun": {"content": "\n"}}
              ]}}]},
              {"content": [{"paragraph": {"elements": [{"textRun": {"content": "Plain\n"}}]}}]}
            ]}
          ]}}
        ]},
        "footnotes": {
          "f": {"content": [{"paragraph": {"elements": [
            {"textRun": {"content": "Note in cell.\n"}}]}}]}
        }}
        """#
        XCTAssertEqual(
            try decode(json).markdown,
            "| **Bold** and [link](https://ex.com)[^1] | Plain |\n| --- | --- |"
            + "\n\n[^1]: Note in cell.")
    }

    // MARK: - Footnotes

    /// Two footnotes render inline markers in order and one combined section at
    /// the end.
    func testMultipleFootnotesNumberInOrderWithSection() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"elements": [
            {"textRun": {"content": "A"}},
            {"footnoteReference": {"footnoteId": "f1", "footnoteNumber": "1"}},
            {"textRun": {"content": " B"}},
            {"footnoteReference": {"footnoteId": "f2", "footnoteNumber": "2"}},
            {"textRun": {"content": "\n"}}
          ]}}
        ]},
        "footnotes": {
          "f1": {"content": [{"paragraph": {"elements": [{"textRun": {"content": "First note.\n"}}]}}]},
          "f2": {"content": [{"paragraph": {"elements": [{"textRun": {"content": "Second note.\n"}}]}}]}
        }}
        """#
        XCTAssertEqual(
            try decode(json).markdown,
            "A[^1] B[^2]\n\n[^1]: First note.\n[^2]: Second note.")
    }

    func testRepeatedFootnoteNestedTableAndEmptyInlineElements() throws {
        let expected = [
            "First[^7] then again[^7].",
            "| Outer Nested A Nested B | Tail |\n| --- | --- |",
            "Visible text.",
            "[^7]: One note.",
        ].joined(separator: "\n\n")

        XCTAssertEqual(try decode(Self.edgeRulesJSON).markdown, expected)
    }

    // MARK: - Inline images and empty input

    /// An inline image with only a description (no title) uses the description
    /// as alt text.
    func testInlineImageFallsBackToDescriptionForAlt() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"paragraph": {"elements": [
            {"inlineObjectElement": {"inlineObjectId": "i"}},
            {"textRun": {"content": "\n"}}
          ]}}
        ]},
        "inlineObjects": {
          "i": {"inlineObjectProperties": {"embeddedObject": {
            "description": "A photo",
            "imageProperties": {"sourceUri": "https://ex.com/p.png"}}}}
        }}
        """#
        XCTAssertEqual(try decode(json).markdown, "![A photo](https://ex.com/p.png)")
    }

    func testEmptyDocumentRendersEmptyString() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(#"{"documentId": "d"}"#.utf8))
        XCTAssertEqual(document.markdown, "")
    }
}
