import Foundation

/// A Google Docs document. Only the fields needed for text extraction are
/// modeled; the decoder ignores all other fields. Every field is optional,
/// so a partial or new response shape does not sink the whole decode.
public struct Document: Codable, Sendable {
    public let documentId: String?
    public let title: String?
    public let body: DocumentBody?

    /// The document text, in reading order. Tables render one row per line
    /// with tab-separated cells.
    public var plainText: String {
        (body?.content ?? []).map(\.plainText).joined()
    }
}

public struct DocumentBody: Codable, Sendable {
    public let content: [StructuralElement]?
}

/// One block in a document body: a paragraph, a table, or another element
/// that this model does not read yet.
public struct StructuralElement: Codable, Sendable {
    public let paragraph: DocParagraph?
    public let table: DocTable?

    var plainText: String {
        if let paragraph {
            return (paragraph.elements ?? []).compactMap { $0.textRun?.content }.joined()
        }
        if let table {
            return table.plainText
        }
        return ""
    }
}

public struct DocParagraph: Codable, Sendable {
    public let elements: [DocParagraphElement]?
}

public struct DocParagraphElement: Codable, Sendable {
    public let textRun: DocTextRun?
}

public struct DocTextRun: Codable, Sendable {
    public let content: String?
}

public struct DocTable: Codable, Sendable {
    public let tableRows: [DocTableRow]?

    var plainText: String {
        let rows = (tableRows ?? []).map { row in
            (row.tableCells ?? [])
                .map { cell in
                    (cell.content ?? [])
                        .map(\.plainText)
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .joined(separator: "\t")
        }
        return rows.isEmpty ? "" : rows.joined(separator: "\n") + "\n"
    }
}

public struct DocTableRow: Codable, Sendable {
    public let tableCells: [DocTableCell]?
}

public struct DocTableCell: Codable, Sendable {
    public let content: [StructuralElement]?
}
