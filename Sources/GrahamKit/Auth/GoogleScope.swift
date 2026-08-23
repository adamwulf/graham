import Foundation

/// The OAuth scopes that graham can request.
public enum GoogleScope: String, CaseIterable, Sendable {
    case drive = "https://www.googleapis.com/auth/drive"
    case driveReadonly = "https://www.googleapis.com/auth/drive.readonly"
    case spreadsheets = "https://www.googleapis.com/auth/spreadsheets"
    case documents = "https://www.googleapis.com/auth/documents"
    case presentations = "https://www.googleapis.com/auth/presentations"

    /// The default set: full access to Drive, Sheets, Docs, and Slides.
    public static let all: [GoogleScope] = [.drive, .spreadsheets, .documents, .presentations]

    /// The short name used on the command line.
    public var shortName: String {
        switch self {
        case .drive: return "drive"
        case .driveReadonly: return "drive-readonly"
        case .spreadsheets: return "sheets"
        case .documents: return "docs"
        case .presentations: return "slides"
        }
    }

    public init?(shortName: String) {
        guard let match = GoogleScope.allCases.first(where: { $0.shortName == shortName }) else {
            return nil
        }
        self = match
    }
}
