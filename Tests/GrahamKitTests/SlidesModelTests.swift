import XCTest
@testable import GrahamKit

/// Decoding tests for the Slides v1 `PageElement` model foundation. Every
/// fixture is static JSON that matches the shape of a real Slides response.
/// No test touches the network.
final class SlidesModelTests: XCTestCase {
    private func decode(_ json: String) throws -> PageElement {
        try GoogleJSON.decoder.decode(PageElement.self, from: Data(json.utf8))
    }

    // MARK: - Common properties

    func testCommonPropertiesDecode() throws {
        let json = #"""
        {
            "objectId": "elem-1",
            "size": {
                "width": {"magnitude": 3000000, "unit": "EMU"},
                "height": {"magnitude": 1500000, "unit": "EMU"}
            },
            "transform": {
                "scaleX": 1.5, "scaleY": 2.0,
                "shearX": 0.1, "shearY": -0.1,
                "translateX": 838200, "translateY": 452374,
                "unit": "EMU"
            },
            "title": "Alt title",
            "description": "Alt description",
            "shape": {}
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.objectId, "elem-1")
        XCTAssertEqual(element.size?.width?.magnitude, 3000000)
        XCTAssertEqual(element.size?.width?.unit, "EMU")
        XCTAssertEqual(element.size?.height?.magnitude, 1500000)

        XCTAssertEqual(element.transform?.scaleX, 1.5)
        XCTAssertEqual(element.transform?.scaleY, 2.0)
        XCTAssertEqual(element.transform?.shearX, 0.1)
        XCTAssertEqual(element.transform?.shearY, -0.1)
        XCTAssertEqual(element.transform?.translateX, 838200)
        XCTAssertEqual(element.transform?.translateY, 452374)
        XCTAssertEqual(element.transform?.unit, "EMU")

        // Alt text lives in title and description.
        XCTAssertEqual(element.title, "Alt title")
        XCTAssertEqual(element.description, "Alt description")
    }

    func testMinimalElementDecodesWithOnlyObjectId() throws {
        // The `fields` mask can trim a response to almost nothing. Every field
        // except the type marker is optional, so this must still decode.
        let element = try decode(#"{"objectId": "bare"}"#)

        XCTAssertEqual(element.objectId, "bare")
        XCTAssertNil(element.size)
        XCTAssertNil(element.transform)
        XCTAssertEqual(element.kind, .unknown)
    }

    // MARK: - Shape

    func testShapeDecodesTypePlaceholderTextAndLinks() throws {
        let json = #"""
        {
            "objectId": "title-shape",
            "shape": {
                "shapeType": "TEXT_BOX",
                "placeholder": {"type": "TITLE", "index": 0, "parentObjectId": "layout-1"},
                "shapeProperties": {"link": {"url": "https://example.com/shape"}},
                "text": {"textElements": [
                    {"paragraphMarker": {}},
                    {"startIndex": 0, "endIndex": 6, "textRun": {
                        "content": "Hello ",
                        "style": {}
                    }},
                    {"startIndex": 6, "endIndex": 11, "textRun": {
                        "content": "world",
                        "style": {"link": {"url": "https://example.com/run"}}
                    }}
                ]}
            }
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .shape)
        XCTAssertEqual(element.shape?.shapeType, "TEXT_BOX")
        XCTAssertEqual(element.shape?.placeholder?.type, "TITLE")
        XCTAssertEqual(element.shape?.placeholder?.index, 0)
        XCTAssertEqual(element.shape?.placeholder?.parentObjectId, "layout-1")

        // A shape-level hyperlink.
        XCTAssertEqual(element.shape?.shapeProperties?.link?.url, "https://example.com/shape")

        // A hyperlink on one text run.
        let runs = element.shape?.text?.textElements ?? []
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[1].textRun?.content, "Hello ")
        XCTAssertNil(runs[1].textRun?.style?.link)
        XCTAssertEqual(runs[2].textRun?.style?.link?.url, "https://example.com/run")

        XCTAssertEqual(element.plainText, "Hello world")
    }

    func testTextRunLinkTargetVariants() throws {
        // A Slides link is exactly one of four targets. Each decodes.
        let json = #"""
        {
            "shape": {"text": {"textElements": [
                {"textRun": {"content": "a", "style": {"link": {"relativeLink": "NEXT_SLIDE"}}}},
                {"textRun": {"content": "b", "style": {"link": {"pageObjectId": "slide-42"}}}},
                {"textRun": {"content": "c", "style": {"link": {"slideIndex": 3}}}}
            ]}}
        }
        """#
        let runs = try decode(json).shape?.text?.textElements ?? []

        XCTAssertEqual(runs[0].textRun?.style?.link?.relativeLink, "NEXT_SLIDE")
        XCTAssertEqual(runs[1].textRun?.style?.link?.pageObjectId, "slide-42")
        XCTAssertEqual(runs[2].textRun?.style?.link?.slideIndex, 3)
    }

    func testAutoTextDecodesButDoesNotAddToPlainText() throws {
        // Auto-text (a slide number) is real text, but plainText keeps the
        // user's typed text only, so the number does not appear.
        let json = #"""
        {
            "shape": {"text": {"textElements": [
                {"autoText": {"type": "SLIDE_NUMBER", "content": "7"}},
                {"textRun": {"content": "Body copy"}}
            ]}}
        }
        """#
        let element = try decode(json)

        let first = element.shape?.text?.textElements?.first
        XCTAssertEqual(first?.autoText?.type, "SLIDE_NUMBER")
        XCTAssertEqual(first?.autoText?.content, "7")
        XCTAssertEqual(element.plainText, "Body copy")
    }

    // MARK: - Image

    func testImageDecodesUrlsLinkAndAltText() throws {
        let json = #"""
        {
            "objectId": "img-1",
            "title": "A cat",
            "description": "A cat on a mat",
            "image": {
                "contentUrl": "https://lh3.googleusercontent.com/abc",
                "sourceUrl": "https://example.com/cat.png",
                "imageProperties": {"link": {"url": "https://example.com/more"}}
            }
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .image)
        XCTAssertEqual(element.image?.contentUrl, "https://lh3.googleusercontent.com/abc")
        XCTAssertEqual(element.image?.sourceUrl, "https://example.com/cat.png")
        XCTAssertEqual(element.image?.imageProperties?.link?.url, "https://example.com/more")

        // Alt text is on the page element, not on the image.
        XCTAssertEqual(element.title, "A cat")
        XCTAssertEqual(element.description, "A cat on a mat")

        // An image adds no text to the slide.
        XCTAssertEqual(element.plainText, "")
    }

    func testImageWithoutSourceUrlStillDecodes() throws {
        // sourceUrl is present only for some images. Its absence must not fail.
        let json = #"""
        {"image": {"contentUrl": "https://lh3.googleusercontent.com/only"}}
        """#
        let element = try decode(json)

        XCTAssertEqual(element.image?.contentUrl, "https://lh3.googleusercontent.com/only")
        XCTAssertNil(element.image?.sourceUrl)
    }

    // MARK: - Video

    func testVideoDecodes() throws {
        let json = #"""
        {
            "objectId": "vid-1",
            "video": {
                "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "source": "YOUTUBE",
                "id": "dQw4w9WgXcQ",
                "videoProperties": {"autoPlay": true, "mute": false, "start": 5, "end": 30}
            }
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .video)
        XCTAssertEqual(element.video?.source, "YOUTUBE")
        XCTAssertEqual(element.video?.id, "dQw4w9WgXcQ")
        XCTAssertEqual(element.video?.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(element.video?.videoProperties?.autoPlay, true)
        XCTAssertEqual(element.video?.videoProperties?.mute, false)
        XCTAssertEqual(element.video?.videoProperties?.start, 5)
        XCTAssertEqual(element.video?.videoProperties?.end, 30)
    }

    // MARK: - Line and connector

    func testLineDecodesWithLink() throws {
        let json = #"""
        {
            "objectId": "line-1",
            "line": {
                "lineType": "STRAIGHT_CONNECTOR_1",
                "lineCategory": "STRAIGHT",
                "lineProperties": {
                    "dashStyle": "SOLID",
                    "weight": {"magnitude": 9525, "unit": "EMU"},
                    "link": {"url": "https://example.com/line"}
                }
            }
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .line)
        XCTAssertEqual(element.line?.lineType, "STRAIGHT_CONNECTOR_1")
        XCTAssertEqual(element.line?.lineCategory, "STRAIGHT")
        XCTAssertEqual(element.line?.lineProperties?.dashStyle, "SOLID")
        XCTAssertEqual(element.line?.lineProperties?.weight?.magnitude, 9525)
        XCTAssertEqual(element.line?.lineProperties?.link?.url, "https://example.com/line")
    }

    // MARK: - Table

    func testTableDecodesGeometryTextAndSpans() throws {
        let json = #"""
        {
            "objectId": "table-1",
            "table": {
                "rows": 2,
                "columns": 2,
                "tableRows": [
                    {"rowHeight": {"magnitude": 400000, "unit": "EMU"}, "tableCells": [
                        {"location": {"rowIndex": 0, "columnIndex": 0}, "rowSpan": 1, "columnSpan": 1,
                            "text": {"textElements": [{"textRun": {"content": "A1\n"}}]}},
                        {"location": {"rowIndex": 0, "columnIndex": 1}, "rowSpan": 1, "columnSpan": 1,
                            "text": {"textElements": [{"textRun": {"content": "B1\n"}}]}}
                    ]},
                    {"tableCells": [
                        {"location": {"rowIndex": 1, "columnIndex": 0},
                            "text": {"textElements": [{"textRun": {"content": "A2\n"}}]}},
                        {"location": {"rowIndex": 1, "columnIndex": 1},
                            "text": {"textElements": [{"textRun": {"content": "B2\n"}}]}}
                    ]}
                ]
            }
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .table)
        XCTAssertEqual(element.table?.rows, 2)
        XCTAssertEqual(element.table?.columns, 2)

        let firstCell = element.table?.tableRows?.first?.tableCells?.first
        XCTAssertEqual(firstCell?.location?.rowIndex, 0)
        XCTAssertEqual(firstCell?.location?.columnIndex, 0)
        XCTAssertEqual(firstCell?.rowSpan, 1)
        XCTAssertEqual(firstCell?.columnSpan, 1)
        XCTAssertEqual(element.table?.tableRows?.first?.rowHeight?.magnitude, 400000)

        // Tabs between cells, new lines between rows.
        XCTAssertEqual(element.plainText, "A1\tB1\nA2\tB2")
    }

    func testEmptyTableAddsNoText() throws {
        let json = #"""
        {"table": {"rows": 1, "columns": 1, "tableRows": [{"tableCells": [{}]}]}}
        """#
        XCTAssertEqual(try decode(json).plainText, "")
    }

    // MARK: - Chart from Sheets

    func testSheetsChartDecodes() throws {
        let json = #"""
        {
            "objectId": "chart-1",
            "sheetsChart": {
                "spreadsheetId": "sheet-abc",
                "chartId": 1234567890,
                "contentUrl": "https://docs.google.com/chart-image"
            }
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .sheetsChart)
        XCTAssertEqual(element.sheetsChart?.spreadsheetId, "sheet-abc")
        XCTAssertEqual(element.sheetsChart?.chartId, 1234567890)
        XCTAssertEqual(element.sheetsChart?.contentUrl, "https://docs.google.com/chart-image")
    }

    // MARK: - Word art

    func testWordArtDecodesAndAddsText() throws {
        let json = #"""
        {"objectId": "wa-1", "wordArt": {"renderedText": "SALE"}}
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .wordArt)
        XCTAssertEqual(element.wordArt?.renderedText, "SALE")
        XCTAssertEqual(element.plainText, "SALE")
    }

    // MARK: - Group (recursive)

    func testElementGroupDecodesAndNests() throws {
        let json = #"""
        {
            "objectId": "group-1",
            "elementGroup": {"children": [
                {"objectId": "g-shape", "shape": {"text": {"textElements": [
                    {"textRun": {"content": "In group"}}
                ]}}},
                {"objectId": "inner-group", "elementGroup": {"children": [
                    {"objectId": "deep-shape", "shape": {"text": {"textElements": [
                        {"textRun": {"content": "Nested deep"}}
                    ]}}},
                    {"objectId": "deep-image", "image": {"contentUrl": "https://img/deep"}}
                ]}}
            ]}
        }
        """#
        let element = try decode(json)

        XCTAssertEqual(element.kind, .group)
        let children = element.elementGroup?.children ?? []
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.first?.kind, .shape)

        // The second child is a group inside the group.
        let inner = children.last
        XCTAssertEqual(inner?.kind, .group)
        XCTAssertEqual(inner?.elementGroup?.children?.count, 2)
        XCTAssertEqual(inner?.elementGroup?.children?.first?.shape?.text?.textElements?.first?.textRun?.content, "Nested deep")

        // plainText walks the whole tree, one text block per line.
        XCTAssertEqual(element.plainText, "In group\nNested deep")
    }

    // MARK: - Kind detection

    func testKindReportsEveryType() throws {
        let cases: [(String, PageElementKind)] = [
            (#"{"shape": {}}"#, .shape),
            (#"{"image": {}}"#, .image),
            (#"{"video": {}}"#, .video),
            (#"{"line": {}}"#, .line),
            (#"{"table": {}}"#, .table),
            (#"{"sheetsChart": {}}"#, .sheetsChart),
            (#"{"wordArt": {}}"#, .wordArt),
            (#"{"elementGroup": {}}"#, .group),
            (#"{"objectId": "x"}"#, .unknown),
        ]
        for (json, expected) in cases {
            XCTAssertEqual(try decode(json).kind, expected, "for \(json)")
        }
    }

    func testUnmodeledTypeDecodesAsUnknown() throws {
        // A future element type graham does not know yet must decode, not fail.
        let json = #"""
        {"objectId": "future", "someNewKind": {"foo": 1}}
        """#
        let element = try decode(json)

        XCTAssertEqual(element.objectId, "future")
        XCTAssertEqual(element.kind, .unknown)
        XCTAssertEqual(element.plainText, "")
    }

    // MARK: - Whole presentation and plainText behavior

    func testPresentationWithMixedElementsDecodesAndReadsText() throws {
        let json = #"""
        {
            "presentationId": "p-1",
            "title": "Mixed deck",
            "slides": [
                {"objectId": "slide-1", "pageElements": [
                    {"objectId": "s-title", "shape": {"text": {"textElements": [
                        {"textRun": {"content": "Title here\n"}}
                    ]}}},
                    {"objectId": "s-image", "title": "logo", "image": {"contentUrl": "https://img/logo"}},
                    {"objectId": "s-group", "elementGroup": {"children": [
                        {"shape": {"text": {"textElements": [{"textRun": {"content": "Grouped line"}}]}}}
                    ]}},
                    {"objectId": "s-table", "table": {"tableRows": [
                        {"tableCells": [
                            {"text": {"textElements": [{"textRun": {"content": "R1C1\n"}}]}},
                            {"text": {"textElements": [{"textRun": {"content": "R1C2\n"}}]}}
                        ]}
                    ]}},
                    {"objectId": "s-word", "wordArt": {"renderedText": "BIG"}}
                ]}
            ]
        }
        """#
        let presentation = try GoogleJSON.decoder.decode(Presentation.self, from: Data(json.utf8))

        XCTAssertEqual(presentation.presentationId, "p-1")
        XCTAssertEqual(presentation.title, "Mixed deck")

        let slide = try XCTUnwrap(presentation.slides?.first)
        XCTAssertEqual(slide.pageElements?.count, 5)

        // Text comes from the shape, the group, the table, and the word art.
        // The image adds no text.
        XCTAssertEqual(slide.plainText, "Title here\nGrouped line\nR1C1\tR1C2\nBIG")
    }

    func testSlidePlainTextStillReadsPlainShapesOnly() throws {
        // This mirrors the pre-existing behavior: one shape per line, empty
        // elements dropped. The change must not regress it.
        let json = #"""
        {
            "objectId": "s1",
            "pageElements": [
                {"objectId": "e1", "shape": {"text": {"textElements": [
                    {"paragraphMarker": {}},
                    {"textRun": {"content": "Slide title\n"}}
                ]}}},
                {"objectId": "e2"}
            ]
        }
        """#
        let slide = try GoogleJSON.decoder.decode(SlidePage.self, from: Data(json.utf8))

        XCTAssertEqual(slide.plainText, "Slide title")
    }
}
