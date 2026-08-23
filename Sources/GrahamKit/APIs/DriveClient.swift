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

    /// Lists files.
    ///
    /// - Parameters:
    ///   - query: A Drive search query, for example `name contains 'report'`.
    ///     See https://developers.google.com/drive/api/guides/search-files
    ///   - orderBy: A sort order, for example `modifiedTime desc`.
    ///   - limit: The maximum number of files to return.
    public func list(query: String? = nil, orderBy: String? = nil, limit: Int = 100) async throws -> [DriveFile] {
        var files: [DriveFile] = []
        var pageToken: String?
        repeat {
            let pageSize = min(100, max(1, limit - files.count))
            let url = try GoogleURL.build("\(Self.baseURL)/files", query: [
                ("q", query),
                ("orderBy", orderBy),
                ("pageSize", String(pageSize)),
                ("pageToken", pageToken),
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
