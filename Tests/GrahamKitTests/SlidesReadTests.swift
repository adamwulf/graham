import XCTest
@testable import GrahamKit

/// Tests for the detailed read facade: flattening every slide's elements
/// (groups and their nested children), the geometry summary, link and alt-text
/// extraction, image filtering, and the table/id/jsonl rendering. Every
/// fixture is static JSON; no test touches the network.
final class SlidesReadTests: XCTestCase {
    /// A presentation that mixes all nine element types, a group nested inside
    /// a group, several link kinds, alt text, and a second slide.
    private static let mixedJSON = #"""
    {
      "presentationId": "p-1",
      "title": "Mixed deck",
      "slides": [
        {
          "objectId": "slide-1",
          "pageElements": [
            {
              "objectId": "sh1",
              "title": "Heading",
              "description": "The heading shape",
              "size": {
                "width": {"magnitude": 1270000, "unit": "EMU"},
                "height": {"magnitude": 635000, "unit": "EMU"}
              },
              "transform": {
                "scaleX": 1, "scaleY": 1, "shearX": 0, "shearY": 0,
                "translateX": 127000, "translateY": 254000, "unit": "EMU"
              },
              "shape": {
                "shapeType": "TEXT_BOX",
                "shapeProperties": {"link": {"url": "https://example.com/shape"}},
                "text": {"textElements": [
                  {"textRun": {"content": "Hello "}},
                  {"textRun": {"content": "world",
                    "style": {"link": {"url": "https://example.com/word"}}}}
                ]}
              }
            },
            {
              "objectId": "img1",
              "title": "A cat",
              "description": "A cat on a mat",
              "transform": {
                "scaleX": 0.70710678, "scaleY": 0.70710678,
                "shearX": -0.70710678, "shearY": 0.70710678,
                "translateX": 0, "translateY": 0, "unit": "EMU"
              },
              "image": {
                "contentUrl": "https://lh3.googleusercontent.com/one",
                "sourceUrl": "https://example.com/cat.png",
                "imageProperties": {"link": {"url": "https://example.com/more"}}
              }
            },
            {
              "objectId": "grp1",
              "elementGroup": {"children": [
                {"objectId": "g-sh", "shape": {"text": {"textElements": [
                  {"textRun": {"content": "In group"}}
                ]}}},
                {"objectId": "grp2", "elementGroup": {"children": [
                  {"objectId": "deep-sh", "shape": {"text": {"textElements": [
                    {"textRun": {"content": "Nested deep"}}
                  ]}}},
                  {"objectId": "deep-img", "image": {
                    "contentUrl": "https://lh3.googleusercontent.com/deep"
                  }}
                ]}}
              ]}
            },
            {
              "objectId": "tbl1",
              "table": {"rows": 1, "columns": 2, "tableRows": [
                {"tableCells": [
                  {"text": {"textElements": [{"textRun": {"content": "A1\n"}}]}},
                  {"text": {"textElements": [{"textRun": {"content": "B1\n",
                    "style": {"link": {"pageObjectId": "slide-2"}}}}]}}
                ]}
              ]}
            },
            {
              "objectId": "vid1",
              "video": {"url": "https://youtu.be/abc", "source": "YOUTUBE", "id": "abc"}
            },
            {
              "objectId": "ln1",
              "line": {"lineType": "STRAIGHT_CONNECTOR_1",
                "lineProperties": {"link": {"relativeLink": "NEXT_SLIDE"}}}
            },
            {"objectId": "wa1", "wordArt": {"renderedText": "SALE"}},
            {"objectId": "ch1", "sheetsChart": {"spreadsheetId": "s", "chartId": 7,
              "contentUrl": "https://docs.google.com/chart"}},
            {"objectId": "spot1", "title": "Presenter",
              "speakerSpotlight": {"speakerSpotlightProperties": {}}}
          ]
        },
        {
          "objectId": "slide-2",
          "pageElements": [
            {"objectId": "sh2", "shape": {"shapeType": "RECTANGLE"}},
            {"objectId": "img-nourl", "title": "no url", "image": {
              "sourceUrl": "https://example.com/only-source.png"
            }}
          ]
        }
      ]
    }
    """#

    private func decodePresentation() throws -> Presentation {
        try GoogleJSON.decoder.decode(Presentation.self, from: Data(Self.mixedJSON.utf8))
    }

    // MARK: - Flattening order and identity

    func testElementRowsFlattenInDepthFirstOrder() throws {
        let rows = try decodePresentation().elementRows

        XCTAssertEqual(rows.map(\.objectId), [
            "sh1", "img1", "grp1", "g-sh", "grp2", "deep-sh", "deep-img",
            "tbl1", "vid1", "ln1", "wa1", "ch1", "spot1",
            "sh2", "img-nourl",
        ])
    }

    func testEveryKindIsReported() throws {
        let rows = try decodePresentation().elementRows
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.objectId, $0.kind) })

        XCTAssertEqual(byId["sh1"], .shape)
        XCTAssertEqual(byId["img1"], .image)
        XCTAssertEqual(byId["grp1"], .group)
        XCTAssertEqual(byId["tbl1"], .table)
        XCTAssertEqual(byId["vid1"], .video)
        XCTAssertEqual(byId["ln1"], .line)
        XCTAssertEqual(byId["wa1"], .wordArt)
        XCTAssertEqual(byId["ch1"], .sheetsChart)
        XCTAssertEqual(byId["spot1"], .speakerSpotlight)
    }

    func testSlideIndexAndSlideIdTrackTheOwningSlide() throws {
        let rows = try decodePresentation().elementRows
        let sh1 = try XCTUnwrap(rows.first { $0.objectId == "sh1" })
        let sh2 = try XCTUnwrap(rows.first { $0.objectId == "sh2" })

        XCTAssertEqual(sh1.slideIndex, 0)
        XCTAssertEqual(sh1.slideId, "slide-1")
        XCTAssertEqual(sh2.slideIndex, 1)
        XCTAssertEqual(sh2.slideId, "slide-2")
    }

    func testNestedChildrenCarryParentAndDepth() throws {
        let rows = try decodePresentation().elementRows
        func row(_ id: String) throws -> SlideElementRow {
            try XCTUnwrap(rows.first { $0.objectId == id })
        }

        // Top-level group.
        XCTAssertEqual(try row("grp1").depth, 0)
        XCTAssertNil(try row("grp1").parentObjectId)
        // Direct children of grp1.
        XCTAssertEqual(try row("g-sh").depth, 1)
        XCTAssertEqual(try row("g-sh").parentObjectId, "grp1")
        XCTAssertEqual(try row("grp2").depth, 1)
        XCTAssertEqual(try row("grp2").parentObjectId, "grp1")
        // Grandchildren, inside the inner group.
        XCTAssertEqual(try row("deep-sh").depth, 2)
        XCTAssertEqual(try row("deep-sh").parentObjectId, "grp2")
        XCTAssertEqual(try row("deep-img").depth, 2)
        XCTAssertEqual(try row("deep-img").parentObjectId, "grp2")
    }

    // MARK: - findElement

    func testFindElementFindsATopLevelElement() throws {
        let presentation = try decodePresentation()
        let element = try XCTUnwrap(presentation.findElement(objectId: "img1"))
        XCTAssertEqual(element.objectId, "img1")
        XCTAssertEqual(element.kind, .image)
    }

    func testFindElementRecursesIntoNestedGroups() throws {
        let presentation = try decodePresentation()

        // One level deep, a direct child of grp1.
        let child = try XCTUnwrap(presentation.findElement(objectId: "g-sh"))
        XCTAssertEqual(child.objectId, "g-sh")
        XCTAssertEqual(child.kind, .shape)

        // Two levels deep, inside the inner group grp2. This proves the search
        // recurses through nested groups, not just the top level.
        let deep = try XCTUnwrap(presentation.findElement(objectId: "deep-img"))
        XCTAssertEqual(deep.objectId, "deep-img")
        XCTAssertEqual(deep.kind, .image)

        // The group object itself is findable too.
        XCTAssertEqual(try XCTUnwrap(presentation.findElement(objectId: "grp2")).kind, .group)
    }

    func testFindElementReturnsNilForAMissingId() throws {
        let presentation = try decodePresentation()
        XCTAssertNil(presentation.findElement(objectId: "does-not-exist"))
    }

    func testFindElementReturnsNilOnAnEmptyPresentation() throws {
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(#"{"presentationId": "p"}"#.utf8)
        )
        XCTAssertNil(presentation.findElement(objectId: "sh1"))
    }

    // MARK: - Text

    func testTextIsDirectAndGroupsCarryNone() throws {
        let rows = try decodePresentation().elementRows
        func text(_ id: String) throws -> String {
            try XCTUnwrap(rows.first { $0.objectId == id }).text
        }

        XCTAssertEqual(try text("sh1"), "Hello world")
        XCTAssertEqual(try text("g-sh"), "In group")
        XCTAssertEqual(try text("deep-sh"), "Nested deep")
        XCTAssertEqual(try text("tbl1"), "A1\tB1")
        XCTAssertEqual(try text("wa1"), "SALE")
        // A group has no text of its own; its children carry it.
        XCTAssertEqual(try text("grp1"), "")
        XCTAssertEqual(try text("grp2"), "")
        // Non-text elements add nothing.
        XCTAssertEqual(try text("img1"), "")
        XCTAssertEqual(try text("vid1"), "")
        XCTAssertEqual(try text("spot1"), "")
    }

    func testSlidePlainTextIsUnchanged() throws {
        // The reader facade must not regress `slides cat`. The slide's
        // aggregated plainText still walks groups and joins one block per line.
        let slide = try XCTUnwrap(decodePresentation().slides?.first)
        XCTAssertEqual(slide.plainText, "Hello world\nIn group\nNested deep\nA1\tB1\nSALE")
    }

    // MARK: - Geometry

    func testGeometryPreservesRawTransformAndSizeWithUnits() throws {
        let rows = try decodePresentation().elementRows
        let sh1 = try XCTUnwrap(rows.first { $0.objectId == "sh1" })
        let geometry = sh1.geometry

        XCTAssertEqual(geometry.translateX, 127000)
        XCTAssertEqual(geometry.translateY, 254000)
        XCTAssertEqual(geometry.scaleX, 1)
        XCTAssertEqual(geometry.scaleY, 1)
        XCTAssertEqual(geometry.shearX, 0)
        XCTAssertEqual(geometry.shearY, 0)
        XCTAssertEqual(geometry.transformUnit, "EMU")
        XCTAssertEqual(geometry.width, 1270000)
        XCTAssertEqual(geometry.height, 635000)
        XCTAssertEqual(geometry.sizeUnit, "EMU")
        // No rotation: atan2(0, 1) == 0.
        XCTAssertEqual(try XCTUnwrap(geometry.rotationDegrees), 0, accuracy: 0.0001)
    }

    func testRotationIsDerivedFromTheTransform() throws {
        let rows = try decodePresentation().elementRows
        // img1 is scaled and rotated 45 degrees: scaleX == shearY == cos/sin 45.
        let img1 = try XCTUnwrap(rows.first { $0.objectId == "img1" })
        XCTAssertEqual(try XCTUnwrap(img1.geometry.rotationDegrees), 45, accuracy: 0.0001)
    }

    func testRotationIsNilWithoutTheNeededFields() throws {
        let rows = try decodePresentation().elementRows
        // sh2 has no transform at all.
        let sh2 = try XCTUnwrap(rows.first { $0.objectId == "sh2" })
        XCTAssertNil(sh2.geometry.rotationDegrees)
        XCTAssertNil(sh2.geometry.translateX)
    }

    func testPointConversionFromEmuAndPt() {
        // EMU is the default and converts by 12700 per point.
        XCTAssertEqual(try XCTUnwrap(SlideElementGeometry.points(127000, unit: "EMU")), 10, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SlideElementGeometry.points(127000, unit: nil)), 10, accuracy: 0.0001)
        // A value already in points is passed through.
        XCTAssertEqual(try XCTUnwrap(SlideElementGeometry.points(72, unit: "PT")), 72, accuracy: 0.0001)
        XCTAssertNil(SlideElementGeometry.points(nil, unit: "EMU"))
    }

    // MARK: - Links

    func testShapeCollectsItsOwnLinkAndItsTextRunLinks() throws {
        let rows = try decodePresentation().elementRows
        let sh1 = try XCTUnwrap(rows.first { $0.objectId == "sh1" })

        XCTAssertEqual(sh1.links.count, 2)
        let shapeLink = try XCTUnwrap(sh1.links.first { $0.source == "shape" })
        XCTAssertEqual(shapeLink.url, "https://example.com/shape")
        XCTAssertNil(shapeLink.text)

        let runLink = try XCTUnwrap(sh1.links.first { $0.source == "textRun" })
        XCTAssertEqual(runLink.url, "https://example.com/word")
        // The run link is labelled with the text it sits on.
        XCTAssertEqual(runLink.text, "world")
    }

    func testImageLineTableAndVideoLinks() throws {
        let rows = try decodePresentation().elementRows
        func links(_ id: String) throws -> [SlideElementLink] {
            try XCTUnwrap(rows.first { $0.objectId == id }).links
        }

        // Image link.
        XCTAssertEqual(try links("img1").first?.url, "https://example.com/more")
        XCTAssertEqual(try links("img1").first?.source, "image")

        // Line link, a relative target.
        let lineLink = try XCTUnwrap(try links("ln1").first)
        XCTAssertEqual(lineLink.source, "line")
        XCTAssertEqual(lineLink.relativeLink, "NEXT_SLIDE")
        XCTAssertNil(lineLink.url)

        // Table cell link, a page-object target, labelled with the cell text.
        let tableLink = try XCTUnwrap(try links("tbl1").first)
        XCTAssertEqual(tableLink.source, "table")
        XCTAssertEqual(tableLink.pageObjectId, "slide-2")
        XCTAssertEqual(tableLink.text, "B1")

        // A video's media URL is reported as a link so nothing is lost.
        let videoLink = try XCTUnwrap(try links("vid1").first)
        XCTAssertEqual(videoLink.source, "video")
        XCTAssertEqual(videoLink.url, "https://youtu.be/abc")
    }

    func testGroupRowHasNoLinksOfItsOwn() throws {
        let rows = try decodePresentation().elementRows
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.objectId == "grp1" }).links.isEmpty)
    }

    // MARK: - Alt text and image URLs

    func testAltTextAndImageUrlsAreExposed() throws {
        let rows = try decodePresentation().elementRows
        let img1 = try XCTUnwrap(rows.first { $0.objectId == "img1" })

        XCTAssertEqual(img1.title, "A cat")
        XCTAssertEqual(img1.description, "A cat on a mat")
        XCTAssertEqual(img1.imageContentUrl, "https://lh3.googleusercontent.com/one")
        XCTAssertEqual(img1.imageSourceUrl, "https://example.com/cat.png")

        // A shape's alt text is exposed too, and it has no image URLs.
        let sh1 = try XCTUnwrap(rows.first { $0.objectId == "sh1" })
        XCTAssertEqual(sh1.title, "Heading")
        XCTAssertNil(sh1.imageContentUrl)
    }

    // MARK: - Image rows

    func testImageRowsListEveryImageRecursively() throws {
        let images = try decodePresentation().imageRows

        // img1 (slide 1), deep-img (nested two groups deep, slide 1),
        // img-nourl (slide 2). Depth-first order.
        XCTAssertEqual(images.map(\.objectId), ["img1", "deep-img", "img-nourl"])
        XCTAssertEqual(images.map(\.slideIndex), [0, 0, 1])
    }

    func testImageRowsCarryUrlsAndAltText() throws {
        let images = try decodePresentation().imageRows
        let img1 = try XCTUnwrap(images.first { $0.objectId == "img1" })

        XCTAssertEqual(img1.slideId, "slide-1")
        XCTAssertEqual(img1.contentUrl, "https://lh3.googleusercontent.com/one")
        XCTAssertEqual(img1.sourceUrl, "https://example.com/cat.png")
        XCTAssertEqual(img1.title, "A cat")

        // An image whose content URL the fields mask trimmed still lists, with
        // a nil content URL (a download would skip it).
        let bare = try XCTUnwrap(images.first { $0.objectId == "img-nourl" })
        XCTAssertNil(bare.contentUrl)
        XCTAssertEqual(bare.sourceUrl, "https://example.com/only-source.png")
    }

    // MARK: - Rendering

    func testElementTableRendersColumnsAndNestingIndent() throws {
        let rows = try decodePresentation().elementRows
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // The header carries every column, in order. The exact spacing is
        // data-driven (columns pad to their widest value), so this checks the
        // column names, not their padding.
        let header = try XCTUnwrap(lines.first)
        XCTAssertTrue(header.hasPrefix("SLIDE"), header)
        for column in ["ELEMENT", "TYPE", "POS(pt)", "SIZE(pt)", "LINKS"] {
            XCTAssertTrue(header.contains(column), "\(column) missing from header: \(header)")
        }
        XCTAssertTrue(header.hasSuffix("TEXT"), header)

        // sh1: slide 1, position 10,20 pt, size 100x50 pt, its text last.
        let sh1Line = try XCTUnwrap(lines.first { $0.contains("sh1") })
        XCTAssertTrue(sh1Line.hasPrefix("1 "), sh1Line)
        XCTAssertTrue(sh1Line.contains("10,20"), sh1Line)
        XCTAssertTrue(sh1Line.contains("100x50"), sh1Line)
        XCTAssertTrue(sh1Line.hasSuffix("Hello world"), sh1Line)

        // A nested child's TYPE is indented by its depth (two spaces per level).
        let deepLine = try XCTUnwrap(lines.first { $0.contains("deep-sh") })
        XCTAssertTrue(deepLine.contains("    shape"), deepLine)
    }

    func testElementIdFormatListsObjectIdsOnePerLine() throws {
        let rows = try decodePresentation().elementRows
        let ids = try OutputFormatter.render(rows, format: .id)
        XCTAssertEqual(ids.split(separator: "\n").first, "sh1")
        XCTAssertEqual(ids.split(separator: "\n").count, rows.count)
    }

    func testElementJsonlIsOneObjectPerRowAndDecodes() throws {
        let rows = try decodePresentation().elementRows
        let jsonl = try OutputFormatter.render(rows, format: .jsonl)
        let lines = jsonl.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, rows.count)
        // Each line is a self-contained JSON object with the row's key fields.
        let first = try XCTUnwrap(lines.first)
        XCTAssertTrue(first.contains(#""objectId":"sh1""#), first)
        XCTAssertTrue(first.contains(#""kind":"shape""#), first)
        XCTAssertTrue(first.contains(#""slideIndex":0"#), first)

        // The image row carries the full detail the table omits: the raw
        // geometry (with its derived rotation), the links, the alt text, and
        // both image URLs. (JSONEncoder escapes "/" as "\/", so the host is
        // matched rather than the whole URL.)
        let imageLine = try XCTUnwrap(lines.first { $0.contains(#""objectId":"img1""#) })
        XCTAssertTrue(imageLine.contains(#""imageContentUrl""#), imageLine)
        XCTAssertTrue(imageLine.contains("lh3.googleusercontent.com"), imageLine)
        XCTAssertTrue(imageLine.contains(#""imageSourceUrl""#), imageLine)
        XCTAssertTrue(imageLine.contains(#""rotationDegrees":45"#), imageLine)
        XCTAssertTrue(imageLine.contains(#""title":"A cat""#), imageLine)
        XCTAssertTrue(imageLine.contains(#""source":"image""#), imageLine)
    }

    func testImageTableRendersUsefulColumns() throws {
        let images = try decodePresentation().imageRows
        let table = try OutputFormatter.render(images, format: .table)
        let lines = table.split(separator: "\n").map(String.init)

        let header = try XCTUnwrap(lines.first)
        XCTAssertTrue(header.hasPrefix("SLIDE"), header)
        for column in ["ELEMENT", "ALT", "SOURCE_URL"] {
            XCTAssertTrue(header.contains(column), "\(column) missing from header: \(header)")
        }
        XCTAssertTrue(header.hasSuffix("CONTENT_URL"), header)

        // The content URL is last (unpadded), so the row ends with it.
        let img1Line = try XCTUnwrap(lines.first { $0.contains("img1") })
        XCTAssertTrue(img1Line.contains("A cat"), img1Line)
        XCTAssertTrue(img1Line.hasSuffix("https://lh3.googleusercontent.com/one"), img1Line)
    }

    func testOneLineCollapsesAndTruncates() {
        // Newlines and tabs are collapsed so a table row never breaks.
        XCTAssertEqual(SlideElementRow.oneLine("a\nb\tc"), "a / b c")
        // Long text is truncated with an ellipsis to the limit.
        let long = String(repeating: "x", count: 100)
        let short = SlideElementRow.oneLine(long, limit: 10)
        XCTAssertEqual(short.count, 10)
        XCTAssertTrue(short.hasSuffix("\u{2026}"))
    }

    // MARK: - Layouts

    /// A presentation with two layouts, one missing its display name.
    private static let layoutsJSON = #"""
    {
      "presentationId": "p-layouts",
      "layouts": [
        {"objectId": "layout-1", "layoutProperties": {
          "name": "TITLE", "displayName": "Title Slide", "masterObjectId": "master-1"}},
        {"objectId": "layout-2", "layoutProperties": {
          "name": "TITLE_AND_BODY", "masterObjectId": "master-1"}}
      ]
    }
    """#

    private func decodeLayouts() throws -> Presentation {
        try GoogleJSON.decoder.decode(Presentation.self, from: Data(Self.layoutsJSON.utf8))
    }

    func testLayoutRowsExposeIdNameAndDisplayName() throws {
        let rows = try decodeLayouts().layoutRows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].objectId, "layout-1")
        XCTAssertEqual(rows[0].name, "TITLE")
        XCTAssertEqual(rows[0].displayName, "Title Slide")
        XCTAssertEqual(rows[1].objectId, "layout-2")
        XCTAssertEqual(rows[1].name, "TITLE_AND_BODY")
        XCTAssertNil(rows[1].displayName)
    }

    func testLayoutTableRendersColumns() throws {
        let rows = try decodeLayouts().layoutRows
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let header = try XCTUnwrap(lines.first)
        XCTAssertTrue(header.hasPrefix("LAYOUT"), header)
        XCTAssertTrue(header.contains("NAME"), header)
        XCTAssertTrue(header.hasSuffix("DISPLAY_NAME"), header)

        let first = try XCTUnwrap(lines.first { $0.contains("layout-1") })
        XCTAssertTrue(first.contains("TITLE"), first)
        XCTAssertTrue(first.hasSuffix("Title Slide"), first)
    }

    func testLayoutRowsAreEmptyWithoutLayouts() throws {
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(#"{"presentationId": "p"}"#.utf8))
        XCTAssertTrue(presentation.layoutRows.isEmpty)
    }

    // MARK: - Empty and defensive cases

    func testEmptyPresentationYieldsNoRows() throws {
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(#"{"presentationId": "p"}"#.utf8)
        )
        XCTAssertTrue(presentation.elementRows.isEmpty)
        XCTAssertTrue(presentation.imageRows.isEmpty)
    }
}
