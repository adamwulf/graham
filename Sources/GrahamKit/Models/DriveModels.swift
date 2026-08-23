import Foundation

/// One file in Google Drive.
///
/// All fields except `id` and `name` are optional, because the `fields`
/// parameter controls which fields the API returns.
public struct DriveFile: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let mimeType: String?
    public let modifiedTime: String?
    public let size: String?
    public let webViewLink: String?
    public let parents: [String]?

    public init(
        id: String,
        name: String,
        mimeType: String? = nil,
        modifiedTime: String? = nil,
        size: String? = nil,
        webViewLink: String? = nil,
        parents: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.size = size
        self.webViewLink = webViewLink
        self.parents = parents
    }

    /// A short type label for tables, for example "doc" or "sheet".
    public var shortType: String {
        switch mimeType {
        case "application/vnd.google-apps.document": return "doc"
        case "application/vnd.google-apps.spreadsheet": return "sheet"
        case "application/vnd.google-apps.presentation": return "slides"
        case "application/vnd.google-apps.folder": return "folder"
        case "application/vnd.google-apps.shortcut": return "shortcut"
        case let mime?: return mime.split(separator: "/").last.map(String.init) ?? mime
        case nil: return ""
        }
    }
}

/// One page of a Drive file listing.
public struct DriveFileList: Codable, Sendable {
    public let nextPageToken: String?
    public let files: [DriveFile]?
}

extension DriveFile: GrahamRow {
    public static var tableColumns: [String] { ["ID", "TYPE", "MODIFIED", "NAME"] }

    public var tableValues: [String] {
        [id, shortType, modifiedTime ?? "", name]
    }

    public var idValue: String { id }
}
