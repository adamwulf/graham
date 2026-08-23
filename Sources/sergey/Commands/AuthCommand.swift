import ArgumentParser
import Foundation
import SergeyKit

struct Auth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Log in to Google and check credentials.",
        subcommands: [Login.self, Status.self]
    )

    struct Login: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the one-time OAuth consent flow and print a refresh token."
        )

        @Option(help: "A scope to request: drive, drive-readonly, sheets, docs, or slides. Repeat the option for more scopes. The default is drive, sheets, docs, and slides.")
        var scope: [String] = []

        func run() async throws {
            let credentials = try CredentialsResolver.resolve()
            let scopes: [GoogleScope]
            if scope.isEmpty {
                scopes = GoogleScope.all
            } else {
                scopes = try scope.map { name in
                    guard let match = GoogleScope(shortName: name) else {
                        throw ValidationError(
                            "Unknown scope \"\(name)\". Valid scopes: "
                                + GoogleScope.allCases.map(\.shortName).joined(separator: ", ")
                        )
                    }
                    return match
                }
            }
            print("Opening the browser for Google consent...")
            print("Scopes: \(scopes.map(\.shortName).joined(separator: ", "))")
            let flow = OAuthLoginFlow()
            let grant = try await flow.run(credentials: credentials, scopes: scopes)
            guard let refreshToken = grant.refreshToken else {
                throw SergeyError.oauthError(
                    "Google did not return a refresh token. Remove this app's access at "
                        + "https://myaccount.google.com/permissions and log in again."
                )
            }
            print("""

            Login complete. Add this line to your .env file:

            GOOGLE_REFRESH_TOKEN=\(refreshToken)
            """)
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show which credentials are set, and test a token refresh."
        )

        func run() async throws {
            let keys = [
                CredentialsResolver.clientIDKey,
                CredentialsResolver.clientSecretKey,
                CredentialsResolver.refreshTokenKey,
            ]
            var allSet = true
            for key in keys {
                let isSet = CredentialsResolver.value(forKey: key) != nil
                allSet = allSet && isSet
                print("\(isSet ? "set    " : "missing") \(key)")
            }
            guard allSet else {
                print("\nSet the missing keys in your environment or in a .env file.")
                print("Run \"sergey auth login\" to get a refresh token.")
                throw ExitCode.failure
            }
            let credentials = try CredentialsResolver.resolve()
            let provider = OAuthTokenProvider(credentials: credentials, transport: URLSessionTransport())
            _ = try await provider.validAccessToken()
            if let expiry = await provider.currentExpiry {
                let seconds = Int(expiry.timeIntervalSinceNow)
                print("\nToken refresh OK. The access token is valid for \(seconds) seconds.")
            } else {
                print("\nToken refresh OK.")
            }
        }
    }
}
