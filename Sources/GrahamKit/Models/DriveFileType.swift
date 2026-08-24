import Foundation

/// A file-type filter for Drive listings.
///
/// Each case maps to a Google Workspace MIME type (or `nil` for `all`), and
/// carries a short name for the command line, mirroring ``GoogleScope``.
public enum DriveFileType: String, CaseIterable, Sendable {
    case docs
    case sheets
    case slides
    case folders
    case all

    /// The MIME type this filter matches, or `nil` for `all` (no MIME clause).
    public var mimeType: String? {
        switch self {
        case .docs: return "application/vnd.google-apps.document"
        case .sheets: return "application/vnd.google-apps.spreadsheet"
        case .slides: return "application/vnd.google-apps.presentation"
        case .folders: return "application/vnd.google-apps.folder"
        case .all: return nil
        }
    }

    /// The short name used on the command line.
    public var shortName: String {
        rawValue
    }

    public init?(shortName: String) {
        guard let match = DriveFileType.allCases.first(where: { $0.shortName == shortName }) else {
            return nil
        }
        self = match
    }
}
