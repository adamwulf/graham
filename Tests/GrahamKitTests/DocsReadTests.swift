import XCTest
@testable import GrahamKit

/// Tests for the extended Docs read model and the structured block facade:
/// defensive decoding of the full document surface (headings, a bulleted list,
/// a linked run, an inline image, a table, a footnote, and a section break),
/// the preserved `plainText`, and the flattened ``Document/blockRows`` (kinds,
/// index ranges, nesting, previews) with its table/id/jsonl rendering. Every
/// fixture is static JSON; no test touches the network.
final class DocsReadTests: XCTestCase {
    /// One realistic document that exercises every read feature this phase
    /// adds. Body indices are internally consistent (each run's length in
    /// UTF-16 code units), so the block ranges below are exact.
    private static let fullJSON = #"""
    {
      "documentId": "doc-1",
      "title": "A rich document",
      "revisionId": "rev-123",
      "body": {"content": [
        {"endIndex": 1, "sectionBreak": {}},
        {"startIndex": 1, "endIndex": 14, "paragraph": {
          "paragraphStyle": {"namedStyleType": "HEADING_1", "alignment": "START"},
          "elements": [
            {"startIndex": 1, "endIndex": 14, "textRun": {
              "content": "Introduction\n", "textStyle": {}}}
          ]}},
        {"startIndex": 14, "endIndex": 31, "paragraph": {
          "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
          "elements": [
            {"startIndex": 14, "endIndex": 18, "textRun": {
              "content": "See ", "textStyle": {}}},
            {"startIndex": 18, "endIndex": 24, "textRun": {
              "content": "Google", "textStyle": {
                "bold": true,
                "link": {"url": "https://www.google.com"},
                "fontSize": {"magnitude": 11, "unit": "PT"},
                "weightedFontFamily": {"fontFamily": "Arial", "weight": 400}}}},
            {"startIndex": 24, "endIndex": 31, "textRun": {
              "content": " here.\n", "textStyle": {}}}
          ]}},
        {"startIndex": 31, "endIndex": 37, "paragraph": {
          "bullet": {"listId": "kix.list1", "nestingLevel": 0},
          "elements": [
            {"startIndex": 31, "endIndex": 37, "textRun": {"content": "First\n"}}
          ]}},
        {"startIndex": 37, "endIndex": 44, "paragraph": {
          "bullet": {"listId": "kix.list1", "nestingLevel": 1},
          "elements": [
            {"startIndex": 37, "endIndex": 44, "textRun": {"content": "Second\n"}}
          ]}},
        {"startIndex": 44, "endIndex": 46, "paragraph": {
          "elements": [
            {"startIndex": 44, "endIndex": 45, "inlineObjectElement": {
              "inlineObjectId": "kix.img1"}},
            {"startIndex": 45, "endIndex": 46, "textRun": {"content": "\n"}}
          ]}},
        {"startIndex": 46, "endIndex": 63, "paragraph": {
          "elements": [
            {"startIndex": 46, "endIndex": 61, "textRun": {"content": "Cite this fact."}},
            {"startIndex": 61, "endIndex": 62, "footnoteReference": {
              "footnoteId": "kix.fn1", "footnoteNumber": "1"}},
            {"startIndex": 62, "endIndex": 63, "textRun": {"content": "\n"}}
          ]}},
        {"startIndex": 63, "endIndex": 78, "table": {
          "rows": 2, "columns": 2, "tableRows": [
            {"startIndex": 64, "endIndex": 71, "tableCells": [
              {"startIndex": 64, "endIndex": 67, "content": [
                {"startIndex": 65, "endIndex": 68, "paragraph": {
                  "elements": [{"textRun": {"content": "A1\n"}}]}}]},
              {"startIndex": 67, "endIndex": 70, "content": [
                {"startIndex": 68, "endIndex": 71, "paragraph": {
                  "elements": [{"textRun": {"content": "B1\n"}}]}}]}
            ]},
            {"startIndex": 71, "endIndex": 78, "tableCells": [
              {"startIndex": 71, "endIndex": 74, "content": [
                {"startIndex": 72, "endIndex": 75, "paragraph": {
                  "elements": [{"textRun": {"content": "A2\n"}}]}}]},
              {"startIndex": 74, "endIndex": 77, "content": [
                {"startIndex": 75, "endIndex": 78, "paragraph": {
                  "elements": [{"textRun": {"content": "B2\n"}}]}}]}
            ]}
          ]}}
      ]},
      "inlineObjects": {
        "kix.img1": {
          "objectId": "kix.img1",
          "inlineObjectProperties": {"embeddedObject": {
            "title": "A chart",
            "description": "Quarterly revenue",
            "imageProperties": {
              "sourceUri": "https://example.com/chart.png",
              "contentUri": "https://lh3.googleusercontent.com/chart"},
            "size": {
              "width": {"magnitude": 400, "unit": "PT"},
              "height": {"magnitude": 300, "unit": "PT"}}
          }}
        }
      },
      "positionedObjects": {
        "kix.pos1": {
          "objectId": "kix.pos1",
          "positionedObjectProperties": {"embeddedObject": {
            "imageProperties": {
              "sourceUri": "https://example.com/logo.png",
              "contentUri": "https://lh3.googleusercontent.com/logo"},
            "size": {
              "width": {"magnitude": 100, "unit": "PT"},
              "height": {"magnitude": 100, "unit": "PT"}}
          }}
        }
      },
      "footnotes": {
        "kix.fn1": {
          "footnoteId": "kix.fn1",
          "content": [
            {"startIndex": 0, "endIndex": 19, "paragraph": {
              "elements": [{"textRun": {"content": "The footnote text.\n"}}]}}
          ]
        }
      },
      "lists": {
        "kix.list1": {"listProperties": {"nestingLevels": [
          {"glyphType": "DECIMAL", "glyphFormat": "%0."},
          {"glyphType": "ALPHA", "glyphFormat": "%1."}
        ]}}
      },
      "headers": {
        "kix.hdr1": {"headerId": "kix.hdr1", "content": [
          {"paragraph": {"elements": [{"textRun": {"content": "Header text\n"}}]}}]}
      },
      "footers": {
        "kix.ftr1": {"footerId": "kix.ftr1", "content": [
          {"paragraph": {"elements": [{"textRun": {"content": "Footer text\n"}}]}}]}
      },
      "namedRanges": {
        "greeting": {"name": "greeting", "namedRanges": [
          {"namedRangeId": "nr1", "name": "greeting", "ranges": [
            {"startIndex": 14, "endIndex": 31}]}]}
      },
      "namedStyles": {"styles": [
        {"namedStyleType": "HEADING_1", "textStyle": {"bold": true},
         "paragraphStyle": {"namedStyleType": "HEADING_1"}}
      ]},
      "documentStyle": {
        "pageSize": {"width": {"magnitude": 612, "unit": "PT"},
                     "height": {"magnitude": 792, "unit": "PT"}},
        "marginTop": {"magnitude": 72, "unit": "PT"},
        "useFirstPageHeaderFooter": false
      }
    }
    """#

    private func decodeDocument() throws -> Document {
        try GoogleJSON.decoder.decode(Document.self, from: Data(Self.fullJSON.utf8))
    }

    // MARK: - Defensive decoding of the full surface

    func testTopLevelFieldsDecode() throws {
        let document = try decodeDocument()
        XCTAssertEqual(document.documentId, "doc-1")
        XCTAssertEqual(document.title, "A rich document")
        XCTAssertEqual(document.revisionId, "rev-123")
        XCTAssertEqual(document.body?.content?.count, 8)
    }

    func testInlineObjectImageIsExposed() throws {
        let document = try decodeDocument()
        let image = try XCTUnwrap(document.inlineObjects?["kix.img1"])
        XCTAssertEqual(image.objectId, "kix.img1")

        let embedded = try XCTUnwrap(image.embeddedObject)
        XCTAssertEqual(embedded.title, "A chart")
        XCTAssertEqual(embedded.description, "Quarterly revenue")
        XCTAssertEqual(embedded.imageProperties?.sourceUri, "https://example.com/chart.png")
        XCTAssertEqual(
            embedded.imageProperties?.contentUri, "https://lh3.googleusercontent.com/chart")
        XCTAssertEqual(embedded.size?.width?.magnitude, 400)
        XCTAssertEqual(embedded.size?.width?.unit, "PT")
        XCTAssertEqual(embedded.size?.height?.magnitude, 300)
    }

    func testPositionedObjectImageIsExposed() throws {
        let document = try decodeDocument()
        let object = try XCTUnwrap(document.positionedObjects?["kix.pos1"])
        let embedded = try XCTUnwrap(object.embeddedObject)
        XCTAssertEqual(embedded.imageProperties?.sourceUri, "https://example.com/logo.png")
        XCTAssertEqual(
            embedded.imageProperties?.contentUri, "https://lh3.googleusercontent.com/logo")
        XCTAssertEqual(embedded.size?.width?.magnitude, 100)
    }

    func testFootnoteHeaderFooterSegmentsDecode() throws {
        let document = try decodeDocument()

        let footnote = try XCTUnwrap(document.footnotes?["kix.fn1"])
        XCTAssertEqual(footnote.footnoteId, "kix.fn1")
        XCTAssertEqual(footnote.plainText, "The footnote text.\n")

        XCTAssertEqual(document.headers?["kix.hdr1"]?.headerId, "kix.hdr1")
        XCTAssertEqual(document.headers?["kix.hdr1"]?.plainText, "Header text\n")
        XCTAssertEqual(document.footers?["kix.ftr1"]?.plainText, "Footer text\n")
    }

    func testListsNamedRangesNamedStylesAndDocumentStyleDecode() throws {
        let document = try decodeDocument()

        // The list backs bullet rendering; its first level is ordered decimal.
        let list = try XCTUnwrap(document.lists?["kix.list1"])
        XCTAssertEqual(list.listProperties?.nestingLevels?.first?.glyphType, "DECIMAL")
        XCTAssertEqual(list.listProperties?.nestingLevels?.count, 2)

        let named = try XCTUnwrap(document.namedRanges?["greeting"])
        XCTAssertEqual(named.namedRanges?.first?.namedRangeId, "nr1")
        XCTAssertEqual(named.namedRanges?.first?.ranges?.first?.startIndex, 14)
        XCTAssertEqual(named.namedRanges?.first?.ranges?.first?.endIndex, 31)

        XCTAssertEqual(document.namedStyles?.styles?.first?.namedStyleType, "HEADING_1")
        XCTAssertEqual(document.namedStyles?.styles?.first?.textStyle?.bold, true)

        XCTAssertEqual(document.documentStyle?.marginTop?.magnitude, 72)
        XCTAssertEqual(document.documentStyle?.pageSize?.height?.magnitude, 792)
        XCTAssertEqual(document.documentStyle?.useFirstPageHeaderFooter, false)
    }

    func testTextRunLinkAndStyleAreExposed() throws {
        let document = try decodeDocument()
        // The linked "Google" run sits in the third body element (index 2), as
        // the second paragraph element.
        let paragraph = try XCTUnwrap(document.body?.content?[2].paragraph)
        let run = try XCTUnwrap(paragraph.elements?[1].textRun)
        XCTAssertEqual(run.content, "Google")
        XCTAssertEqual(run.textStyle?.bold, true)
        XCTAssertEqual(run.textStyle?.link?.url, "https://www.google.com")
        XCTAssertEqual(run.textStyle?.fontSize?.magnitude, 11)
        XCTAssertEqual(run.textStyle?.weightedFontFamily?.fontFamily, "Arial")
        XCTAssertEqual(run.textStyle?.weightedFontFamily?.weight, 400)
    }

    func testParagraphElementKindsAreReported() throws {
        let document = try decodeDocument()
        // The image paragraph's first element is an inline object.
        let imageParagraph = try XCTUnwrap(document.body?.content?[5].paragraph)
        XCTAssertEqual(imageParagraph.elements?.first?.kind, .inlineObjectElement)
        XCTAssertEqual(
            imageParagraph.elements?.first?.inlineObjectElement?.inlineObjectId, "kix.img1")
        // The footnote paragraph's second element is a footnote reference.
        let footnoteParagraph = try XCTUnwrap(document.body?.content?[6].paragraph)
        XCTAssertEqual(footnoteParagraph.elements?[1].kind, .footnoteReference)
        XCTAssertEqual(
            footnoteParagraph.elements?[1].footnoteReference?.footnoteId, "kix.fn1")
    }

    // MARK: - plainText is unchanged

    func testPlainTextStillWorks() throws {
        let document = try decodeDocument()
        XCTAssertEqual(
            document.plainText,
            "Introduction\nSee Google here.\nFirst\nSecond\n\nCite this fact.\nA1\tB1\nA2\tB2\n")
    }

    // MARK: - blockRows structure

    func testBlockRowsFlattenDepthFirstWithExpectedKinds() throws {
        let rows = try decodeDocument().blockRows
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(rows.map(\.kind), [
            .sectionBreak, .heading, .paragraph, .listItem, .listItem,
            .paragraph, .paragraph, .table,
            // The four table cell paragraphs, flattened at depth 1.
            .paragraph, .paragraph, .paragraph, .paragraph,
        ])
        XCTAssertEqual(rows.map(\.depth), [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
    }

    func testBlockRowIndexRangesAreReportedAsIs() throws {
        let rows = try decodeDocument().blockRows

        // The first body block (the section break) has no start index; the API
        // omits it because it is 0.
        XCTAssertNil(rows[0].startIndex)
        XCTAssertEqual(rows[0].endIndex, 1)

        XCTAssertEqual(rows[1].startIndex, 1)
        XCTAssertEqual(rows[1].endIndex, 14)
        XCTAssertEqual(rows[2].startIndex, 14)
        XCTAssertEqual(rows[2].endIndex, 31)
        // The table's own range is its start index — what a table write needs.
        XCTAssertEqual(rows[7].startIndex, 63)
        XCTAssertEqual(rows[7].endIndex, 78)
    }

    func testHeadingLevelAndNamedStyle() throws {
        let rows = try decodeDocument().blockRows
        XCTAssertEqual(rows[1].kind, .heading)
        XCTAssertEqual(rows[1].namedStyleType, "HEADING_1")
        XCTAssertEqual(rows[1].headingLevel, 1)
        // A normal paragraph reports its style but no heading level.
        XCTAssertEqual(rows[2].namedStyleType, "NORMAL_TEXT")
        XCTAssertNil(rows[2].headingLevel)
    }

    func testListItemsCarryListIdAndNesting() throws {
        let rows = try decodeDocument().blockRows
        XCTAssertEqual(rows[3].kind, .listItem)
        XCTAssertEqual(rows[3].listId, "kix.list1")
        XCTAssertEqual(rows[3].nestingLevel, 0)
        XCTAssertEqual(rows[4].nestingLevel, 1)
    }

    func testBlockObjectIdsCorrelateWithInlineObjects() throws {
        let rows = try decodeDocument().blockRows
        // The image paragraph references the inline object; the id keys into
        // Document.inlineObjects.
        XCTAssertEqual(rows[5].objectIds, ["kix.img1"])
        XCTAssertNotNil(try decodeDocument().inlineObjects?[rows[5].objectIds[0]])
        // A plain paragraph references no objects.
        XCTAssertTrue(rows[2].objectIds.isEmpty)
    }

    func testBlockPreviewsAreTrimmedSingleLines() throws {
        let rows = try decodeDocument().blockRows
        XCTAssertEqual(rows[1].preview, "Introduction")
        XCTAssertEqual(rows[2].preview, "See Google here.")
        XCTAssertEqual(rows[3].preview, "First")
        XCTAssertEqual(rows[6].preview, "Cite this fact.")
        // The image paragraph's only text is a newline, so its preview is empty.
        XCTAssertEqual(rows[5].preview, "")
        // A table carries no preview of its own; the cell rows carry the text.
        XCTAssertEqual(rows[7].preview, "")
        // The flattened cell paragraphs carry the cell text.
        XCTAssertEqual(rows[8].preview, "A1")
        XCTAssertEqual(rows[9].preview, "B1")
        XCTAssertEqual(rows[10].preview, "A2")
        XCTAssertEqual(rows[11].preview, "B2")
    }

    // MARK: - Rendering

    func testBlockTableRendersColumnsAndNestingIndent() throws {
        let rows = try decodeDocument().blockRows
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let header = try XCTUnwrap(lines.first)
        XCTAssertTrue(header.hasPrefix("RANGE"), header)
        for column in ["KIND", "STYLE", "LIST", "NEST", "OBJECTS"] {
            XCTAssertTrue(header.contains(column), "\(column) missing from header: \(header)")
        }
        XCTAssertTrue(header.hasSuffix("TEXT"), header)

        // The heading row: range 1-14, kind heading, style HEADING_1, its
        // preview last.
        let headingLine = try XCTUnwrap(lines.first { $0.contains("HEADING_1") })
        XCTAssertTrue(headingLine.hasPrefix("1-14 "), headingLine)
        XCTAssertTrue(headingLine.contains("heading"), headingLine)
        XCTAssertTrue(headingLine.hasSuffix("Introduction"), headingLine)

        // A flattened cell paragraph is indented by its depth (two spaces).
        let cellLine = try XCTUnwrap(lines.first { $0.hasSuffix("A1") })
        XCTAssertTrue(cellLine.contains("  paragraph"), cellLine)
    }

    func testBlockIdFormatPrintsStartIndices() throws {
        let rows = try decodeDocument().blockRows
        let ids = try OutputFormatter.render(rows, format: .id)
        let lines = ids.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.count, rows.count)
        // The first block's start is omitted by the API, so it prints as 0.
        XCTAssertEqual(lines[0], "0")
        XCTAssertEqual(lines[1], "1")
        XCTAssertEqual(lines[7], "63")
    }

    func testBlockJsonlIsOneObjectPerRowWithDetail() throws {
        let rows = try decodeDocument().blockRows
        let jsonl = try OutputFormatter.render(rows, format: .jsonl)
        let lines = jsonl.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, rows.count)

        // The heading row carries the full detail the table collapses.
        let headingLine = try XCTUnwrap(lines.first { $0.contains(#""kind":"heading""#) })
        XCTAssertTrue(headingLine.contains(#""headingLevel":1"#), headingLine)
        XCTAssertTrue(headingLine.contains(#""namedStyleType":"HEADING_1""#), headingLine)
        XCTAssertTrue(headingLine.contains(#""startIndex":1"#), headingLine)

        // The list item row carries its list id and nesting level.
        let listLine = try XCTUnwrap(lines.first { $0.contains(#""kind":"listItem""#) })
        XCTAssertTrue(listLine.contains(#""listId":"kix.list1""#), listLine)
        XCTAssertTrue(listLine.contains(#""nestingLevel":0"#), listLine)
    }

    // MARK: - Defensive and empty cases

    func testUnknownStructuralElementDecodesAsUnknownBlock() throws {
        // A body with only a block kind graham does not model still decodes and
        // flattens to a single row of kind `unknown`.
        let json = #"""
        {"documentId": "d", "body": {"content": [
            {"startIndex": 0, "endIndex": 5, "someFutureBlock": {"x": 1}}
        ]}}
        """#
        let document = try GoogleJSON.decoder.decode(Document.self, from: Data(json.utf8))
        let rows = document.blockRows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .unknown)
        XCTAssertEqual(rows[0].endIndex, 5)
    }

    func testEmptyDocumentYieldsNoBlockRows() throws {
        let document = try GoogleJSON.decoder.decode(
            Document.self, from: Data(#"{"documentId": "d"}"#.utf8))
        XCTAssertTrue(document.blockRows.isEmpty)
        XCTAssertEqual(document.plainText, "")
    }
}
