import Foundation

/// A bounded rectangular range in A1 notation.
///
/// Rows and columns are exposed as zero-based, half-open bounds so the result
/// can be used directly in the Sheets API's ``GridRange`` model.
public struct A1Range: Sendable, Equatable {
    public let sheetName: String?
    public let startRowIndex: Int
    public let endRowIndex: Int
    public let startColumnIndex: Int
    public let endColumnIndex: Int

    public init(
        sheetName: String?,
        startRowIndex: Int,
        endRowIndex: Int,
        startColumnIndex: Int,
        endColumnIndex: Int
    ) {
        self.sheetName = sheetName
        self.startRowIndex = startRowIndex
        self.endRowIndex = endRowIndex
        self.startColumnIndex = startColumnIndex
        self.endColumnIndex = endColumnIndex
    }

    /// Parses a bounded A1 range such as `A1:B4`, `Sheet1!A1:B4`, or
    /// `'My Sheet'!A2:C10`.
    ///
    /// Whole-row and whole-column ranges are intentionally unsupported. A
    /// quote inside a quoted sheet name is also rejected; Sheets' doubled-
    /// quote escaping can be added when a caller needs it.
    public static func parse(_ input: String) throws -> A1Range {
        guard !input.isEmpty else {
            throw invalid(input, "the range is empty")
        }

        let sheetAndCells = try splitSheetName(from: input)
        let cellParts = sheetAndCells.cells.split(
            separator: ":", omittingEmptySubsequences: false)
        guard cellParts.count == 1 || cellParts.count == 2,
              cellParts.allSatisfy({ !$0.isEmpty })
        else {
            throw invalid(input, "expected one cell or two cells separated by ':'")
        }

        let start = try parseCell(cellParts[0], input: input)
        let end = try parseCell(cellParts.count == 2 ? cellParts[1] : cellParts[0], input: input)
        guard end.row >= start.row, end.column >= start.column else {
            throw invalid(input, "the end cell precedes the start cell")
        }
        guard end.row < Int.max, end.column < Int.max else {
            throw invalid(input, "a row or column is too large")
        }

        return A1Range(
            sheetName: sheetAndCells.sheetName,
            startRowIndex: start.row,
            endRowIndex: end.row + 1,
            startColumnIndex: start.column,
            endColumnIndex: end.column + 1
        )
    }

    private static func splitSheetName(from input: String) throws
        -> (sheetName: String?, cells: Substring)
    {
        if input.first == "'" {
            let quoteCount = input.reduce(into: 0) { count, character in
                if character == "'" { count += 1 }
            }
            guard quoteCount == 2, let delimiter = input.range(of: "'!") else {
                throw invalid(input, "the quoted sheet name is malformed or contains a quote")
            }
            let nameStart = input.index(after: input.startIndex)
            let name = input[nameStart..<delimiter.lowerBound]
            let cells = input[delimiter.upperBound...]
            guard !name.isEmpty, !cells.isEmpty else {
                throw invalid(input, "the sheet name and cell range must not be empty")
            }
            return (String(name), cells)
        }

        let parts = input.split(separator: "!", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard !parts[0].contains("'") else {
                throw invalid(input, "a quoted sheet name must be enclosed as 'Name'!")
            }
            return (nil, parts[0])
        case 2:
            guard !parts[0].isEmpty, !parts[1].isEmpty, !parts[0].contains("'") else {
                throw invalid(input, "the sheet name and cell range are malformed")
            }
            return (String(parts[0]), parts[1])
        default:
            throw invalid(input, "the range contains more than one '!' separator")
        }
    }

    private static func parseCell(_ cell: Substring, input: String) throws
        -> (row: Int, column: Int)
    {
        let letters = cell.prefix { character in
            character.isASCII && character.isLetter
        }
        let digits = cell.dropFirst(letters.count)
        guard !letters.isEmpty,
              !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber })
        else {
            throw invalid(input, "cell '\(cell)' is malformed or unbounded")
        }

        var column = 0
        for character in letters.uppercased() {
            guard let ascii = character.asciiValue else {
                throw invalid(input, "cell '\(cell)' has an invalid column")
            }
            let value = Int(ascii - 64)
            let multiplied = column.multipliedReportingOverflow(by: 26)
            let added = multiplied.partialValue.addingReportingOverflow(value)
            guard !multiplied.overflow, !added.overflow else {
                throw invalid(input, "cell '\(cell)' has a column that is too large")
            }
            column = added.partialValue
        }

        guard let oneBasedRow = Int(digits), oneBasedRow > 0 else {
            throw invalid(input, "cell '\(cell)' has an invalid row")
        }
        return (oneBasedRow - 1, column - 1)
    }

    private static func invalid(_ input: String, _ reason: String) -> GrahamError {
        GrahamError.invalidArgument("invalid A1 range \"\(input)\": \(reason)")
    }
}
