import Foundation

/// The errors that GrahamKit can throw.
public enum GrahamError: Error, LocalizedError {
    /// A required credential is not set in the environment or in a `.env` file.
    case missingCredentials(key: String)
    /// No refresh token is available, so the tool cannot get an access token.
    case missingRefreshToken
    /// A URL could not be built.
    case invalidURL(String)
    /// The server response was not valid HTTP.
    case invalidResponse(String)
    /// The server returned a non-success status with a body that is not a
    /// standard Google error envelope.
    case httpError(statusCode: Int, body: String)
    /// The server returned a standard Google error envelope.
    case googleAPIError(code: Int, status: String?, message: String)
    /// A JSON response did not match the expected model.
    case decodeError(detail: String)
    /// The OAuth flow failed.
    case oauthError(String)
    /// An argument to a high-level operation is invalid, for example a slide
    /// position that is out of range, or a slide id that does not exist.
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials(let key):
            return "Missing credential \(key). Set it as an environment variable, "
                + "or add the line \"\(key)=...\" to a .env file in this directory or a parent directory. "
                + "See README.md for the Google Cloud setup steps."
        case .missingRefreshToken:
            return "No refresh token found. Run \"graham auth login\", then add the printed "
                + "GOOGLE_REFRESH_TOKEN line to your .env file."
        case .invalidURL(let url):
            return "Could not build a valid URL from: \(url)"
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .httpError(let statusCode, let body):
            return "HTTP error \(statusCode): \(body)"
        case .googleAPIError(let code, let status, let message):
            let statusText = status.map { " (\($0))" } ?? ""
            return "Google API error \(code)\(statusText): \(message)"
        case .decodeError(let detail):
            return "Could not decode the response: \(detail)"
        case .oauthError(let detail):
            return "OAuth error: \(detail)"
        case .invalidArgument(let detail):
            return "Invalid argument: \(detail)"
        }
    }

    /// Makes a readable description of a `DecodingError`, with the JSON path
    /// of the field that failed.
    public static func decodingDetail(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return String(describing: error)
        }
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath
                .map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }
                .joined(separator: ".")
            return joined.isEmpty ? "(root)" : joined
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing key \"\(key.stringValue)\" at \(path(context))"
        case .typeMismatch(let type, let context):
            return "type mismatch for \(type) at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "missing value for \(type) at \(path(context))"
        case .dataCorrupted(let context):
            return "corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: decodingError)
        }
    }
}
