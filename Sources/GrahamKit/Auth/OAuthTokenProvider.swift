import Foundation

/// The response from Google's token endpoint.
struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Double?
    let refreshToken: String?
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

/// Encodes `application/x-www-form-urlencoded` bodies.
enum FormEncoder {
    static func encode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields
            .map { name, value in
                let name = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
                let value = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(name)=\(value)"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }
}

/// Supplies a valid OAuth2 access token.
///
/// Google access tokens expire after about one hour. This actor caches the
/// current token and refreshes it with the refresh token when it is near
/// expiry, or when ``GoogleAPI`` reports a 401 and calls ``invalidate()``.
public actor OAuthTokenProvider {
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    private let credentials: GoogleCredentials
    private let transport: any HTTPTransport
    private var accessToken: String?
    private var expiry: Date?

    public init(credentials: GoogleCredentials, transport: any HTTPTransport) {
        self.credentials = credentials
        self.transport = transport
    }

    /// Returns a token that is valid for at least 60 more seconds.
    public func validAccessToken() async throws -> String {
        if let accessToken, let expiry, expiry.timeIntervalSinceNow > 60 {
            return accessToken
        }
        return try await refreshAccessToken()
    }

    /// Drops the cached token, so the next call refreshes it.
    public func invalidate() {
        accessToken = nil
        expiry = nil
    }

    /// The expiry date of the cached token, if one is cached.
    public var currentExpiry: Date? {
        expiry
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = credentials.refreshToken else {
            throw GrahamError.missingRefreshToken
        }
        let body = FormEncoder.encode([
            ("client_id", credentials.clientID),
            ("client_secret", credentials.clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ])
        let request = HTTPRequest(
            method: "POST",
            url: Self.tokenEndpoint,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: response.body, encoding: .utf8) ?? ""
            throw GrahamError.oauthError(
                "Token refresh failed with status \(response.statusCode): \(String(text.prefix(500)))"
            )
        }
        let token: TokenResponse
        do {
            token = try GoogleJSON.decoder.decode(TokenResponse.self, from: response.body)
        } catch {
            throw GrahamError.decodeError(detail: GrahamError.decodingDetail(error))
        }
        accessToken = token.accessToken
        expiry = Date().addingTimeInterval(token.expiresIn ?? 3600)
        return token.accessToken
    }
}
