import Foundation

/// Parses rows of cell values from the input forms `graham sheets set` accepts
/// beyond the legacy comma-separated `--row`. Both forms let a cell contain a
/// comma, which the comma-split form cannot, so a `values | set` round trip
/// keeps commas intact.
public enum SheetsRowInput {
    /// Parses rows from a JSON array of arrays of strings, for example
    /// `[["Label","Value"],["A, B","10"]]`.
    public static func fromJSON(_ json: String) throws -> [[String]] {
        let rows: [[String]]
        do {
            rows = try JSONDecoder().decode([[String]].self, from: Data(json.utf8))
        } catch {
            throw GrahamError.invalidArgument(
                "the rows must be a JSON array of arrays of strings")
        }
        try validate(rows)
        return rows
    }

    /// Parses rows from the legacy comma-separated `--row` form: each element is
    /// one row, split on commas with no escaping (every comma starts the next
    /// cell). This is the form `--json-rows` and `--tsv` exist to escape.
    public static func fromCommaRows(_ rows: [String]) throws -> [[String]] {
        let parsed = rows.map { row in
            row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        try validate(parsed)
        return parsed
    }

    /// Parses rows from tab-separated text: rows split on newlines and cells on
    /// tabs. A trailing newline and any blank lines are dropped, so piping a
    /// `graham sheets values` read straight back in round-trips.
    public static func fromTSV(_ tsv: String) throws -> [[String]] {
        let lines = tsv
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
        let rows = lines.map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
        try validate(rows)
        return rows
    }

    private static func validate(_ rows: [[String]]) throws {
        guard !rows.isEmpty else {
            throw GrahamError.invalidArgument("provide at least one row to write")
        }
        guard !rows.contains(where: \.isEmpty) else {
            throw GrahamError.invalidArgument("each row must contain at least one cell")
        }
    }
}
