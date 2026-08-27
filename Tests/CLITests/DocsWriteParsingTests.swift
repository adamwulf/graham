import XCTest
import GrahamKit
@testable import graham

final class DocsWriteParsingTests: XCTestCase {
    func testDocsDoesNotRegisterACreateSubcommand() {
        // Document creation now lives under `graham drive create doc`, so the one
        // create path is under `drive`. `docs` no longer carries a create command.
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertFalse(names.contains("Create"), "docs should not list a Create subcommand: \(names)")
    }

    func testDocsInsertParsesTextAndIndex() throws {
        let command = try Docs.Insert.parse([
            "doc-1",
            "--text", "Hello, world",
            "--at", "5",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.text, "Hello, world")
        XCTAssertEqual(command.at, 5)
    }

    func testDocsInsertRequiresDocumentTextAndIndex() {
        XCTAssertThrowsError(try Docs.Insert.parse([]))
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1", "--text", "hi"]))
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1", "--at", "1"]))
    }

    func testDocsInsertParsesSegmentAndEnd() throws {
        let command = try Docs.Insert.parse([
            "doc-1", "--text", "hi", "--segment", "hdr-1", "--end",
        ])
        XCTAssertEqual(command.segment, "hdr-1")
        XCTAssertTrue(command.end)
        XCTAssertNil(command.at)
    }

    func testDocsInsertWithEndDoesNotRequireAnIndex() {
        // --end appends to the end of the segment, so --at is not required.
        XCTAssertNoThrow(try Docs.Insert.parse(["doc-1", "--text", "hi", "--end"]))
    }

    func testDocsInsertWithoutIndexOrEndIsRejectedAtParse() {
        // Neither --at nor --end: the validate() gate rejects it.
        XCTAssertThrowsError(try Docs.Insert.parse(["doc-1", "--text", "hi"]))
    }

    func testDocsInsertWithBothIndexAndEndIsRejectedAtParse() {
        // --at and --end conflict: --end takes no index. Exactly one is allowed.
        XCTAssertThrowsError(
            try Docs.Insert.parse(["doc-1", "--text", "hi", "--at", "1", "--end"])
        ) { error in
            let message = Docs.Insert.message(for: error)
            XCTAssertTrue(message.contains("not both"), "Expected a conflict message: \(message)")
        }
    }

    func testDocsInsertDefaultsSegmentToNilAndEndToFalse() throws {
        let command = try Docs.Insert.parse(["doc-1", "--text", "hi", "--at", "1"])
        XCTAssertNil(command.segment)
        XCTAssertFalse(command.end)
    }

    func testDocsDeleteParsesSegment() throws {
        let command = try Docs.Delete.parse([
            "doc-1", "--from", "0", "--to", "4", "--segment", "ftr-2",
        ])
        XCTAssertEqual(command.segment, "ftr-2")
    }

    func testDocsDeleteDefaultsSegmentToNil() throws {
        let command = try Docs.Delete.parse(["doc-1", "--from", "1", "--to", "4"])
        XCTAssertNil(command.segment)
    }

    func testDocsInsertParsesRequireRevision() throws {
        let command = try Docs.Insert.parse([
            "doc-1", "--text", "hi", "--at", "1", "--require-revision", "rev-7",
        ])
        XCTAssertEqual(command.requireRevision, "rev-7")
    }

    func testDocsInsertDefaultsRequireRevisionToNil() throws {
        let command = try Docs.Insert.parse(["doc-1", "--text", "hi", "--at", "1"])
        XCTAssertNil(command.requireRevision)
    }

    func testDocsDeleteParsesRequireRevision() throws {
        let command = try Docs.Delete.parse([
            "doc-1", "--from", "1", "--to", "4", "--require-revision", "rev-8",
        ])
        XCTAssertEqual(command.requireRevision, "rev-8")
    }

    func testDocsReplaceParsesRequireRevision() throws {
        let command = try Docs.Replace.parse([
            "doc-1", "--find", "a", "--replace", "b", "--require-revision", "rev-9",
        ])
        XCTAssertEqual(command.requireRevision, "rev-9")
    }

    func testDocsDeleteParsesRange() throws {
        let command = try Docs.Delete.parse([
            "doc-1",
            "--from", "3",
            "--to", "9",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.from, 3)
        XCTAssertEqual(command.to, 9)
    }

    func testDocsDeleteRequiresDocumentAndBothBounds() {
        XCTAssertThrowsError(try Docs.Delete.parse([]))
        XCTAssertThrowsError(try Docs.Delete.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Delete.parse(["doc-1", "--from", "3"]))
        XCTAssertThrowsError(try Docs.Delete.parse(["doc-1", "--to", "9"]))
    }

    func testDocsReplaceParsesFindReplaceAndMatchCase() throws {
        let command = try Docs.Replace.parse([
            "doc-1",
            "--find", "old",
            "--replace", "new",
            "--match-case",
        ])

        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.find, "old")
        XCTAssertEqual(command.replace, "new")
        XCTAssertTrue(command.matchCase)
    }

    func testDocsReplaceDefaultsMatchCaseOff() throws {
        let command = try Docs.Replace.parse([
            "doc-1", "--find", "old", "--replace", "new",
        ])
        XCTAssertFalse(command.matchCase)
    }

    func testDocsReplaceRequiresDocumentFindAndReplace() {
        XCTAssertThrowsError(try Docs.Replace.parse([]))
        XCTAssertThrowsError(try Docs.Replace.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Replace.parse(["doc-1", "--find", "old"]))
        XCTAssertThrowsError(try Docs.Replace.parse(["doc-1", "--replace", "new"]))
    }

    // MARK: - docs chip

    func testDocsRegistersChipSubcommand() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        XCTAssertTrue(names.contains("Chip"), "docs should list a Chip subcommand: \(names)")
        let chipNames = Docs.Chip.configuration.subcommands.map { String(describing: $0) }
        for expected in ["Person", "RichLink", "DateChip"] {
            XCTAssertTrue(chipNames.contains(expected), "chip should list \(expected): \(chipNames)")
        }
    }

    func testChipPersonParsesEmailNameAndTarget() throws {
        let command = try Docs.Chip.Person.parse([
            "doc-1", "--email", "a@b.com", "--name", "Ada", "--at", "5",
            "--segment", "h.0", "--tab-id", "t.0",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.email, "a@b.com")
        XCTAssertEqual(command.name, "Ada")
        XCTAssertEqual(command.at, 5)
        XCTAssertEqual(command.segment, "h.0")
        XCTAssertEqual(command.tabId, "t.0")
        XCTAssertFalse(command.end)
    }

    func testChipPersonRequiresEmailAndExactlyOneTarget() {
        // --email is required.
        XCTAssertThrowsError(try Docs.Chip.Person.parse(["doc-1", "--at", "1"]))
        // Neither --at nor --end.
        XCTAssertThrowsError(try Docs.Chip.Person.parse(["doc-1", "--email", "a@b.com"]))
        // Both --at and --end.
        XCTAssertThrowsError(try Docs.Chip.Person.parse([
            "doc-1", "--email", "a@b.com", "--at", "1", "--end",
        ]))
    }

    func testChipRichLinkParsesUriTitleAndMime() throws {
        let command = try Docs.Chip.RichLink.parse([
            "doc-1", "--uri", "https://drive.google.com/x",
            "--title", "Doc", "--mime-type", "application/pdf", "--end",
        ])
        XCTAssertEqual(command.uri, "https://drive.google.com/x")
        XCTAssertEqual(command.title, "Doc")
        XCTAssertEqual(command.mimeType, "application/pdf")
        XCTAssertTrue(command.end)
    }

    func testChipRichLinkRequiresUri() {
        XCTAssertThrowsError(try Docs.Chip.RichLink.parse(["doc-1", "--end"]))
    }

    func testChipDateParsesTimestampFormatsAndLocale() throws {
        let command = try Docs.Chip.DateChip.parse([
            "doc-1", "--timestamp", "2026-08-27T00:00:00Z",
            "--locale", "en-US", "--time-zone", "America/Chicago",
            "--date-format", "iso8601", "--time-format", "disabled", "--at", "2",
        ])
        XCTAssertEqual(command.timestamp, "2026-08-27T00:00:00Z")
        XCTAssertEqual(command.locale, "en-US")
        XCTAssertEqual(command.timeZone, "America/Chicago")
        XCTAssertEqual(command.dateFormat, .iso8601)
        XCTAssertEqual(command.timeFormat, .disabled)
        XCTAssertEqual(command.at, 2)
    }

    func testChipDateRequiresTimestampAndRejectsBadFormat() {
        XCTAssertThrowsError(try Docs.Chip.DateChip.parse(["doc-1", "--at", "1"]))
        XCTAssertThrowsError(try Docs.Chip.DateChip.parse([
            "doc-1", "--timestamp", "2026-08-27T00:00:00Z", "--date-format", "weekday", "--at", "1",
        ]))
    }
}
