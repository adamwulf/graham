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
/// The name and MIME type are always sent. `parents` is included when the
/// caller wants the new file placed in a particular folder.
/// Encoding through ``GoogleJSON`` escapes the name safely, so a name with a
/// quote, a backslash, or a newline never breaks the JSON.
public struct DriveFileCreateRequest: Codable, Sendable, Equatable {
    public let name: String
    public let mimeType: String
    public let parents: [String]?

    public init(name: String, mimeType: String, parents: [String]? = nil) {
        self.name = name
        self.mimeType = mimeType
        self.parents = parents
    }
}

/// The request body for `files.copy`: an optional new name and destination.
///
/// When `name` is nil the key is omitted entirely, so Drive keeps its default
/// naming ("Copy of <original>"). A one-item `parents` array keeps a copy in a
/// caller-selected folder. Both are carried in the body, never in the URL.
public struct DriveFileCopyRequest: Codable, Sendable, Equatable {
    public let name: String?
    public let parents: [String]?

    public init(name: String? = nil, parents: [String]? = nil) {
        self.name = name
        self.parents = parents
    }
}

/// The request body for trashing or restoring a file via `files.update`: sets
/// `trashed`.
///
/// Trashing is a metadata update, so it is a PATCH with this one field. Setting
/// `trashed = true` moves the file to the trash, which the Drive UI can undo;
/// setting it `false` restores the file from the trash.
public struct DriveTrashRequest: Codable, Sendable, Equatable {
    public let trashed: Bool

    public init(trashed: Bool) {
        self.trashed = trashed
    }
}

/// The request body for a metadata update via `files.update` (a PATCH).
///
/// Every field is optional and omitted when nil, so a rename sends only `name`,
/// a star or unstar sends only `starred`, and a pure parent move sends `{}` —
/// the parent change travels in the URL as `addParents`/`removeParents`, not in
/// the body. Encoding through ``GoogleJSON`` escapes the name safely, so a name
/// with a quote, a backslash, or a newline never breaks the JSON.
public struct DriveUpdateRequest: Codable, Sendable, Equatable {
    public let name: String?
    public let starred: Bool?

    public init(name: String? = nil, starred: Bool? = nil) {
        self.name = name
        self.starred = starred
    }
}

/// The `shortcutDetails` of a shortcut file: the id of the file it points to.
public struct DriveShortcutDetails: Codable, Sendable, Equatable {
    public let targetId: String

    public init(targetId: String) {
        self.targetId = targetId
    }
}

/// The request body for creating a shortcut via `files.create`.
///
/// A shortcut is an ordinary file whose MIME is
/// `application/vnd.google-apps.shortcut` and whose `shortcutDetails.targetId`
/// names the file it points to. The name and target travel in the body, never
/// in the URL; `parents` places the shortcut in a folder.
public struct DriveShortcutCreateRequest: Codable, Sendable, Equatable {
    /// The MIME type every Drive shortcut carries.
    public static let mimeType = "application/vnd.google-apps.shortcut"

    public let name: String
    public let mimeType: String
    public let parents: [String]?
    public let shortcutDetails: DriveShortcutDetails

    public init(name: String, targetId: String, parents: [String]? = nil) {
        self.name = name
        self.mimeType = Self.mimeType
        self.parents = parents
        self.shortcutDetails = DriveShortcutDetails(targetId: targetId)
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
