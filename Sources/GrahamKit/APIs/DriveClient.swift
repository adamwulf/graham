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

    /// Creates a new, empty Google Doc, Sheet, Slides file, or folder via
    /// `files.create`. With no `parent`, the file lands in "My Drive". When a
    /// parent id is supplied, Drive places the file directly in that folder.
    /// Returns the created file's metadata (the same `fields` as ``file(id:)``).
    ///
    /// The name is carried in a JSON request body, not in the URL, so it is
    /// encoded safely no matter what characters it holds.
    public func create(
        name: String,
        type: DriveCreateType,
        parent: String? = nil
    ) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files",
            query: [("fields", Self.fileFields), ("supportsAllDrives", "true")]
        )
        let body = DriveFileCreateRequest(
            name: name,
            mimeType: type.mimeType,
            parents: parent.map { [$0] }
        )
        return try await api.sendJSON(DriveFile.self, method: "POST", url: url, body: body)
    }

    /// Copies a file via `files.copy`. With a `name`, the copy takes that name;
    /// without one, Drive names it "Copy of <original>". An optional `parent`
    /// places the copy in that folder. Returns the new file, whose `id` is the
    /// value the `copy` command prints.
    ///
    /// The optional name travels in a JSON request body, not in the URL, so it
    /// is encoded safely no matter what characters it holds. The request spans
    /// shared drives.
    public func copy(
        fileId: String,
        name: String? = nil,
        parent: String? = nil
    ) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(fileId))/copy",
            query: [("supportsAllDrives", "true")]
        )
        let body = DriveFileCopyRequest(name: name, parents: parent.map { [$0] })
        return try await api.sendJSON(DriveFile.self, method: "POST", url: url, body: body)
    }

    /// Moves a file to the trash via `files.update` (a PATCH that sets
    /// `trashed = true`). Returns the updated file metadata. Trashing is
    /// reversible from the Drive UI. The request spans shared drives.
    ///
    /// The `trashed` flag travels in a JSON request body, not in the URL.
    public func trash(fileId: String) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(fileId))",
            query: [("supportsAllDrives", "true")]
        )
        let body = DriveTrashRequest(trashed: true)
        return try await api.sendJSON(DriveFile.self, method: "PATCH", url: url, body: body)
    }

    /// Restores a file from the trash via `files.update` (a PATCH that sets
    /// `trashed = false`), the inverse of ``trash(fileId:)``. Returns the updated
    /// file metadata. The request spans shared drives.
    ///
    /// The `trashed` flag travels in a JSON request body, not in the URL.
    public func untrash(fileId: String) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(fileId))",
            query: [("supportsAllDrives", "true")]
        )
        let body = DriveTrashRequest(trashed: false)
        return try await api.sendJSON(DriveFile.self, method: "PATCH", url: url, body: body)
    }

    /// Renames a file via `files.update`. Returns the updated file metadata.
    /// The new name travels in a JSON body, so any character encodes safely.
    public func rename(fileId: String, name: String) async throws -> DriveFile {
        try await update(fileId: fileId, request: DriveUpdateRequest(name: name))
    }

    /// Stars or unstars a file (Drive's "favorite") via `files.update`.
    /// Returns the updated file metadata.
    public func setStarred(fileId: String, starred: Bool) async throws -> DriveFile {
        try await update(fileId: fileId, request: DriveUpdateRequest(starred: starred))
    }

    /// Moves a file into the folder `parent` via `files.update`. Drive reparents
    /// by adding one parent and removing the others, so this first reads the
    /// file's current parents, then adds `parent` and removes the rest (never
    /// `parent` itself, so an add/remove of the same id cannot conflict).
    /// Returns the updated file metadata. The parent ids travel in the URL as
    /// `addParents`/`removeParents`, which Drive does not accept in the body;
    /// the body is empty. The request spans shared drives.
    public func move(fileId: String, to parent: String) async throws -> DriveFile {
        let current = try await file(id: fileId)
        let toRemove = current.parents?.filter { $0 != parent }
        return try await update(
            fileId: fileId,
            request: DriveUpdateRequest(),
            addParents: [parent],
            removeParents: toRemove
        )
    }

    /// The shared `files.update` PATCH behind ``rename(fileId:name:)``,
    /// ``setStarred(fileId:starred:)``, and ``move(fileId:to:)``. Metadata fields
    /// (name, starred) travel in the JSON `request` body; a parent move travels
    /// in the URL as `addParents`/`removeParents`. The request asks for the full
    /// field set and spans shared drives.
    private func update(
        fileId: String,
        request: DriveUpdateRequest,
        addParents: [String]? = nil,
        removeParents: [String]? = nil
    ) async throws -> DriveFile {
        var query: [(String, String)] = [
            ("fields", Self.fileFields),
            ("supportsAllDrives", "true"),
        ]
        if let addParents, !addParents.isEmpty {
            query.append(("addParents", addParents.joined(separator: ",")))
        }
        if let removeParents, !removeParents.isEmpty {
            query.append(("removeParents", removeParents.joined(separator: ",")))
        }
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(fileId))",
            query: query
        )
        return try await api.sendJSON(DriveFile.self, method: "PATCH", url: url, body: request)
    }

    /// Creates a shortcut that points to `targetId` via `files.create`. Returns
    /// the new shortcut file, whose own id differs from the target's. The name
    /// and target travel in a JSON body, never in the URL; `parent` places the
    /// shortcut in a folder. The request spans shared drives.
    public func createShortcut(
        name: String,
        targetId: String,
        parent: String? = nil
    ) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files",
            query: [("fields", Self.fileFields), ("supportsAllDrives", "true")]
        )
        let body = DriveShortcutCreateRequest(
            name: name, targetId: targetId, parents: parent.map { [$0] })
        return try await api.sendJSON(DriveFile.self, method: "POST", url: url, body: body)
    }

    /// Permanently deletes a file via `files.delete` (an HTTP DELETE that
    /// replies with 204 and an empty body). This BYPASSES the trash: the file
    /// is not recoverable from the Drive UI, unlike ``trash(fileId:)``. The
    /// request spans shared drives.
    public func delete(fileId: String) async throws {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(fileId))",
            query: [("supportsAllDrives", "true")]
        )
        try await api.sendNoContent(method: "DELETE", url: url)
    }

    /// Gets the metadata of one file. Spans shared drives, so a shared-drive
    /// file resolves instead of 404-ing (`files.get` scopes to My Drive without
    /// `supportsAllDrives`). `move` relies on this to read a file's parents.
    public func file(id: String) async throws -> DriveFile {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(id))",
            query: [("fields", Self.fileFields), ("supportsAllDrives", "true")]
        )
        return try await api.getJSON(DriveFile.self, from: url)
    }

    /// Exports a Google Workspace file (Doc, Sheet, Slides) to another format,
    /// for example `text/plain` or `application/pdf`. Spans shared drives.
    public func export(id: String, mimeType: String) async throws -> Data {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(id))/export",
            query: [("mimeType", mimeType), ("supportsAllDrives", "true")]
        )
        return try await api.getData(from: url)
    }

    /// Downloads the content of a binary file. Spans shared drives (this is
    /// `files.get` with `alt=media`, which needs `supportsAllDrives` to reach a
    /// shared-drive file).
    public func download(id: String) async throws -> Data {
        let url = try GoogleURL.build(
            "\(Self.baseURL)/files/\(GoogleURL.escapePathComponent(id))",
            query: [("alt", "media"), ("supportsAllDrives", "true")]
        )
        return try await api.getData(from: url)
    }
}
