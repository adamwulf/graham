import Foundation

/// The result of a completed login flow.
public struct TokenGrant: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let scope: String?
    public let expiresIn: Double?
}

/// Runs the one-time OAuth consent flow for a desktop app:
///
/// 1. Start a loopback server on an ephemeral 127.0.0.1 port.
/// 2. Open the Google consent page in the browser.
/// 3. Receive the authorization code on the loopback redirect.
/// 4. Exchange the code for an access token and a refresh token.
///
/// The caller stores the refresh token (in `.env` as `GOOGLE_REFRESH_TOKEN`).
public struct OAuthLoginFlow {
    public static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"

    private let transport: any HTTPTransport
    private let openURL: @Sendable (URL) -> Void

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        openURL: @escaping @Sendable (URL) -> Void = { @Sendable url in
            OAuthLoginFlow.openInBrowser(url)
        }
    ) {
        self.transport = transport
        self.openURL = openURL
    }

    /// Opens a URL in the default browser with `/usr/bin/open`.
    public static func openInBrowser(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    public func run(credentials: GoogleCredentials, scopes: [GoogleScope]) async throws -> TokenGrant {
        let server = LoopbackServer()
        defer { server.stop() }
        let port = try server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let state = UUID().uuidString
        let authURL = try Self.authorizationURL(
            clientID: credentials.clientID,
            redirectURI: redirectURI,
            scopes: scopes,
            state: state
        )
        async let callback = server.waitForCallback()
        openURL(authURL)
        let query = try await callback
        guard query["state"] == state else {
            throw SergeyError.oauthError("The state parameter in the callback does not match.")
        }
        if let error = query["error"] {
            throw SergeyError.oauthError("Authorization failed: \(error)")
        }
        guard let code = query["code"] else {
            throw SergeyError.oauthError("The callback did not contain an authorization code.")
        }
        return try await exchange(code: code, redirectURI: redirectURI, credentials: credentials)
    }

    /// Builds the consent page URL.
    ///
    /// `access_type=offline` and `prompt=consent` make Google return a
    /// refresh token, not only an access token.
    static func authorizationURL(
        clientID: String,
        redirectURI: String,
        scopes: [GoogleScope],
        state: String
    ) throws -> URL {
        try GoogleURL.build(authEndpoint, query: [
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("response_type", "code"),
            ("scope", scopes.map(\.rawValue).joined(separator: " ")),
            ("access_type", "offline"),
            ("prompt", "consent"),
            ("state", state),
        ])
    }

    func exchange(code: String, redirectURI: String, credentials: GoogleCredentials) async throws -> TokenGrant {
        let body = FormEncoder.encode([
            ("client_id", credentials.clientID),
            ("client_secret", credentials.clientSecret),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
        ])
        let request = HTTPRequest(
            method: "POST",
            url: OAuthTokenProvider.tokenEndpoint,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let text = String(data: response.body, encoding: .utf8) ?? ""
            throw SergeyError.oauthError(
                "The code exchange failed with status \(response.statusCode): \(String(text.prefix(500)))"
            )
        }
        let token: TokenResponse
        do {
            token = try GoogleJSON.decoder.decode(TokenResponse.self, from: response.body)
        } catch {
            throw SergeyError.decodeError(detail: SergeyError.decodingDetail(error))
        }
        return TokenGrant(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            scope: token.scope,
            expiresIn: token.expiresIn
        )
    }
}
