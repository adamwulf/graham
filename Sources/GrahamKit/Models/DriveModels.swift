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
        case "application/vnd.google-apps.drive": return "drive"
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

/// The request body for `files.create`: the metadata of a new, empty file.
///
/// Only the name and the MIME type are sent; Drive fills in everything else.
/// Encoding through ``GoogleJSON`` escapes the name safely, so a name with a
/// quote, a backslash, or a newline never breaks the JSON.
public struct DriveFileCreateRequest: Codable, Sendable, Equatable {
    public let name: String
    public let mimeType: String

    public init(name: String, mimeType: String) {
        self.name = name
        self.mimeType = mimeType
    }
}

/// The request body for `files.copy`: an optional new name for the copy.
///
/// When `name` is nil the key is omitted entirely, so Drive keeps its default
/// naming ("Copy of <original>"). The name is carried in the body, never in
/// the URL, so any character encodes safely.
public struct DriveFileCopyRequest: Codable, Sendable, Equatable {
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

/// One shared drive the user can see.
///
/// `id` is the only invariant; `name` is optional so the model decodes even
/// when the `fields` parameter omits it.
public struct SharedDrive: Codable, Sendable, Equatable {
    /// The synthetic MIME graham uses to label a shared drive in a unified
    /// listing next to files. Google does not send this; graham assigns it so
    /// a shared drive shows a sensible "drive" type in the table.
    public static let mimeType = "application/vnd.google-apps.drive"

    public let id: String
    public let name: String?

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }

    /// Renders this shared drive as a ``DriveFile`` row, using the synthetic
    /// drive MIME so it lists alongside files with a sensible type label.
    public func asDriveFile() -> DriveFile {
        DriveFile(id: id, name: name ?? "", mimeType: Self.mimeType)
    }
}

/// One page of a shared-drive listing.
public struct SharedDriveList: Codable, Sendable {
    public let nextPageToken: String?
    public let drives: [SharedDrive]?
}

extension DriveFile: GrahamRow {
    public static var tableColumns: [String] { ["ID", "TYPE", "MODIFIED", "NAME"] }

    public var tableValues: [String] {
        [id, shortType, modifiedTime ?? "", name]
    }

    public var idValue: String { id }
}
