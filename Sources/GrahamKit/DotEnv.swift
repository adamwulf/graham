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

    /// Finds the nearest existing `.env` file.
    ///
    /// The search starts in one directory and moves up through the parent
    /// directories until it finds a `.env` file or it gets to the filesystem
    /// root.
    ///
    /// - Parameter directory: The directory where the search starts. The
    ///   default is the current working directory.
    /// - Returns: The URL of the nearest existing `.env` file, or `nil` if no
    ///   `.env` file exists in the directory or any parent.
    public static func findNearestFileURL(startingIn directory: URL? = nil) -> URL? {
        var dir = (directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        while true {
            let envFileURL = dir.appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: envFileURL.path) {
                return envFileURL
            }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Writes `value` for `key` into the nearest existing `.env` file.
    ///
    /// The search for the file starts in `directory` and moves up through the
    /// parent directories; the nearest existing `.env` file wins. If no `.env`
    /// file exists, this creates one in `directory`.
    ///
    /// If the file already has a line for `key`, this replaces that line and
    /// removes any later duplicate lines for the same key, so the reader
    /// (which takes the first match) always sees the new value. If the file
    /// has no line for `key`, this appends a new line. All other lines,
    /// including comments, stay unchanged. The file permissions of an
    /// existing file are kept.
    ///
    /// - Parameters:
    ///   - value: The value to write.
    ///   - key: The name of the variable, for example `GOOGLE_REFRESH_TOKEN`.
    ///   - directory: The directory where the search starts. The default is
    ///     the current working directory.
    /// - Returns: The URL of the `.env` file that was written.
    @discardableResult
    public static func setValue(
        _ value: String,
        forKey key: String,
        startingIn directory: URL? = nil
    ) throws -> URL {
        let startDir = (directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        let fileURL = findNearestFileURL(startingIn: startDir)
            ?? startDir.appendingPathComponent(".env")

        let fileExisted = FileManager.default.fileExists(atPath: fileURL.path)
        let priorPermissions = fileExisted
            ? (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.posixPermissions] as? NSNumber
            : nil

        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var lines = existing.isEmpty ? [] : existing.components(separatedBy: "\n")
        // Drop the trailing empty element that a final newline produces, so we
        // control the trailing newline ourselves.
        if lines.last == "" { lines.removeLast() }

        let newLine = "\(key)=\(value)"
        var didReplace = false
        var result: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=") {
                if !didReplace {
                    result.append(newLine)
                    didReplace = true
                }
                // A duplicate line for the same key is dropped.
            } else {
                result.append(line)
            }
        }
        if !didReplace { result.append(newLine) }

        let output = result.joined(separator: "\n") + "\n"
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
        if let priorPermissions {
            try? FileManager.default.setAttributes(
                [.posixPermissions: priorPermissions], ofItemAtPath: fileURL.path)
        }
        return fileURL
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
