import Foundation

/// Builds Google API URLs.
public enum GoogleURL {
    /// Builds a URL from a base string and query parameters.
    ///
    /// Parameters with a `nil` value are dropped. The parameter order is kept,
    /// so URLs are stable and testable.
    ///
    /// Note: `URLComponents` leaves `+` unescaped, but Google reads `+` as a
    /// space. That corrupts search queries and base64-like page tokens. So this
    /// function escapes `+` as `%2B` after the query is built.
    public static func build(_ base: String, query: [(String, String?)] = []) throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw SergeyError.invalidURL(base)
        }
        let items = query.compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        if !items.isEmpty {
            components.queryItems = (components.queryItems ?? []) + items
        }
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            throw SergeyError.invalidURL(base)
        }
        return url
    }

    /// Escapes one path component, for example a file ID or an A1 range.
    public static func escapePathComponent(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
