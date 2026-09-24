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
            "contentUrl": "https://lh7-rt.googleusercontent.com/picture",
            "size": {"width": {"magnitude": 272, "unit": "PT"}, "height": {"magnitude": 92, "unit": "PT"}}}}}
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

    func testSlidePropertiesRowsReadAnUnrecognizedFillAsEmpty() throws {
        // A rendered fill with neither a solid color nor a picture is not a
        // form `--background` can express, so it is empty rather than guessed.
        let json = #"{"slides":[{"objectId":"s1","pageProperties":{"pageBackgroundFill":{}}}]}"#
        let presentation = try GoogleJSON.decoder.decode(
            Presentation.self, from: Data(json.utf8))
        XCTAssertEqual(presentation.slidePropertiesRows.first?.background, "")
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
        // Every `background` a read prints (except `image`) parses back to a
        // background that writes the same value.
        let rows = try decodeProperties().slidePropertiesRows
        for value in rows.map(\.background) where value != "image" {
            XCTAssertNoThrow(try SlideBackground.parse(value), value)
        }
        XCTAssertEqual(
            try SlideBackground.parse("#123456"),
            .color(OpaqueColor(red: 0x12 / 255, green: 0x34 / 255, blue: 0x56 / 255)))
    }

    func testSlideBackgroundRejectsAnUnknownValue() {
        assertInvalidArgumentSync { _ = try SlideBackground.parse("image") }
        assertInvalidArgumentSync { _ = try SlideBackground.parse("blurple") }
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
