import Foundation

/// Loads values from `.env` files.
///
/// The search starts in one directory and moves up through the parent
/// directories until it finds the key or it gets to the filesystem root.
/// The nearest `.env` file that contains the key wins.
public enum DotEnv {
    /// Finds the value for `key` in the nearest `.env` file.
    ///
    /// - Parameters:
    ///   - key: The name of the variable, for example `GOOGLE_CLIENT_ID`.
    ///   - directory: The directory where the search starts. The default is
    ///     the current working directory.
    /// - Returns: The value, or `nil` if no `.env` file contains the key.
    public static func loadValue(forKey key: String, startingIn directory: URL? = nil) -> String? {
        var dir = (directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        while true {
            let envFileURL = dir.appendingPathComponent(".env")
            if let value = parseValue(forKey: key, in: envFileURL) {
                return value
            }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Parses one `.env` file and returns the value for `key`.
    ///
    /// Rules:
    /// - Blank lines and lines that start with `#` are ignored.
    /// - The line must start with `KEY=` exactly, so `KEY_EXTRA=` does not match `KEY`.
    /// - One pair of single or double quotes around the value is removed.
    /// - An empty value counts as "not found".
    static func parseValue(forKey key: String, in fileURL: URL) -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard line.hasPrefix("\(key)=") else { continue }
            var value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first,
               first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
