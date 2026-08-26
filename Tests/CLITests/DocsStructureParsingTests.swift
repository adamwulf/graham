import XCTest
import GrahamKit
@testable import graham

/// Argument-only coverage for the Phase 6 `docs page-break`, `docs image`,
/// `docs object`, and `docs section-break` commands. These tests parse arguments
/// and never touch the network; the client behavior is covered by
/// `DocsStructureWriteTests`. Mirrors `DocsWriteParsingTests` and
/// `DocsTableParsingTests`.
final class DocsStructureParsingTests: XCTestCase {
    func testDocsRegistersTheStructureSubcommands() {
        let names = Docs.configuration.subcommands.map { String(describing: $0) }
        for expected in ["PageBreak", "Image", "Object", "SectionBreak"] {
            XCTAssertTrue(names.contains(expected), "docs should list \(expected): \(names)")
        }
    }

    // MARK: - page-break

    func testPageBreakParsesAt() throws {
        let command = try Docs.PageBreak.parse(["doc-1", "--at", "5"])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.at, 5)
        XCTAssertFalse(command.end)
    }

    func testPageBreakParsesEndAndRequireRevision() throws {
        let command = try Docs.PageBreak.parse([
            "doc-1", "--end", "--require-revision", "rev-1",
        ])
        XCTAssertTrue(command.end)
        XCTAssertNil(command.at)
        XCTAssertEqual(command.requireRevision, "rev-1")
    }

    func testPageBreakRejectsBothAtAndEndAndNeither() {
        XCTAssertThrowsError(try Docs.PageBreak.parse(["doc-1", "--at", "5", "--end"]))
        XCTAssertThrowsError(try Docs.PageBreak.parse(["doc-1"]))
    }

    // MARK: - image insert

    func testDocsImageListsInsertAndReplace() {
        let names = Docs.Image.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["insert", "replace"])
    }

    func testImageInsertParsesEveryOption() throws {
        let command = try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png", "--at", "5",
            "--width", "120", "--height", "80", "--segment", "hdr-1",
            "--require-revision", "rev-2",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.uri, "https://cdn.example.com/pic.png")
        XCTAssertEqual(command.at, 5)
        XCTAssertFalse(command.end)
        XCTAssertEqual(command.width, 120)
        XCTAssertEqual(command.height, 80)
        XCTAssertEqual(command.segment, "hdr-1")
        XCTAssertEqual(command.requireRevision, "rev-2")
    }

    func testImageInsertParsesEndWithoutAnIndex() throws {
        let command = try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png", "--end",
        ])
        XCTAssertTrue(command.end)
        XCTAssertNil(command.at)
    }

    func testImageInsertRejectsBadCombinations() {
        // Missing --uri.
        XCTAssertThrowsError(try Docs.Image.Insert.parse(["doc-1", "--at", "5"]))
        // Neither --at nor --end.
        XCTAssertThrowsError(try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png",
        ]))
        // Both --at and --end.
        XCTAssertThrowsError(try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png", "--at", "5", "--end",
        ]))
        // Empty --uri.
        XCTAssertThrowsError(try Docs.Image.Insert.parse([
            "doc-1", "--uri", "", "--at", "5",
        ]))
        // Non-positive dimensions.
        XCTAssertThrowsError(try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png", "--at", "5", "--width", "0",
        ]))
        XCTAssertThrowsError(try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png", "--at", "5", "--height", "-3",
        ]))
    }

    func testImageInsertDefaultsOptionalsToNil() throws {
        let command = try Docs.Image.Insert.parse([
            "doc-1", "--uri", "https://cdn.example.com/pic.png", "--at", "1",
        ])
        XCTAssertNil(command.width)
        XCTAssertNil(command.height)
        XCTAssertNil(command.segment)
        XCTAssertNil(command.requireRevision)
    }

    // MARK: - image replace

    func testImageReplaceParsesArguments() throws {
        let command = try Docs.Image.Replace.parse([
            "doc-1", "img-1", "--uri", "https://cdn.example.com/new.png",
            "--require-revision", "rev-3",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.imageObjectID, "img-1")
        XCTAssertEqual(command.uri, "https://cdn.example.com/new.png")
        XCTAssertEqual(command.requireRevision, "rev-3")
    }

    func testImageReplaceRequiresObjectIdAndUri() {
        XCTAssertThrowsError(try Docs.Image.Replace.parse([]))
        XCTAssertThrowsError(try Docs.Image.Replace.parse(["doc-1"]))
        XCTAssertThrowsError(try Docs.Image.Replace.parse(["doc-1", "img-1"]))
        // Empty object id.
        XCTAssertThrowsError(try Docs.Image.Replace.parse([
            "doc-1", "", "--uri", "https://cdn.example.com/new.png",
        ]))
        // Empty uri.
        XCTAssertThrowsError(try Docs.Image.Replace.parse(["doc-1", "img-1", "--uri", ""]))
    }

    // MARK: - object delete

    func testDocsObjectListsDelete() {
        let names = Docs.Object.configuration.subcommands.compactMap {
            $0.configuration.commandName ?? "\($0)".lowercased()
        }
        XCTAssertEqual(names, ["delete"])
    }

    func testObjectDeleteParsesArguments() throws {
        let command = try Docs.Object.Delete.parse([
            "doc-1", "obj-1", "--require-revision", "rev-4",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.objectID, "obj-1")
        XCTAssertEqual(command.requireRevision, "rev-4")
    }

    func testObjectDeleteRequiresObjectId() {
        XCTAssertThrowsError(try Docs.Object.Delete.parse([]))
        XCTAssertThrowsError(try Docs.Object.Delete.parse(["doc-1"]))
        // Empty object id.
        XCTAssertThrowsError(try Docs.Object.Delete.parse(["doc-1", ""]))
    }

    // MARK: - section-break

    func testSectionBreakParsesTypeAndAt() throws {
        let command = try Docs.SectionBreak.parse([
            "doc-1", "--type", "continuous", "--at", "3",
        ])
        XCTAssertEqual(command.documentID, "doc-1")
        XCTAssertEqual(command.type, .continuous)
        XCTAssertEqual(command.at, 3)
        XCTAssertFalse(command.end)
    }

    func testSectionBreakParsesNextPageAndEnd() throws {
        let command = try Docs.SectionBreak.parse([
            "doc-1", "--type", "next-page", "--end",
        ])
        XCTAssertEqual(command.type, .nextPage)
        XCTAssertTrue(command.end)
        XCTAssertNil(command.at)
    }

    func testSectionBreakRequiresType() {
        XCTAssertThrowsError(try Docs.SectionBreak.parse(["doc-1", "--at", "3"]))
        // An unknown type is rejected by the argument enum at parse time.
        XCTAssertThrowsError(try Docs.SectionBreak.parse([
            "doc-1", "--type", "sideways", "--at", "3",
        ]))
    }

    func testSectionBreakRejectsBothAtAndEndAndNeither() {
        XCTAssertThrowsError(try Docs.SectionBreak.parse([
            "doc-1", "--type", "continuous", "--at", "3", "--end",
        ]))
        XCTAssertThrowsError(try Docs.SectionBreak.parse(["doc-1", "--type", "continuous"]))
    }

    // MARK: - argument enum mapping

    func testSectionTypeArgumentMapsToTheWireValue() {
        XCTAssertEqual(DocsSectionTypeArgument.continuous.sectionType, "CONTINUOUS")
        XCTAssertEqual(DocsSectionTypeArgument.nextPage.sectionType, "NEXT_PAGE")
    }
}
