import Foundation

/// The OAuth client credentials for the Google APIs.
public struct GoogleCredentials: Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String
    public var refreshToken: String?

    public init(clientID: String, clientSecret: String, refreshToken: String? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
    }
}

/// Finds credentials with this precedence: process environment first,
/// then the nearest `.env` file (see ``DotEnv``).
public enum CredentialsResolver {
    public static let clientIDKey = "GOOGLE_CLIENT_ID"
    public static let clientSecretKey = "GOOGLE_CLIENT_SECRET"
    public static let refreshTokenKey = "GOOGLE_REFRESH_TOKEN"

    /// Finds one value. The process environment wins over `.env` files.
    public static func value(
        forKey key: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingIn directory: URL? = nil
    ) -> String? {
        if let value = environment[key], !value.isEmpty {
            return value
        }
        return DotEnv.loadValue(forKey: key, startingIn: directory)
    }

    /// Resolves the full credentials.
    ///
    /// The client ID and the client secret are required. The refresh token is
    /// optional here; ``OAuthTokenProvider`` throws ``GrahamError/missingRefreshToken``
    /// when an API call needs it and it is not set.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingIn directory: URL? = nil
    ) throws -> GoogleCredentials {
        guard let clientID = value(forKey: clientIDKey, environment: environment, startingIn: directory) else {
            throw GrahamError.missingCredentials(key: clientIDKey)
        }
        guard let clientSecret = value(forKey: clientSecretKey, environment: environment, startingIn: directory) else {
            throw GrahamError.missingCredentials(key: clientSecretKey)
        }
        let refreshToken = value(forKey: refreshTokenKey, environment: environment, startingIn: directory)
        return GoogleCredentials(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
    }
}
