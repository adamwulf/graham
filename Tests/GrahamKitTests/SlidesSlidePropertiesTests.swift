import XCTest
@testable import GrahamKit

/// Tests for the slide-properties read facade (skipped flag and background)
/// and ``SlidesClient/setSlideProperties(presentationId:slideId:skipped:background:)``.
/// Every fixture is static JSON shaped like a live `presentations.get`; no test
/// touches the network, and the batch-update bodies are asserted exactly (the
/// shared encoder sorts keys).
final class SlidesSlidePropertiesTests: GrahamTestCase {

    /// One slide per background form the API reports. A rendered fill arrives
    /// with its `propertyState` omitted; an untouched slide reports `INHERIT`;
    /// `isSkipped` is omitted when false.
    private static let propertiesJSON = #"""
    {
      "presentationId": "p-props",
      "slides": [
        {
          "objectId": "slide-1",
          "pageProperties": {"pageBackgroundFill": {"propertyState": "INHERIT"}}
        },
        {
          "objectId": "slide-2",
          "slideProperties": {"isSkipped": true},
          "pageProperties": {"pageBackgroundFill": {"solidFill": {"alpha": 1,
            "color": {"rgbColor": {"red": 0.07058824, "green": 0.20392157, "blue": 0.3372549}}}}}
        },
        {
          "objectId": "slide-3",
          "pageProperties": {"pageBackgroundFill": {"solidFill": {"alpha": 1,
            "color": {"themeColor": "ACCENT2"}}}}
        },
        {
          "objectId": "slide-4",
          "pageProperties": {"pageBackgroundFill": {"stretchedPictureFill": {
            "contentUrl": "https://lh7-rt.googleusercontent.com/picture"}}}
        },
        {
          "objectId": "slide-5",
          "slideProperties": {"isSkipped": true},
          "pageProperties": {"pageBackgroundFill": {"propertyState": "NOT_RENDERED",
            "solidFill": {"alpha": 1, "color": {"rgbColor": {"green": 1}}}}}
        },
        {
          "objectId": "slide-6"
        },
        {
          "objectId": "slide-7",
          "pageProperties": {"pageBackgroundFill": {"solidFill": {
            "color": {"rgbColor": {"red": 1}}}}}
        }
      ]
    }
    """#

    private func decodeProperties() throws -> Presentation {
        try GoogleJSON.decoder.decode(Presentation.self, from: Data(Self.propertiesJSON.utf8))
    }

    // MARK: - Read facade

    func testSlidePropertiesRowsCoverEveryBackgroundForm() throws {
        let rows = try decodeProperties().slidePropertiesRows
        XCTAssertEqual(rows.map(\.slideNumber), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(rows.map(\.slideId), [
            "slide-1", "slide-2", "slide-3", "slide-4", "slide-5", "slide-6", "slide-7",
        ])
        // An omitted isSkipped is false.
        XCTAssertEqual(rows.map(\.skipped), [false, true, false, false, true, false, false])
        XCTAssertEqual(rows.map(\.background), [
            "inherit",   // an untouched slide reports INHERIT
            "#123456",   // an RGB fill, channels scaled to 0...255
            "accent2",   // a theme fill, lowercased as `--background` takes it
            "image",     // a stretched picture
            "none",      // NOT_RENDERED wins over the leftover solid fill
            "inherit",   // no pageProperties at all is inherited
            "#FF0000",   // omitted RGB channels are 0
        ])
        // Only the picture carries a URL.
        XCTAssertEqual(rows[3].backgroundImageUrl, "https://lh7-rt.googleusercontent.com/picture")
        XCTAssertEqual(rows.compactMap(\.backgroundImageUrl).count, 1)
    }

    func testSlidePropertiesRowsLetThePropertyStateWinOverALeftoverFill() throws {
        // A fill left behind under NOT_RENDERED or INHERIT is not shown, so it
        // neither changes the background nor reports a picture URL. An explicit
        // RENDERED state reads like the usual omitted one.
        let json = #"""
        {"slides":[
          {"objectId":"s1","pageProperties":{"pageBackgroundFill":{"propertyState":"NOT_RENDERED",
            "stretchedPictureFill":{"contentUrl":"https://lh7-rt.googleusercontent.com/old"}}}},
          {"objectId":"s2","pageProperties":{"pageBackgroundFill":{"propertyState":"INHERIT",
            "stretchedPictureFill":{"contentUrl":"https://lh7-rt.googleusercontent.com/old"}}}},
          {"objectId":"s3","pageProperties":{"pageBackgroundFill":{"propertyState":"INHERIT",
            "solidFill":{"color":{"rgbColor":{"red":1}}}}}},
          {"objectId":"s4","pageProperties":{"pageBackgroundFill":{"propertyState":"RENDERED",
            "solidFill":{"color":{"themeColor":"DARK1"}}}}}
        ]}
        """#
        let rows = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(json.utf8)).slidePropertiesRows
        XCTAssertEqual(rows.map(\.background), ["none", "inherit", "inherit", "dark1"])
        XCTAssertEqual(rows.map(\.backgroundImageUrl), [nil, nil, nil, nil])
    }

    func testSlidePropertiesRowsReportAPictureBeforeAColor() throws {
        // The live test's slide-verify relies on this order: if a color write
        // ever left the old picture rendered, the read would say `image`.
        let json = #"""
        {"slides":[{"objectId":"s1","pageProperties":{"pageBackgroundFill":{
          "solidFill":{"color":{"rgbColor":{"red":1}}},
          "stretchedPictureFill":{"contentUrl":"https://lh7-rt.googleusercontent.com/old"}}}}]}
        """#
        let row = try XCTUnwrap(GoogleJSON.decoder.decode(
            Presentation.self, from: Data(json.utf8)).slidePropertiesRows.first)
        XCTAssertEqual(row.background, "image")
        XCTAssertEqual(row.backgroundImageUrl, "https://lh7-rt.googleusercontent.com/old")
    }

    func testSlidePropertiesRowsReadAnUnrecognizedFillAsEmpty() throws {
        // A rendered fill with neither a solid color nor a picture, and a theme
        // color outside ThemeColorName, are not forms `--background` can
        // express, so each is empty rather than guessed.
        let json = #"""
        {"slides":[
          {"objectId":"s1","pageProperties":{"pageBackgroundFill":{}}},
          {"objectId":"s2","pageProperties":{"pageBackgroundFill":{"solidFill":{
            "color":{"themeColor":"THEME_COLOR_TYPE_UNSPECIFIED"}}}}}
        ]}
        """#
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(json.utf8))
        XCTAssertEqual(presentation.slidePropertiesRows.map(\.background), ["", ""])
    }

    func testSlidePropertiesTableRendersColumns() throws {
        let rows = try decodeProperties().slidePropertiesRows
        let table = try OutputFormatter.render(rows, format: .table)
        let lines = table.split(separator: "\n").map(String.init)

        let header = try XCTUnwrap(lines.first)
        XCTAssertEqual(
            header.split(separator: " ").map(String.init),
            ["SLIDE", "SLIDE_ID", "SKIPPED", "BACKGROUND"])

        let second = try XCTUnwrap(lines.first { $0.contains("slide-2") })
        XCTAssertEqual(
            second.split(separator: " ").map(String.init), ["2", "slide-2", "yes", "#123456"])
        let first = try XCTUnwrap(lines.first { $0.contains("slide-1") })
        XCTAssertEqual(
            first.split(separator: " ").map(String.init), ["1", "slide-1", "no", "inherit"])
    }

    func testSlidePropertiesIdFormatPrintsSlideIds() throws {
        let rows = try decodeProperties().slidePropertiesRows
        let ids = try OutputFormatter.render(Array(rows.prefix(2)), format: .id)
        XCTAssertEqual(ids, "slide-1\nslide-2")
    }

    // MARK: - slideProperties (read)

    func testSlidePropertiesMasksTheRead() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(urlContains: "presentations/p-props?fields=", json: Self.propertiesJSON)

        let rows = try await client.slideProperties(presentationId: "p-props")

        let read = try XCTUnwrap(transport.requests(urlContains: "presentations/p-props?").first)
        XCTAssertEqual(read.method, "GET")
        let fields = URLComponents(url: read.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "fields" }?.value
        XCTAssertEqual(
            fields,
            "slides.objectId,slides.slideProperties.isSkipped,"
                + "slides.pageProperties.pageBackgroundFill")
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[1].skipped, true)
        // A read sends no write.
        XCTAssertTrue(transport.requests(urlContains: ":batchUpdate").isEmpty)
    }

    // MARK: - setSlideProperties

    func testSetSkippedSendsUpdateSlideProperties() async throws {
        let body = try await setAndCapture(skipped: true)
        XCTAssertEqual(
            body,
            #"{"requests":[{"updateSlideProperties":{"fields":"isSkipped","objectId":"slide-1","slideProperties":{"isSkipped":true}}}]}"#
        )
    }

    func testSetNotSkippedEncodesAnExplicitFalse() async throws {
        // An explicit false reaches the wire; it is not dropped like a nil.
        let body = try await setAndCapture(skipped: false)
        XCTAssertEqual(
            body,
            #"{"requests":[{"updateSlideProperties":{"fields":"isSkipped","objectId":"slide-1","slideProperties":{"isSkipped":false}}}]}"#
        )
    }

    func testSetBackgroundColorMasksOnlyTheSolidFillColor() async throws {
        let body = try await setAndCapture(background: .color(try OpaqueColor.parse("#FF0000")))
        XCTAssertEqual(
            body,
            #"{"requests":[{"updatePageProperties":{"fields":"pageBackgroundFill.solidFill.color","objectId":"slide-1","pageProperties":{"pageBackgroundFill":{"solidFill":{"color":{"rgbColor":{"blue":0,"green":0,"red":1}}}}}}}]}"#
        )
    }

    func testSetBackgroundThemeColor() async throws {
        let body = try await setAndCapture(background: .color(OpaqueColor(theme: .accent2)))
        XCTAssertEqual(
            body,
            #"{"requests":[{"updatePageProperties":{"fields":"pageBackgroundFill.solidFill.color","objectId":"slide-1","pageProperties":{"pageBackgroundFill":{"solidFill":{"color":{"themeColor":"ACCENT2"}}}}}}]}"#
        )
    }

    func testSetBackgroundImageSendsAStretchedPicture() async throws {
        let body = try await setAndCapture(
            background: .image(url: "https://example.com/bg.png"))
        XCTAssertEqual(
            body,
            #"{"requests":[{"updatePageProperties":{"fields":"pageBackgroundFill.stretchedPictureFill.contentUrl","objectId":"slide-1","pageProperties":{"pageBackgroundFill":{"stretchedPictureFill":{"contentUrl":"https:\/\/example.com\/bg.png"}}}}}]}"#
        )
    }

    func testSetBackgroundNoneSetsNotRendered() async throws {
        let body = try await setAndCapture(background: .noFill)
        XCTAssertEqual(
            body,
            #"{"requests":[{"updatePageProperties":{"fields":"pageBackgroundFill.propertyState","objectId":"slide-1","pageProperties":{"pageBackgroundFill":{"propertyState":"NOT_RENDERED"}}}}]}"#
        )
    }

    func testSetBackgroundInheritResetsTheWholeFill() async throws {
        // The whole fill is masked but left unset, which the API reads as a
        // reset: the slide reports INHERIT again.
        let body = try await setAndCapture(background: .inherit)
        XCTAssertEqual(
            body,
            #"{"requests":[{"updatePageProperties":{"fields":"pageBackgroundFill","objectId":"slide-1","pageProperties":{}}}]}"#
        )
    }

    func testSetSkippedAndBackgroundShareOneBatch() async throws {
        let body = try await setAndCapture(skipped: true, background: .inherit)
        XCTAssertEqual(
            body,
            #"{"requests":[{"updateSlideProperties":{"fields":"isSkipped","objectId":"slide-1","slideProperties":{"isSkipped":true}}},{"updatePageProperties":{"fields":"pageBackgroundFill","objectId":"slide-1","pageProperties":{}}}]}"#
        )
    }

    func testSetSlidePropertiesRequiresASettingAndSendsNothing() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)

        await assertInvalidArgument {
            try await client.setSlideProperties(presentationId: "p-props", slideId: "slide-1")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSetSlidePropertiesRejectsAnEmptyImageUrlAndSendsNothing() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)

        await assertInvalidArgument {
            try await client.setSlideProperties(
                presentationId: "p-props", slideId: "slide-1", skipped: true,
                background: .image(url: ""))
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSetSlidePropertiesPropagatesAGoogleError() async throws {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(
            urlContains: ":batchUpdate",
            json: #"{"error":{"code":400,"message":"The object (missing) could not be found.","status":"INVALID_ARGUMENT"}}"#,
            status: 400
        )

        await assertGoogleError(
            code: 400,
            status: "INVALID_ARGUMENT",
            message: "The object (missing) could not be found."
        ) {
            try await client.setSlideProperties(
                presentationId: "p-props", slideId: "missing", skipped: true)
        }
    }

    // MARK: - SlideBackground.parse

    func testSlideBackgroundParsesKeywordsCaseInsensitively() throws {
        XCTAssertEqual(try SlideBackground.parse("none"), .noFill)
        XCTAssertEqual(try SlideBackground.parse("NONE"), .noFill)
        XCTAssertEqual(try SlideBackground.parse("inherit"), .inherit)
        XCTAssertEqual(try SlideBackground.parse(" Inherit "), .inherit)
    }

    func testSlideBackgroundParsesColors() throws {
        XCTAssertEqual(
            try SlideBackground.parse("#F00"), .color(OpaqueColor(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(try SlideBackground.parse("accent1"), .color(OpaqueColor(theme: .accent1)))
    }

    func testSlideBackgroundRoundTripsTheValuesGetPrints() throws {
        // Every `background` a read prints (except `image`) parses back to the
        // background that writes the same value.
        let rows = try decodeProperties().slidePropertiesRows
        let parsed = try rows.filter { $0.background != "image" }
            .map { try SlideBackground.parse($0.background) }
        XCTAssertEqual(parsed, [
            .inherit,
            .color(OpaqueColor(red: 0x12 / 255, green: 0x34 / 255, blue: 0x56 / 255)),
            .color(OpaqueColor(theme: .accent2)),
            .noFill,
            .inherit,
            .color(OpaqueColor(red: 1, green: 0, blue: 0)),
        ])
    }

    func testSlideBackgroundRoundTripsAnUnderscoredThemeColor() throws {
        // A theme name with an underscore reads lowercased and parses back.
        let json = #"""
        {"slides":[{"objectId":"s1","pageProperties":{"pageBackgroundFill":{"solidFill":{
          "color":{"themeColor":"FOLLOWED_HYPERLINK"}}}}}]}
        """#
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(json.utf8))
        let value = try XCTUnwrap(presentation.slidePropertiesRows.first?.background)
        XCTAssertEqual(value, "followed_hyperlink")
        XCTAssertEqual(
            try SlideBackground.parse(value), .color(OpaqueColor(theme: .followedHyperlink)))
    }

    func testSlideBackgroundRejectsAnUnknownValue() {
        assertInvalidArgumentSync { _ = try SlideBackground.parse("blurple") }
        assertInvalidArgumentSync { _ = try SlideBackground.parse("") }
    }

    func testSlideBackgroundPointsImageAtThePictureFlag() {
        // `image` is a value get prints, but a picture is written from its URL.
        XCTAssertThrowsError(try SlideBackground.parse("Image")) { error in
            guard case GrahamError.invalidArgument(let message) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(message.contains("--background-image"), message)
        }
    }

    // MARK: - Helpers

    /// Calls `setSlideProperties` on `slide-1` against a stubbed empty reply
    /// and returns the one batch-update body it sent.
    private func setAndCapture(
        skipped: Bool? = nil,
        background: SlideBackground? = nil
    ) async throws -> String {
        let transport = StubTransport()
        let client = TestSupport.slidesClient(transport)
        transport.stub(urlContains: ":batchUpdate", json: #"{"presentationId":"p-props","replies":[{}]}"#)

        try await client.setSlideProperties(
            presentationId: "p-props", slideId: "slide-1",
            skipped: skipped, background: background)

        let requests = transport.requests(urlContains: ":batchUpdate")
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.path,
            "/v1/presentations/p-props:batchUpdate")
        return TestSupport.bodyString(request)
    }
}
