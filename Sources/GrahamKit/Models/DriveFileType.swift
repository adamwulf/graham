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

/// The Google Workspace file types graham can create.
///
/// Unlike ``DriveFileType`` (a listing filter, which also has `all`), every
/// case here maps to a concrete Google MIME type, so
/// `files.create` always has a type to send. The short names mirror the
/// matching ``DriveFileType`` cases, so the command line is consistent.
public enum DriveCreateType: String, CaseIterable, Sendable {
    case docs
    case sheets
    case slides
    case folder

    /// The Google Workspace MIME type of a new file of this type.
    public var mimeType: String {
        switch self {
        case .docs: return "application/vnd.google-apps.document"
        case .sheets: return "application/vnd.google-apps.spreadsheet"
        case .slides: return "application/vnd.google-apps.presentation"
        case .folder: return "application/vnd.google-apps.folder"
        }
    }

    /// The short name used on the command line.
    public var shortName: String {
        rawValue
    }

    public init?(shortName: String) {
        guard let match = DriveCreateType.allCases.first(where: { $0.shortName == shortName }) else {
            return nil
        }
        self = match
    }
}

/// The Google Workspace types a foreign file can be converted to.
///
/// This is the inverse of ``DriveExportFormat``: export sends a Google
/// Workspace file *out* to a foreign format; convert imports a foreign file (a
/// `.pptx`, `.docx`, `.xlsx`, `.csv`, ...) already in Drive *into* one of these
/// Google editor types, through an import-converting `files.copy`. Google's
/// import conversion targets only a small set of editor types; this enum lists
/// the three graham can read and edit afterward — a Doc, a Sheet, or a Slides
/// deck. (Drive can also import to a Drawing or an Apps Script, but graham has
/// no command for those, so a converted result would be a dead end.)
///
/// The MIME strings live once, on ``DriveCreateType``; this enum only supplies
/// the singular command-line names that mirror the `drive create` subcommands
/// (`doc`, `sheet`, `slides`). Not every source converts to every target:
/// Google fixes the allowed pairs (`.pptx` → slides, `.docx` → doc,
/// `.xlsx`/`.csv` → sheet, ...) and rejects a bad pairing with a `400`, which
/// the client surfaces. This enum only names the target; it does not check the
/// source file.
public enum DriveConvertType: String, CaseIterable, Sendable {
    case doc
    case sheet
    case slides

    /// The Google Workspace MIME type this file is converted to. Routes through
    /// ``DriveCreateType`` so the MIME strings stay in one place.
    public var mimeType: String {
        switch self {
        case .doc: return DriveCreateType.docs.mimeType
        case .sheet: return DriveCreateType.sheets.mimeType
        case .slides: return DriveCreateType.slides.mimeType
        }
    }

    /// The short name used on the command line.
    public var shortName: String {
        rawValue
    }

    public init?(shortName: String) {
        guard let match = DriveConvertType.allCases.first(where: { $0.shortName == shortName }) else {
            return nil
        }
        self = match
    }
}

/// A short name for a common `files.export` target format.
///
/// `graham drive export` maps each case to the MIME type Google's Drive
/// `files.export` endpoint expects, so a caller picks `docx` instead of
/// guessing `application/vnd.openxmlformats-officedocument.wordprocessingml.document`.
/// The list is deliberately short — the everyday formats. The raw `--mime`
/// option stays available for any format not listed here (for example
/// `application/rtf` or an OpenDocument type).
///
/// Not every format applies to every file: `docx` fits a Doc, `xlsx`/`csv` a
/// Sheet, `pptx` a Slides deck. Google rejects an unsupported pairing with a
/// `400`, which the client surfaces; this enum only names the type, it does not
/// check the file.
public enum DriveExportFormat: String, CaseIterable, Sendable {
    case txt
    case md
    case csv
    case pdf
    case docx
    case pptx
    case xlsx

    /// The MIME type Google's `files.export` endpoint expects for this format.
    public var mimeType: String {
        switch self {
        case .txt: return "text/plain"
        case .md: return "text/markdown"
        case .csv: return "text/csv"
        case .pdf: return "application/pdf"
        case .docx:
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .pptx:
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case .xlsx:
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
    }
}
