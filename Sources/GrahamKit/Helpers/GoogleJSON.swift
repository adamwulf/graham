import Foundation

/// Shared JSON coders, so all output is stable and diffable.
public enum GoogleJSON {
    public static let decoder = JSONDecoder()

    /// Compact output with sorted keys. Used for `jsonl`.
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Readable output with sorted keys. Used for `json`.
    public static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
