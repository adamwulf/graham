import XCTest
@testable import GrahamKit

/// Tests for the formatting read surface: the full `ParagraphStyle` and
/// `TextStyle` decode, the widened table / section / document style models,
/// the explicit paragraph fields on the block rows, and the
/// `paragraphFormatRows` / `textFormatRows` facades (range selection,
/// inheritance resolution, segment and tab lookup, and rendering). Every
/// fixture is static JSON; no test touches the network.
final class DocsFormatReadTests: XCTestCase {
    /// A quiz-shaped document: a heading, a question stem, two indented answer
    /// options (explicit indents and, on the first, extra space above), a list
    /// item with no explicit indents (they come from the list level), a
    /// centered paragraph carrying every remaining paragraph setting, a
    /// one-cell table, and a trailing paragraph — plus a header segment, the
    /// list, and fully populated named styles the way the live API reports
    /// them (zero magnitudes omitted, zero color channels omitted).
    private static let quizJSON = #"""
    {
      "documentId": "quiz-1",
      "body": {"content": [
        {"endIndex": 1, "sectionBreak": {"sectionStyle": {
          "columnSeparatorStyle": "NONE", "contentDirection": "LEFT_TO_RIGHT",
          "sectionType": "CONTINUOUS", "marginTop": {"magnitude": 72, "unit": "PT"},
          "marginHeader": {"magnitude": 36, "unit": "PT"}, "pageNumberStart": 3,
          "defaultHeaderId": "kix.h1", "useFirstPageHeaderFooter": false,
          "columnProperties": [
            {"width": {"magnitude": 200, "unit": "PT"}, "paddingEnd": {"magnitude": 36, "unit": "PT"}},
            {"width": {"magnitude": 200, "unit": "PT"}}]}}},
        {"startIndex": 1, "endIndex": 20, "paragraph": {
          "paragraphStyle": {"namedStyleType": "HEADING_1", "headingId": "h.abc",
                             "direction": "LEFT_TO_RIGHT"},
          "elements": [{"startIndex": 1, "endIndex": 20, "textRun": {
            "content": "Quiz 1: What is PM\n", "textStyle": {}}}]}},
        {"startIndex": 20, "endIndex": 41, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT", "direction": "LEFT_TO_RIGHT"},
          "elements": [
            {"startIndex": 20, "endIndex": 23, "textRun": {
              "content": "1. ", "textStyle": {"bold": true}}},
            {"startIndex": 23, "endIndex": 41, "textRun": {
              "content": "Which comes first\n", "textStyle": {}}}]}},
        {"startIndex": 41, "endIndex": 52, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT", "direction": "LEFT_TO_RIGHT",
            "indentStart": {"magnitude": 36, "unit": "PT"},
            "indentFirstLine": {"magnitude": 18, "unit": "PT"},
            "spaceAbove": {"magnitude": 6, "unit": "PT"},
            "spaceBelow": {"unit": "PT"}},
          "elements": [{"startIndex": 41, "endIndex": 52, "textRun": {
            "content": "◯ the idea\n", "textStyle": {
              "foregroundColor": {"color": {"rgbColor": {"red": 0.2, "green": 0.4, "blue": 0.6}}}}}}]}},
        {"startIndex": 52, "endIndex": 63, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT", "direction": "LEFT_TO_RIGHT",
            "indentStart": {"magnitude": 36, "unit": "PT"},
            "indentFirstLine": {"magnitude": 18, "unit": "PT"}},
          "elements": [{"startIndex": 52, "endIndex": 63, "textRun": {
            "content": "◯ the team\n", "textStyle": {
              "link": {"headingId": "h.abc"}, "smallCaps": true,
              "baselineOffset": "SUPERSCRIPT"}}}]}},
        {"startIndex": 63, "endIndex": 69, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
          "bullet": {"listId": "kix.list1", "nestingLevel": 1},
          "elements": [{"startIndex": 63, "endIndex": 69, "textRun": {"content": "First\n"}}]}},
        {"startIndex": 69, "endIndex": 76, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT", "alignment": "CENTER",
            "lineSpacing": 150, "spacingMode": "COLLAPSE_LISTS",
            "keepLinesTogether": true, "keepWithNext": true,
            "avoidWidowAndOrphan": false, "pageBreakBefore": true,
            "indentEnd": {"magnitude": 12.5, "unit": "PT"},
            "shading": {"backgroundColor": {"color": {"rgbColor": {"red": 1, "green": 1}}}},
            "borderTop": {"color": {"color": {"rgbColor": {}}},
                          "width": {"magnitude": 1, "unit": "PT"},
                          "padding": {"magnitude": 2, "unit": "PT"}, "dashStyle": "SOLID"},
            "borderBetween": {"color": {"color": {"rgbColor": {"red": 0.5}}},
                              "width": {"unit": "PT"}, "padding": {"unit": "PT"},
                              "dashStyle": "DOT"},
            "tabStops": [{"offset": {"magnitude": 72, "unit": "PT"}, "alignment": "START"}]},
          "elements": [{"startIndex": 69, "endIndex": 76, "textRun": {
            "content": "Shaded\n", "textStyle": {
              "bold": false, "fontSize": {"magnitude": 14, "unit": "PT"},
              "weightedFontFamily": {"fontFamily": "Georgia", "weight": 700},
              "backgroundColor": {"color": {"rgbColor": {"red": 1, "green": 1, "blue": 0}}}}}}]}},
        {"startIndex": 76, "endIndex": 88, "table": {
          "rows": 1, "columns": 1,
          "tableStyle": {"tableColumnProperties": [
            {"widthType": "FIXED_WIDTH", "width": {"magnitude": 100, "unit": "PT"}}]},
          "tableRows": [{"startIndex": 77, "endIndex": 87,
            "tableRowStyle": {"minRowHeight": {"magnitude": 20, "unit": "PT"},
                              "tableHeader": true, "preventOverflow": false},
            "tableCells": [{"startIndex": 78, "endIndex": 87,
              "tableCellStyle": {"rowSpan": 1, "columnSpan": 1,
                "backgroundColor": {"color": {"rgbColor": {"blue": 1}}},
                "borderLeft": {"color": {"color": {"rgbColor": {}}},
                               "width": {"magnitude": 1, "unit": "PT"}, "dashStyle": "DASH"},
                "paddingTop": {"magnitude": 5, "unit": "PT"},
                "contentAlignment": "MIDDLE"},
              "content": [{"startIndex": 79, "endIndex": 87, "paragraph": {
                "paragraphStyle": {"namedStyleType": "NORMAL_TEXT",
                                   "indentEnd": {"magnitude": 9, "unit": "PT"}},
                "elements": [{"startIndex": 79, "endIndex": 87, "textRun": {
                  "content": "In cell\n"}}]}}]}]}]}},
        {"startIndex": 88, "endIndex": 89, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
          "elements": [{"startIndex": 88, "endIndex": 89, "textRun": {"content": "\n"}}]}}
      ]},
      "headers": {
        "kix.h1": {"headerId": "kix.h1", "content": [
          {"startIndex": 0, "endIndex": 7, "paragraph": {
            "paragraphStyle": {"namedStyleType": "NORMAL_TEXT", "alignment": "END"},
            "elements": [{"startIndex": 0, "endIndex": 7, "textRun": {
              "content": "Header\n", "textStyle": {"italic": true}}}]}}]}
      },
      "lists": {
        "kix.list1": {"listProperties": {"nestingLevels": [
          {"glyphType": "DECIMAL", "glyphFormat": "%0.", "bulletAlignment": "START",
           "indentFirstLine": {"magnitude": 18, "unit": "PT"},
           "indentStart": {"magnitude": 36, "unit": "PT"}},
          {"glyphType": "ALPHA", "glyphFormat": "%1.",
           "indentFirstLine": {"magnitude": 54, "unit": "PT"},
           "indentStart": {"magnitude": 72, "unit": "PT"}}
        ]}}
      },
      "namedStyles": {"styles": [
        {"namedStyleType": "NORMAL_TEXT",
         "paragraphStyle": {"namedStyleType": "NORMAL_TEXT", "alignment": "START",
           "lineSpacing": 115, "direction": "LEFT_TO_RIGHT", "spacingMode": "NEVER_COLLAPSE",
           "spaceAbove": {"unit": "PT"}, "spaceBelow": {"unit": "PT"},
           "indentFirstLine": {"unit": "PT"}, "indentStart": {"unit": "PT"},
           "indentEnd": {"unit": "PT"},
           "keepLinesTogether": false, "keepWithNext": false,
           "avoidWidowAndOrphan": true, "pageBreakBefore": false,
           "shading": {"backgroundColor": {"color": {"rgbColor": {"red": 1, "green": 1, "blue": 1}}}}},
         "textStyle": {"bold": false, "italic": false, "underline": false,
           "strikethrough": false, "smallCaps": false,
           "backgroundColor": {}, "foregroundColor": {"color": {"rgbColor": {}}},
           "fontSize": {"magnitude": 11, "unit": "PT"},
           "weightedFontFamily": {"fontFamily": "Arial", "weight": 400},
           "baselineOffset": "NONE"}},
        {"namedStyleType": "HEADING_1",
         "paragraphStyle": {"namedStyleType": "HEADING_1",
           "spaceAbove": {"magnitude": 20, "unit": "PT"},
           "spaceBelow": {"magnitude": 6, "unit": "PT"},
           "keepLinesTogether": true, "keepWithNext": true},
         "textStyle": {"fontSize": {"magnitude": 20, "unit": "PT"}}}
      ]},
      "documentStyle": {
        "background": {"color": {"color": {"rgbColor": {"red": 1, "green": 1, "blue": 1}}}},
        "defaultHeaderId": "kix.h1", "pageNumberStart": 1,
        "pageSize": {"width": {"magnitude": 612, "unit": "PT"},
                     "height": {"magnitude": 792, "unit": "PT"}},
        "marginTop": {"magnitude": 72, "unit": "PT"},
        "marginHeader": {"magnitude": 36, "unit": "PT"},
        "marginFooter": {"magnitude": 36, "unit": "PT"},
        "useCustomHeaderFooterMargins": true, "flipPageOrientation": false,
        "documentFormat": {"documentMode": "PAGES"}
      }
    }
    """#

    private func decodeQuiz() throws -> Document {
        try GoogleJSON.decoder.decode(Document.self, from: Data(Self.quizJSON.utf8))
    }

    private func paragraph(_ document: Document, at index: Int) throws -> DocParagraph {
        try XCTUnwrap(document.body?.content?[index].paragraph)
    }

    // MARK: - Full ParagraphStyle and TextStyle decode

    func testParagraphStyleDecodesEveryField() throws {
        let document = try decodeQuiz()
        let style = try XCTUnwrap(try paragraph(document, at: 6).paragraphStyle)
        XCTAssertEqual(style.alignment, "CENTER")
        XCTAssertEqual(style.lineSpacing, 150)
        XCTAssertEqual(style.spacingMode, "COLLAPSE_LISTS")
        XCTAssertEqual(style.keepLinesTogether, true)
        XCTAssertEqual(style.keepWithNext, true)
        XCTAssertEqual(style.avoidWidowAndOrphan, false)
        XCTAssertEqual(style.pageBreakBefore, true)
        XCTAssertEqual(style.indentEnd?.magnitude, 12.5)
        XCTAssertEqual(style.indentEnd?.unit, "PT")
        XCTAssertEqual(style.shading?.backgroundColor?.hex, "#FFFF00")
        XCTAssertEqual(style.borderTop?.width?.magnitude, 1)
        XCTAssertEqual(style.borderTop?.padding?.magnitude, 2)
        XCTAssertEqual(style.borderTop?.dashStyle, "SOLID")
        XCTAssertEqual(style.borderTop?.color?.hex, "#000000")
        XCTAssertEqual(style.borderBetween?.dashStyle, "DOT")
        XCTAssertNil(style.borderLeft)
        XCTAssertEqual(style.tabStops?.count, 1)
        XCTAssertEqual(style.tabStops?.first?.offset?.magnitude, 72)
        XCTAssertEqual(style.tabStops?.first?.alignment, "START")
    }

    func testParagraphIndentsAndSpacingDecodeInPoints() throws {
        let document = try decodeQuiz()
        let style = try XCTUnwrap(try paragraph(document, at: 3).paragraphStyle)
        XCTAssertEqual(style.indentStart?.magnitude, 36)
        XCTAssertEqual(style.indentFirstLine?.magnitude, 18)
        XCTAssertEqual(style.spaceAbove?.magnitude, 6)
        // A zero magnitude is omitted by the API; the dimension still decodes.
        XCTAssertNotNil(style.spaceBelow)
        XCTAssertNil(style.spaceBelow?.magnitude)
        XCTAssertEqual(style.spaceBelow?.points, 0)
        XCTAssertNil(style.indentEnd, "an unset indent stays nil (inherited)")
    }

    func testTextStyleDecodesColorsAndSmallCaps() throws {
        let document = try decodeQuiz()
        let optionA = try XCTUnwrap(try paragraph(document, at: 3).elements?.first?.textRun?.textStyle)
        XCTAssertEqual(optionA.foregroundColor?.hex, "#336699")
        XCTAssertNil(optionA.backgroundColor)

        let optionB = try XCTUnwrap(try paragraph(document, at: 4).elements?.first?.textRun?.textStyle)
        XCTAssertEqual(optionB.smallCaps, true)
        XCTAssertEqual(optionB.link?.headingId, "h.abc")
        XCTAssertEqual(optionB.baselineOffset, "SUPERSCRIPT")

        let shaded = try XCTUnwrap(try paragraph(document, at: 6).elements?.first?.textRun?.textStyle)
        XCTAssertEqual(shaded.backgroundColor?.hex, "#FFFF00")
        XCTAssertEqual(shaded.weightedFontFamily?.weight, 700)
    }

    func testDimensionPointsReadsAnOmittedMagnitudeAsZero() throws {
        let zero = try GoogleJSON.decoder.decode(DocDimension.self, from: Data(#"{"unit": "PT"}"#.utf8))
        XCTAssertEqual(zero.points, 0)
        let six = try GoogleJSON.decoder.decode(
            DocDimension.self, from: Data(#"{"magnitude": 6, "unit": "PT"}"#.utf8))
        XCTAssertEqual(six.points, 6)
    }

    func testOptionalColorHexReadsOmittedChannelsAsZeroAndTransparentAsNil() throws {
        func decode(_ json: String) throws -> DocOptionalColor {
            try GoogleJSON.decoder.decode(DocOptionalColor.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"color": {"rgbColor": {"red": 1}}}"#).hex, "#FF0000")
        XCTAssertEqual(try decode(#"{"color": {"rgbColor": {}}}"#).hex, "#000000")
        XCTAssertEqual(
            try decode(#"{"color": {"rgbColor": {"red": 0.2, "green": 0.4, "blue": 0.6}}}"#).hex,
            "#336699")
        // 0x11 / 255 = 0.0667 round-trips to 11 through rounding, not truncation.
        XCTAssertEqual(
            try decode(#"{"color": {"rgbColor": {"red": 0.0667, "green": 0.3333, "blue": 0.8}}}"#).hex,
            "#1155CC")
        XCTAssertNil(try decode("{}").hex, "an empty OptionalColor is transparent")
        XCTAssertNil(try decode(#"{"color": {}}"#).hex)
    }

    // MARK: - Widened table, section, document, list, and tab models

    func testTableStylesDecode() throws {
        let document = try decodeQuiz()
        let table = try XCTUnwrap(document.body?.content?[7].table)
        XCTAssertEqual(table.tableStyle?.tableColumnProperties?.first?.widthType, "FIXED_WIDTH")
        XCTAssertEqual(table.tableStyle?.tableColumnProperties?.first?.width?.magnitude, 100)

        let row = try XCTUnwrap(table.tableRows?.first)
        XCTAssertEqual(row.tableRowStyle?.minRowHeight?.magnitude, 20)
        XCTAssertEqual(row.tableRowStyle?.tableHeader, true)
        XCTAssertEqual(row.tableRowStyle?.preventOverflow, false)

        let cell = try XCTUnwrap(row.tableCells?.first?.tableCellStyle)
        XCTAssertEqual(cell.rowSpan, 1)
        XCTAssertEqual(cell.backgroundColor?.hex, "#0000FF")
        XCTAssertEqual(cell.borderLeft?.dashStyle, "DASH")
        XCTAssertEqual(cell.borderLeft?.width?.magnitude, 1)
        XCTAssertEqual(cell.paddingTop?.magnitude, 5)
        XCTAssertNil(cell.paddingBottom)
        XCTAssertEqual(cell.contentAlignment, "MIDDLE")
    }

    func testSectionStyleDecodes() throws {
        let document = try decodeQuiz()
        let style = try XCTUnwrap(document.body?.content?.first?.sectionBreak?.sectionStyle)
        XCTAssertEqual(style.columnSeparatorStyle, "NONE")
        XCTAssertEqual(style.contentDirection, "LEFT_TO_RIGHT")
        XCTAssertEqual(style.sectionType, "CONTINUOUS")
        XCTAssertEqual(style.marginTop?.magnitude, 72)
        XCTAssertEqual(style.marginHeader?.magnitude, 36)
        XCTAssertEqual(style.pageNumberStart, 3)
        XCTAssertEqual(style.defaultHeaderId, "kix.h1")
        XCTAssertEqual(style.useFirstPageHeaderFooter, false)
        XCTAssertEqual(style.columnProperties?.count, 2)
        XCTAssertEqual(style.columnProperties?.first?.paddingEnd?.magnitude, 36)
    }

    func testDocumentStyleDecodesTheWidenedFields() throws {
        let style = try XCTUnwrap(try decodeQuiz().documentStyle)
        XCTAssertEqual(style.background?.color?.hex, "#FFFFFF")
        XCTAssertEqual(style.defaultHeaderId, "kix.h1")
        XCTAssertEqual(style.pageNumberStart, 1)
        XCTAssertEqual(style.marginHeader?.magnitude, 36)
        XCTAssertEqual(style.marginFooter?.magnitude, 36)
        XCTAssertEqual(style.useCustomHeaderFooterMargins, true)
        XCTAssertEqual(style.flipPageOrientation, false)
        XCTAssertEqual(style.documentFormat?.documentMode, "PAGES")
        // The fields that were already read still decode.
        XCTAssertEqual(style.pageSize?.width?.magnitude, 612)
        XCTAssertEqual(style.marginTop?.magnitude, 72)
    }

    func testNestingLevelIndentsDecode() throws {
        let levels = try XCTUnwrap(try decodeQuiz().lists?["kix.list1"]?.listProperties?.nestingLevels)
        XCTAssertEqual(levels[0].indentFirstLine?.magnitude, 18)
        XCTAssertEqual(levels[0].indentStart?.magnitude, 36)
        XCTAssertEqual(levels[0].bulletAlignment, "START")
        XCTAssertEqual(levels[1].indentStart?.magnitude, 72)
    }

    func testTabContentDecodesListsNamedStylesAndDocumentStyle() throws {
        let json = #"""
        {"documentId": "d", "tabs": [{"tabProperties": {"tabId": "t.0", "title": "Tab"},
          "documentTab": {
            "body": {"content": [{"startIndex": 1, "endIndex": 7, "paragraph": {
              "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
              "bullet": {"listId": "kix.tl", "nestingLevel": 0},
              "elements": [{"startIndex": 1, "endIndex": 7, "textRun": {"content": "Hello\n"}}]}}]},
            "lists": {"kix.tl": {"listProperties": {"nestingLevels": [
              {"indentStart": {"magnitude": 30, "unit": "PT"}}]}}},
            "namedStyles": {"styles": [{"namedStyleType": "NORMAL_TEXT",
              "paragraphStyle": {"lineSpacing": 120}, "textStyle": {"fontSize": {"magnitude": 9, "unit": "PT"}}}]},
            "documentStyle": {"marginTop": {"magnitude": 50, "unit": "PT"}}}}]}
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))
        let tab = try XCTUnwrap(document.tab(withId: "t.0"))
        XCTAssertEqual(tab.documentTab?.documentStyle?.marginTop?.magnitude, 50)
        XCTAssertEqual(tab.documentTab?.namedStyles?.styles?.first?.paragraphStyle?.lineSpacing, 120)

        // The tab facade resolves against the tab's own lists and named styles.
        let rows = tab.paragraphFormatRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].effective.indentStart, 30)
        XCTAssertEqual(rows[0].effective.lineSpacing, 120)
        XCTAssertNil(rows[0].explicit.indentStart)
        let runs = tab.textFormatRows(from: 2, to: 3)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].effective.fontSize, 9)
    }

    // MARK: - Block rows carry the paragraph's explicit values

    func testBlockRowsCarryExplicitIndentsAndSpacingInPoints() throws {
        let rows = try decodeQuiz().blockRows
        let optionA = try XCTUnwrap(rows.first { $0.startIndex == 41 })
        XCTAssertEqual(optionA.indentStart, 36)
        XCTAssertEqual(optionA.indentFirstLine, 18)
        XCTAssertEqual(optionA.spaceAbove, 6)
        XCTAssertEqual(optionA.spaceBelow, 0, "an omitted magnitude is an explicit zero")
        XCTAssertNil(optionA.indentEnd, "an unset value is inherited, so it stays nil")
        XCTAssertNil(optionA.lineSpacing)
        XCTAssertNil(optionA.alignment)

        let stem = try XCTUnwrap(rows.first { $0.startIndex == 20 })
        XCTAssertNil(stem.indentStart)
        XCTAssertNil(stem.spaceAbove)

        let centered = try XCTUnwrap(rows.first { $0.startIndex == 69 })
        XCTAssertEqual(centered.alignment, "CENTER")
        XCTAssertEqual(centered.lineSpacing, 150)
        XCTAssertEqual(centered.indentEnd, 12.5)

        let table = try XCTUnwrap(rows.first { $0.kind == .table })
        XCTAssertNil(table.indentStart)
        XCTAssertNil(table.alignment)
    }

    func testBlockRowJsonCarriesTheExplicitFieldsAndOmitsAbsentOnes() throws {
        let rows = try decodeQuiz().blockRows
        let jsonl = try OutputFormatter.render(rows, format: .jsonl)
        let lines = jsonl.split(separator: "\n").map(String.init)
        let optionA = try XCTUnwrap(lines.first { $0.contains(#""startIndex":41"#) })
        XCTAssertTrue(optionA.contains(#""indentStart":36"#), optionA)
        XCTAssertTrue(optionA.contains(#""indentFirstLine":18"#), optionA)
        XCTAssertTrue(optionA.contains(#""spaceAbove":6"#), optionA)
        XCTAssertTrue(optionA.contains(#""spaceBelow":0"#), optionA)
        XCTAssertFalse(optionA.contains("indentEnd"), optionA)
        XCTAssertFalse(optionA.contains("lineSpacing"), optionA)

        // The table columns are unchanged: the new fields live in JSON only.
        let table = try OutputFormatter.render(rows, format: .table)
        let header = try XCTUnwrap(table.split(separator: "\n").first)
        XCTAssertEqual(
            String(header).split(separator: " ", omittingEmptySubsequences: true).map(String.init),
            ["RANGE", "KIND", "STYLE", "LIST", "NEST", "OBJECTS", "TEXT"])
    }

    // MARK: - paragraphFormatRows: selection

    func testParagraphFormatRowsWithNoBoundsListEveryParagraphIncludingTableCells() throws {
        let rows = try decodeQuiz().paragraphFormatRows()
        // Heading, stem, option A, option B, list item, centered, the cell
        // paragraph, and the trailing paragraph — in body order, the cell's
        // paragraph after the table's position.
        XCTAssertEqual(rows.map(\.startIndex), [1, 20, 41, 52, 63, 69, 79, 88])
        XCTAssertEqual(rows.map(\.preview), [
            "Quiz 1: What is PM", "1. Which comes first", "\u{25EF} the idea", "\u{25EF} the team",
            "First", "Shaded", "In cell", "",
        ])
    }

    func testParagraphFormatRowsAtAnIndexSelectsTheContainingParagraph() throws {
        let document = try decodeQuiz()
        // 45 is inside option A [41, 52).
        let rows = try document.paragraphFormatRows(from: 45, to: 46)
        XCTAssertEqual(rows.map(\.startIndex), [41])
        // The first index of a paragraph belongs to it; its end index does not.
        XCTAssertEqual(try document.paragraphFormatRows(from: 52, to: 53).map(\.startIndex), [52])
        XCTAssertEqual(try document.paragraphFormatRows(from: 51, to: 52).map(\.startIndex), [41])
    }

    func testParagraphFormatRowsSelectEveryParagraphARangeTouches() throws {
        let document = try decodeQuiz()
        // The stem's last character through option B's first: three paragraphs.
        XCTAssertEqual(
            try document.paragraphFormatRows(from: 40, to: 53).map(\.startIndex), [20, 41, 52])
        // An open start runs from 0; an open end runs to the end.
        XCTAssertEqual(try document.paragraphFormatRows(to: 21).map(\.startIndex), [1, 20])
        XCTAssertEqual(try document.paragraphFormatRows(from: 76).map(\.startIndex), [79, 88])
        // A range past the end selects nothing.
        XCTAssertTrue(try document.paragraphFormatRows(from: 500, to: 600).isEmpty)
    }

    func testParagraphFormatRowsReadAHeaderSegmentAndRejectAnUnknownOne() throws {
        let document = try decodeQuiz()
        let rows = try document.paragraphFormatRows(segmentId: "kix.h1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].startIndex, 0)
        XCTAssertEqual(rows[0].explicit.alignment, "END")
        XCTAssertEqual(rows[0].preview, "Header")
        // An empty segment id is the body, like the write commands.
        XCTAssertEqual(try document.paragraphFormatRows(segmentId: "").count, 8)

        XCTAssertThrowsError(try document.paragraphFormatRows(segmentId: "kix.nope")) { error in
            guard case GrahamError.invalidArgument(let detail) = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
            XCTAssertTrue(detail.contains("kix.nope"), detail)
        }
    }

    // MARK: - paragraphFormatRows: explicit versus effective

    func testExplicitValuesAreOnlyWhatTheParagraphSets() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 41, to: 42)
        let optionA = try XCTUnwrap(rows.first)
        XCTAssertEqual(optionA.namedStyleType, "NORMAL_TEXT")
        XCTAssertNil(optionA.listId)
        XCTAssertEqual(optionA.explicit.indentStart, 36)
        XCTAssertEqual(optionA.explicit.indentFirstLine, 18)
        XCTAssertEqual(optionA.explicit.spaceAbove, 6)
        XCTAssertEqual(optionA.explicit.spaceBelow, 0)
        XCTAssertEqual(optionA.explicit.direction, "LEFT_TO_RIGHT")
        XCTAssertNil(optionA.explicit.indentEnd)
        XCTAssertNil(optionA.explicit.lineSpacing)
        XCTAssertNil(optionA.explicit.alignment)
        XCTAssertNil(optionA.explicit.shading)
        XCTAssertNil(optionA.explicit.keepWithNext)
        XCTAssertNil(optionA.explicit.borderTop)
    }

    func testEffectiveValuesInheritFromNormalText() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 41, to: 42)
        let optionA = try XCTUnwrap(rows.first).effective
        // Set on the paragraph: kept.
        XCTAssertEqual(optionA.indentStart, 36)
        XCTAssertEqual(optionA.indentFirstLine, 18)
        XCTAssertEqual(optionA.spaceAbove, 6)
        XCTAssertEqual(optionA.spaceBelow, 0)
        // Inherited from NORMAL_TEXT.
        XCTAssertEqual(optionA.alignment, "START")
        XCTAssertEqual(optionA.lineSpacing, 115)
        XCTAssertEqual(optionA.indentEnd, 0)
        XCTAssertEqual(optionA.spacingMode, "NEVER_COLLAPSE")
        XCTAssertEqual(optionA.keepLinesTogether, false)
        XCTAssertEqual(optionA.avoidWidowAndOrphan, true)
        XCTAssertEqual(optionA.pageBreakBefore, false)
        XCTAssertEqual(optionA.shading, "#FFFFFF")
        XCTAssertNil(optionA.borderTop, "NORMAL_TEXT sets no border, so none is inherited")
    }

    func testTheStemInheritsZeroIndentsAndSpacing() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 20, to: 21)
        let stem = try XCTUnwrap(rows.first)
        XCTAssertNil(stem.explicit.indentStart)
        XCTAssertNil(stem.explicit.spaceAbove)
        XCTAssertEqual(stem.effective.indentStart, 0)
        XCTAssertEqual(stem.effective.indentFirstLine, 0)
        XCTAssertEqual(stem.effective.spaceAbove, 0)
        XCTAssertEqual(stem.effective.spaceBelow, 0)
    }

    func testAHeadingInheritsItsNamedStyleThenNormalText() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 1, to: 2)
        let heading = try XCTUnwrap(rows.first)
        XCTAssertEqual(heading.namedStyleType, "HEADING_1")
        XCTAssertNil(heading.explicit.spaceAbove)
        // From HEADING_1.
        XCTAssertEqual(heading.effective.spaceAbove, 20)
        XCTAssertEqual(heading.effective.spaceBelow, 6)
        XCTAssertEqual(heading.effective.keepWithNext, true)
        XCTAssertEqual(heading.effective.keepLinesTogether, true)
        // HEADING_1 does not set these, so they come from NORMAL_TEXT.
        XCTAssertEqual(heading.effective.lineSpacing, 115)
        XCTAssertEqual(heading.effective.alignment, "START")
        XCTAssertEqual(heading.effective.indentStart, 0)
    }

    func testAListItemTakesItsIndentsFromTheListNestingLevel() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 63, to: 64)
        let item = try XCTUnwrap(rows.first)
        XCTAssertEqual(item.listId, "kix.list1")
        XCTAssertEqual(item.nestingLevel, 1)
        XCTAssertNil(item.explicit.indentStart)
        XCTAssertNil(item.explicit.indentFirstLine)
        // Nesting level 1 of kix.list1, not level 0 and not NORMAL_TEXT's zero.
        XCTAssertEqual(item.effective.indentStart, 72)
        XCTAssertEqual(item.effective.indentFirstLine, 54)
        // Everything else still resolves through NORMAL_TEXT.
        XCTAssertEqual(item.effective.lineSpacing, 115)
        XCTAssertEqual(item.effective.indentEnd, 0)
    }

    func testAParagraphsOwnValueBeatsTheListLevelAndNamedStyle() throws {
        let json = #"""
        {"documentId": "d",
         "body": {"content": [{"startIndex": 1, "endIndex": 5, "paragraph": {
           "paragraphStyle": {"namedStyleType": "HEADING_1",
                              "indentStart": {"magnitude": 5, "unit": "PT"},
                              "spaceAbove": {"magnitude": 1, "unit": "PT"}},
           "bullet": {"listId": "l", "nestingLevel": 0},
           "elements": [{"startIndex": 1, "endIndex": 5, "textRun": {"content": "Abc\n"}}]}}]},
         "lists": {"l": {"listProperties": {"nestingLevels": [
           {"indentStart": {"magnitude": 36, "unit": "PT"}, "indentFirstLine": {"magnitude": 18, "unit": "PT"}}]}}},
         "namedStyles": {"styles": [
           {"namedStyleType": "HEADING_1", "paragraphStyle": {"spaceAbove": {"magnitude": 20, "unit": "PT"}}},
           {"namedStyleType": "NORMAL_TEXT", "paragraphStyle": {"spaceAbove": {"magnitude": 9, "unit": "PT"}}}]}}
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))
        let row = try XCTUnwrap(try document.paragraphFormatRows().first)
        XCTAssertEqual(row.effective.indentStart, 5, "the paragraph's own indent wins")
        XCTAssertEqual(row.effective.indentFirstLine, 18, "the list level fills the unset indent")
        XCTAssertEqual(row.effective.spaceAbove, 1, "the paragraph's own spacing wins")
    }

    func testAMissingListOrLevelOrNamedStyleLeavesTheValueUnset() throws {
        let json = #"""
        {"documentId": "d",
         "body": {"content": [{"startIndex": 1, "endIndex": 5, "paragraph": {
           "paragraphStyle": {"namedStyleType": "HEADING_9"},
           "bullet": {"listId": "missing", "nestingLevel": 4},
           "elements": [{"startIndex": 1, "endIndex": 5, "textRun": {"content": "Abc\n"}}]}}]},
         "lists": {"l": {"listProperties": {"nestingLevels": [{}]}}}}
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))
        let row = try XCTUnwrap(try document.paragraphFormatRows().first)
        XCTAssertNil(row.effective.indentStart)
        XCTAssertNil(row.effective.lineSpacing)
        XCTAssertEqual(row.effective, row.explicit)
    }

    func testEveryParagraphSettingResolvesInSetterUnits() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 69, to: 70)
        let centered = try XCTUnwrap(rows.first)
        let explicit = centered.explicit
        XCTAssertEqual(explicit.alignment, "CENTER")
        XCTAssertEqual(explicit.lineSpacing, 150)
        XCTAssertEqual(explicit.spacingMode, "COLLAPSE_LISTS")
        XCTAssertEqual(explicit.keepLinesTogether, true)
        XCTAssertEqual(explicit.keepWithNext, true)
        XCTAssertEqual(explicit.avoidWidowAndOrphan, false)
        XCTAssertEqual(explicit.pageBreakBefore, true)
        XCTAssertEqual(explicit.indentEnd, 12.5)
        XCTAssertEqual(explicit.shading, "#FFFF00")
        XCTAssertEqual(
            explicit.borderTop, DocBorderFormat(color: "#000000", width: 1, padding: 2, dashStyle: "SOLID"))
        XCTAssertEqual(
            explicit.borderBetween,
            DocBorderFormat(color: "#800000", width: 0, padding: 0, dashStyle: "DOT"))
        XCTAssertNil(explicit.borderBottom)
        // The effective view keeps the explicit border and shading, and the
        // explicit false beats NORMAL_TEXT's true.
        XCTAssertEqual(centered.effective.avoidWidowAndOrphan, false)
        XCTAssertEqual(centered.effective.shading, "#FFFF00")
        XCTAssertEqual(centered.effective.borderTop?.color, "#000000")
    }

    func testACellParagraphIsResolvedLikeABodyParagraph() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 79, to: 80)
        let cell = try XCTUnwrap(rows.first)
        XCTAssertEqual(cell.explicit.indentEnd, 9)
        XCTAssertEqual(cell.effective.indentEnd, 9)
        XCTAssertEqual(cell.effective.lineSpacing, 115)
        XCTAssertEqual(cell.preview, "In cell")
    }

    // MARK: - paragraphFormatRows: rendering

    func testParagraphFormatTableShowsEffectiveValuesInSetterUnits() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 20, to: 76)
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n").map(String.init)
        XCTAssertEqual(
            lines[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init),
            [
                "RANGE", "STYLE", "ALIGN", "LINE", "ABOVE", "BELOW", "INDENT", "END", "FIRST",
                "FLAGS", "SHADING", "TEXT",
            ])
        func columns(_ line: String) -> [String] {
            line.split(separator: "  ", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        // The stem: everything inherited from NORMAL_TEXT.
        XCTAssertEqual(
            columns(lines[1]),
            [
                "20-41", "NORMAL_TEXT", "START", "115", "0", "0", "0", "0", "0", "avoid-widows",
                "#FFFFFF", "1. Which comes first",
            ])
        // Option A: its own indents and space above; no trailing `.0`.
        XCTAssertEqual(
            columns(lines[2]),
            [
                "41-52", "NORMAL_TEXT", "START", "115", "6", "0", "36", "0", "18", "avoid-widows",
                "#FFFFFF", "\u{25EF} the idea",
            ])
        // The list item: indents from nesting level 1.
        XCTAssertEqual(
            columns(lines[4]),
            [
                "63-69", "NORMAL_TEXT", "START", "115", "0", "0", "72", "0", "54", "avoid-widows",
                "#FFFFFF", "First",
            ])
        // The centered paragraph: a fractional indent, the flags, the shading.
        XCTAssertEqual(
            columns(lines[5]),
            [
                "69-76", "NORMAL_TEXT", "CENTER", "150", "0", "0", "0", "12.5", "0",
                "keep-lines keep-next page-break collapse-lists border", "#FFFF00", "Shaded",
            ])
        // Lines have no trailing whitespace.
        for line in lines {
            XCTAssertEqual(line, line.trimmingCharacters(in: .whitespaces))
        }
    }

    func testParagraphFormatFlagsIncludeBorderBetweenAndRtlOnlyWhenSet() throws {
        let json = #"""
        {"documentId": "d", "body": {"content": [
          {"startIndex": 1, "endIndex": 3, "paragraph": {
            "paragraphStyle": {"direction": "RIGHT_TO_LEFT",
              "borderBetween": {"color": {"color": {"rgbColor": {}}}, "width": {"magnitude": 2, "unit": "PT"}},
              "borderTop": {"color": {"color": {"rgbColor": {}}}, "width": {"unit": "PT"}}},
            "elements": [{"startIndex": 1, "endIndex": 3, "textRun": {"content": "a\n"}}]}},
          {"startIndex": 3, "endIndex": 5, "paragraph": {
            "elements": [{"startIndex": 3, "endIndex": 5, "textRun": {"content": "b\n"}}]}}
        ]}}
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))
        let rows = try document.paragraphFormatRows()
        // A zero-width top border is hidden, so only the between border counts.
        XCTAssertEqual(rows[0].flags, "rtl border-between")
        XCTAssertEqual(rows[1].flags, "")
        XCTAssertEqual(rows[1].tableValues[2], "", "no named styles: nothing to inherit")
    }

    func testParagraphFormatJsonCarriesExplicitAndEffective() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 41, to: 42)
        let jsonl = try OutputFormatter.render(rows, format: .jsonl)
        XCTAssertTrue(jsonl.contains(#""explicit":{"#), jsonl)
        XCTAssertTrue(jsonl.contains(#""effective":{"#), jsonl)
        XCTAssertTrue(jsonl.contains(#""indentStart":36"#), jsonl)
        XCTAssertTrue(jsonl.contains(#""lineSpacing":115"#), jsonl)
        XCTAssertTrue(jsonl.contains(#""namedStyleType":"NORMAL_TEXT""#), jsonl)

        let json = try OutputFormatter.render(rows, format: .json)
        let decoded = try GoogleJSON.decoder.decode([DocParagraphFormatRow].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, rows, "the rows round-trip through JSON")
    }

    func testParagraphFormatIdFormatPrintsStartIndices() throws {
        let rows = try decodeQuiz().paragraphFormatRows(from: 41, to: 63)
        XCTAssertEqual(try OutputFormatter.render(rows, format: .id), "41\n52")
    }

    // MARK: - textFormatRows

    func testTextFormatRowsListTheRunsARangeTouchesWhole() throws {
        let document = try decodeQuiz()
        // Index 22 is inside the bold "1. " run; the run is reported whole.
        let rows = try document.textFormatRows(from: 22, to: 23)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].startIndex, 20)
        XCTAssertEqual(rows[0].endIndex, 23)
        XCTAssertEqual(rows[0].preview, "1.")
        // Across the stem's two runs and into option A.
        XCTAssertEqual(
            try document.textFormatRows(from: 22, to: 42).map(\.startIndex), [20, 23, 41])
        // No bounds: every run in the body, cell runs included.
        XCTAssertEqual(
            try document.textFormatRows().map(\.startIndex), [1, 20, 23, 41, 52, 63, 69, 79, 88])
    }

    func testTextFormatExplicitVersusEffective() throws {
        let document = try decodeQuiz()
        let bold = try XCTUnwrap(try document.textFormatRows(from: 20, to: 21).first)
        XCTAssertEqual(bold.explicit.bold, true)
        XCTAssertNil(bold.explicit.fontSize)
        XCTAssertNil(bold.explicit.fontFamily)
        XCTAssertEqual(bold.effective.bold, true)
        XCTAssertEqual(bold.effective.italic, false)
        XCTAssertEqual(bold.effective.fontSize, 11)
        XCTAssertEqual(bold.effective.fontFamily, "Arial")
        XCTAssertEqual(bold.effective.fontWeight, 400)
        XCTAssertEqual(bold.effective.foregroundColor, "#000000")
        XCTAssertNil(bold.effective.backgroundColor, "NORMAL_TEXT's empty background is transparent")
        XCTAssertEqual(bold.effective.baselineOffset, "NONE")

        let colored = try XCTUnwrap(try document.textFormatRows(from: 41, to: 42).first)
        XCTAssertEqual(colored.explicit.foregroundColor, "#336699")
        XCTAssertEqual(colored.effective.foregroundColor, "#336699")

        let linked = try XCTUnwrap(try document.textFormatRows(from: 52, to: 53).first)
        XCTAssertEqual(linked.explicit.link, "heading:h.abc")
        XCTAssertEqual(linked.explicit.smallCaps, true)
        XCTAssertEqual(linked.explicit.baselineOffset, "SUPERSCRIPT")
        XCTAssertEqual(linked.effective.baselineOffset, "SUPERSCRIPT")

        let heading = try XCTUnwrap(try document.textFormatRows(from: 1, to: 2).first)
        XCTAssertEqual(heading.effective.fontSize, 20, "from HEADING_1")
        XCTAssertEqual(heading.effective.fontFamily, "Arial", "then NORMAL_TEXT")

        let shaded = try XCTUnwrap(try document.textFormatRows(from: 69, to: 70).first)
        XCTAssertEqual(shaded.explicit.bold, false)
        XCTAssertEqual(shaded.explicit.fontSize, 14)
        XCTAssertEqual(shaded.explicit.fontFamily, "Georgia")
        XCTAssertEqual(shaded.explicit.fontWeight, 700)
        XCTAssertEqual(shaded.explicit.backgroundColor, "#FFFF00")
    }

    func testTextFormatLinkTextCoversEveryTarget() throws {
        func link(_ json: String) throws -> String? {
            let style = try GoogleJSON.decoder.decode(DocTextStyle.self, from: Data(json.utf8))
            return DocTextFormat(style: style).link
        }
        XCTAssertEqual(try link(#"{"link": {"url": "https://x.test"}}"#), "https://x.test")
        XCTAssertEqual(try link(#"{"link": {"bookmarkId": "b1"}}"#), "bookmark:b1")
        XCTAssertEqual(try link(#"{"link": {"tabId": "t.1"}}"#), "tab:t.1")
        XCTAssertNil(try link(#"{"link": {}}"#))
        XCTAssertNil(try link("{}"))
    }

    func testTextFormatTableShowsEffectiveValues() throws {
        let rows = try decodeQuiz().textFormatRows(from: 20, to: 76)
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n").map(String.init)
        XCTAssertEqual(
            lines[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init),
            ["RANGE", "FLAGS", "SIZE", "FONT", "WEIGHT", "COLOR", "BG", "BASELINE", "LINK", "TEXT"])
        func columns(_ line: String) -> [String] {
            line.split(separator: "  ", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        XCTAssertEqual(
            columns(lines[1]), ["20-23", "bold", "11", "Arial", "400", "#000000", "1."])
        XCTAssertEqual(
            columns(lines[4]),
            ["52-63", "small-caps", "11", "Arial", "400", "#000000", "super", "heading:h.abc",
             "\u{25EF} the team"])
        XCTAssertEqual(
            columns(lines[6]), ["69-76", "14", "Georgia", "700", "#000000", "#FFFF00", "Shaded"])
        for line in lines {
            XCTAssertEqual(line, line.trimmingCharacters(in: .whitespaces))
        }
    }

    func testTextFormatJsonAndIdFormats() throws {
        let rows = try decodeQuiz().textFormatRows(from: 41, to: 63)
        XCTAssertEqual(try OutputFormatter.render(rows, format: .id), "41\n52")
        let json = try OutputFormatter.render(rows, format: .json)
        let decoded = try GoogleJSON.decoder.decode([DocTextFormatRow].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, rows)
        XCTAssertTrue(json.contains(##""foregroundColor" : "#336699""##), json)
    }

    func testTextFormatRowsReadASegment() throws {
        let rows = try decodeQuiz().textFormatRows(segmentId: "kix.h1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].explicit.italic, true)
        XCTAssertEqual(rows[0].effective.fontFamily, "Arial")
    }

    // MARK: - Range intersection

    func testIntersectsTreatsBoundsAsHalfOpenAndNilAsOpen() {
        typealias R = DocFormatResolver
        XCTAssertTrue(R.intersects(start: 10, end: 20, from: 15, to: 16))
        XCTAssertTrue(R.intersects(start: 10, end: 20, from: 19, to: 20))
        XCTAssertFalse(R.intersects(start: 10, end: 20, from: 20, to: 21))
        XCTAssertTrue(R.intersects(start: 10, end: 20, from: 5, to: 11))
        XCTAssertFalse(R.intersects(start: 10, end: 20, from: 5, to: 10))
        XCTAssertTrue(R.intersects(start: nil, end: 20, from: 0, to: 1), "an absent start is 0")
        XCTAssertTrue(R.intersects(start: 10, end: 20, from: nil, to: nil))
        XCTAssertTrue(R.intersects(start: 10, end: 20, from: nil, to: 11))
        XCTAssertFalse(R.intersects(start: 10, end: 20, from: nil, to: 10))
        XCTAssertTrue(R.intersects(start: 10, end: 20, from: 19, to: nil))
        XCTAssertFalse(R.intersects(start: 10, end: 20, from: 20, to: nil))
        XCTAssertTrue(R.intersects(start: 10, end: nil, from: 500, to: nil), "an absent end is open")
    }

    func testNumberFormattingDropsTrailingZeroOnly() {
        XCTAssertEqual(DocFormatText.number(nil), "")
        XCTAssertEqual(DocFormatText.number(0), "0")
        XCTAssertEqual(DocFormatText.number(36), "36")
        XCTAssertEqual(DocFormatText.number(115), "115")
        XCTAssertEqual(DocFormatText.number(12.5), "12.5")
        XCTAssertEqual(DocFormatText.number(0.25), "0.25")
    }
}
