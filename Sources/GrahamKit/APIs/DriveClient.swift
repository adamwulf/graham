import Foundation

/// The high-level client for the Drive v3 API.
///
/// Pagination lives here, and only here. The `limit` parameter is a client
/// side guard, so a broad query does not pull a full Drive by accident.
public struct DriveClient: Sendable {
    public static let baseURL = "https://www.googleapis.com/drive/v3"
    static let fileFields = "id,name,mimeType,modifiedTime,size,webViewLink,parents"

    private let api: GoogleAPI

    public init(api: GoogleAPI) {
        self.api = api
    }

    /// Lists files, optionally inside one folder or shared drive, and
    /// optionally filtered by type or a user query.
    ///
    /// The `q` is built by ANDing the clauses that apply: the parent
    /// (`'<parentID>' in parents`), the type MIME (`mimeType='<mime>'`), the
    /// user `query` (wrapped in parentheses), and always `trashed = false`.
    /// The request always searches across shared drives.
    ///
    /// - Parameters:
    ///   - parentID: List only the items whose parent is this folder or shared
    ///     drive. When `nil`, the search spans all drives.
    ///   - type: A file-type filter. `.all` adds no MIME clause.
    ///   - query: A Drive search query, for example `name contains 'report'`.
    ///     See https://developers.google.com/drive/api/guides/search-files
    ///   - orderBy: A sort order, for example `modifiedTime desc`.
    ///   - limit: The maximum number of files to return.
    public func list(
        parentID: String? = nil,
        type: DriveFileType = .all,
        query: String? = nil,
        orderBy: String? = nil,
        limit: Int = 100
    ) async throws -> [DriveFile] {
        let q = Self.buildQuery(parentID: parentID, type: type, query: query)
        var files: [DriveFile] = []
        var pageToken: String?
        repeat {
            let pageSize = min(100, max(1, limit - files.count))
            let url = try GoogleURL.build("\(Self.baseURL)/files", query: [
                ("q", q),
                ("orderBy", orderBy),
                ("pageSize", String(pageSize)),
                ("pageToken", pageToken),
                ("corpora", "allDrives"),
                ("includeItemsFromAllDrives", "true"),
                ("supportsAllDrives", "true"),
                ("fields", "nextPageToken,files(\(Self.fileFields))"),
            ])
            let page = try await api.getJSON(DriveFileList.self, from: url)
            for file in page.files ?? [] {
                files.append(file)
                if files.count >= limit {
                    return files
                }
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return files
    }

    /// Lists the shared drives the user can see.
    public func drives(limit: Int = 100) async throws -> [SharedDrive] {
        var drives: [SharedDrive] = []
        var pageToken: String?
        repeat {
            let pageSize = min(100, max(1, limit - drives.count))
            let url = try GoogleURL.build("\(Self.baseURL)/drives", query: [
                ("pageSize", String(pageSize)),
                ("pageToken", pageToken),
                ("fields", "nextPageToken,drives(id,name)"),
            ])
            let page = try await api.getJSON(SharedDriveList.self, from: url)
            for drive in page.drives ?? [] {
                drives.append(drive)
                if drives.count >= limit {
                    return drives
                }
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return drives
    }

    /// Gets the "My Drive" root as a ``DriveFile``.
    public func root() async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/root",
            query: [("fields", "id,name,mimeType")]
        )
        return try await api.getJSON(DriveFile.self, from: url)
    }

    /// The top-level roots as one list: "My Drive" first, then every shared
    /// drive, each mapped to a ``DriveFile`` row (with the synthetic drive MIME)
    /// so the two render together. The `limit` counts My Drive, so the shared
    /// drives fill the remaining slots.
    public func roots(limit: Int = 100) async throws -> [DriveFile] {
        guard limit > 0 else { return [] }
        var rows: [DriveFile] = [try await root()]
        if rows.count < limit {
            let drives = try await drives(limit: limit - rows.count)
            rows.append(contentsOf: drives.map { $0.asDriveFile() })
        }
        return rows
    }

    /// Backs the `drive list` command. The routing:
    /// - `id` given: the contents of that folder or shared drive.
    /// - no `id`, no `query`, and `type` is `.all` or `.folders`: the top-level
    ///   roots (My Drive plus the shared drives).
    /// - otherwise: a global search across all drives.
    ///
    /// An empty `query` string is treated as no query.
    public func browse(
        id: String? = nil,
        type: DriveFileType = .all,
        query: String? = nil,
        orderBy: String? = nil,
        limit: Int = 100
    ) async throws -> [DriveFile] {
        let query = (query?.isEmpty ?? true) ? nil : query
        if let id {
            return try await list(
                parentID: id, type: type, query: query, orderBy: orderBy, limit: limit)
        }
        if query == nil, type == .all || type == .folders {
            return try await roots(limit: limit)
        }
        return try await list(type: type, query: query, orderBy: orderBy, limit: limit)
    }

    /// Builds the Drive `q` string. `trashed = false` is always present, so a
    /// non-empty query is always returned.
    ///
    /// The parent id is placed inside single quotes, so any `'` or `\` in it is
    /// backslash-escaped to keep the query well-formed.
    static func buildQuery(parentID: String?, type: DriveFileType, query: String?) -> String {
        var clauses: [String] = []
        if let parentID {
            clauses.append("'\(escapeQueryValue(parentID))' in parents")
        }
        if let mime = type.mimeType {
            clauses.append("mimeType='\(escapeQueryValue(mime))'")
        }
        if let query, !query.isEmpty {
            clauses.append("(\(query))")
        }
        clauses.append("trashed = false")
        return clauses.joined(separator: " and ")
    }

    /// Escapes a value that goes inside single quotes in a Drive `q` clause.
    /// Backslashes are escaped first, then single quotes, per Google's query
    /// grammar.
    static func escapeQueryValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    /// Creates a new, empty Google Doc, Sheet, or Slides file, via
    /// `files.create`. The file lands in "My Drive" with the given name, and
    /// its type is set by the MIME on ``DriveCreateType``. Returns the created
    /// file's metadata (the same `fields` as ``file(id:)``).
    ///
    /// The name is carried in a JSON request body, not in the URL, so it is
    /// encoded safely no matter what characters it holds.
    public func create(name: String, type: DriveCreateType) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files",
            query: [("fields", Self.fileFields)]
        )
        let body = DriveFileCreateRequest(name: name, mimeType: type.mimeType)
        return try await api.sendJSON(DriveFile.self, method: "POST", url: url, body: body)
    }

    /// Gets the metadata of one file.
    public func file(id: String) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(id))",
            query: [("fields", Self.fileFields)]
        )
        return try await api.getJSON(DriveFile.self, from: url)
    }

    /// Exports a Google Workspace file (Doc, Sheet, Slides) to another format,
    /// for example `text/plain` or `application/pdf`.
    public func export(id: String, mimeType: String) async throws -> Data {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(id))/export",
            query: [("mimeType", mimeType)]
        )
        return try await api.getData(from: url)
    }

    /// Downloads the content of a binary file.
    public func download(id: String) async throws -> Data {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(id))",
            query: [("alt", "media")]
        )
        return try await api.getData(from: url)
    }
}
