import Foundation

/// The output formats for list commands.
public enum OutputFormat: String, CaseIterable, Sendable {
    case table
    case json
    case jsonl
    case id
}

/// A model that list commands can render.
public protocol GrahamRow: Encodable {
    /// The column headers for `--format table`.
    static var tableColumns: [String] { get }
    /// One value for each column, in the same order.
    var tableValues: [String] { get }
    /// The value that `--format id` prints, one per line.
    var idValue: String { get }
}

/// Renders models in each ``OutputFormat``.
public enum OutputFormatter {
    public static func render<Row: GrahamRow>(_ items: [Row], format: OutputFormat) throws -> String {
        switch format {
        case .id:
            return items.map(\.idValue).joined(separator: "\n")
        case .json:
            let data = try GoogleJSON.prettyEncoder.encode(items)
            return String(data: data, encoding: .utf8) ?? "[]"
        case .jsonl:
            return try items
                .map { item in
                    let data = try GoogleJSON.encoder.encode(item)
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
                .joined(separator: "\n")
        case .table:
            return table(items)
        }
    }

    /// Renders aligned columns. The last column is not padded, so lines have
    /// no trailing whitespace.
    static func table<Row: GrahamRow>(_ items: [Row]) -> String {
        let columns = Row.tableColumns
        let rows = items.map(\.tableValues)
        var widths = columns.map(\.count)
        for row in rows {
            for (index, value) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], value.count)
            }
        }
        func line(_ values: [String]) -> String {
            values.enumerated()
                .map { index, value in
                    if index == values.count - 1 {
                        return value
                    }
                    return value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
                }
                .joined(separator: "  ")
        }
        return ([line(columns)] + rows.map(line)).joined(separator: "\n")
    }
}
