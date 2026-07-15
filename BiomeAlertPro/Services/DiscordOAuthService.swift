import AppKit
import CryptoKit
import Foundation

/// Sign in with Discord using the official OAuth2 authorization-code flow
/// with PKCE. Authorization happens in the user's default browser; Discord
/// redirects back via the app's registered `biomealertpro://` URL scheme.
///
/// Scope is limited to `identify` — the app only learns who the user is.
/// Tokens are stored exclusively in the Keychain.
@MainActor
final class DiscordOAuthService: ObservableObject {
    @Published private(set) var user: DiscordUser?
    @Published private(set) var isAuthorizing = false
    @Published private(set) var statusMessage: String?

    static let redirectURI = "biomealertpro://oauth/callback"

    private enum KeychainKeys {
        static let accessToken = "discord.oauth.accessToken"
        static let refreshToken = "discord.oauth.refreshToken"
        static let expiry = "discord.oauth.expiry"
        static let clientSecret = "discord.oauth.clientSecret"
    }

    private let settings: SettingsStore
    private let secrets: any SecretStoring
    private let logs: LogStore
    private let session: URLSession

    private var pendingState: String?
    private var pendingVerifier: String?

    var isSignedIn: Bool { user != nil }

    init(settings: SettingsStore, secrets: any SecretStoring, logs: LogStore) {
        self.settings = settings
        self.secrets = secrets
        self.logs = logs
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: configuration)
    }

    /// Optional client secret for confidential Discord apps. Stored in Keychain.
    func setClientSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? secrets.deleteSecret(for: KeychainKeys.clientSecret)
        } else {
            try? secrets.setSecret(trimmed, for: KeychainKeys.clientSecret)
        }
    }

    // MARK: - Sign in

    /// Opens Discord's authorization page in the default browser.
    func beginSignIn() {
        let clientID = settings.discordClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            statusMessage = "Enter your Discord application's Client ID first (see Setup guide)."
            return
        }

        let state = Self.randomURLSafeString(bytes: 24)
        let verifier = Self.randomURLSafeString(bytes: 48)
        pendingState = state
        pendingVerifier = verifier

        var components = URLComponents(string: "https://discord.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: "identify"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components.url else { return }

        isAuthorizing = true
        statusMessage = "Waiting for authorization in your browser…"
        logs.log(.info, .network, "Discord OAuth flow started")
        NSWorkspace.shared.open(url)
    }

    /// Handles the `biomealertpro://oauth/callback` redirect.
    func handleCallback(url: URL) async {
        guard url.scheme?.lowercased() == "biomealertpro" else { return }
        defer { isAuthorizing = false }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              state == pendingState,
              let verifier = pendingVerifier else {
            statusMessage = "Sign-in was cancelled or the callback was invalid."
            logs.log(.warning, .security, "OAuth callback rejected (state mismatch or missing code)")
            return
        }
        pendingState = nil
        pendingVerifier = nil

        do {
            var form: [String: String] = [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": settings.discordClientID,
                "code_verifier": verifier
            ]
            if let secret = try? secrets.secret(for: KeychainKeys.clientSecret), !secret.isEmpty {
                form["client_secret"] = secret
            }
            let token = try await requestToken(form: form)
            try storeToken(token)
            try await fetchUser(accessToken: token.accessToken)
            statusMessage = nil
            logs.log(.info, .network, "Discord sign-in succeeded")
        } catch {
            statusMessage = "Sign-in failed: \(error.localizedDescription)"
            logs.log(.error, .network, "Discord sign-in failed: \(error.localizedDescription)")
        }
    }

    /// Restores a previous session at launch, refreshing the token if needed.
    func restoreSession() async {
        guard let accessToken = try? secrets.secret(for: KeychainKeys.accessToken), !accessToken.isEmpty else {
            return
        }
        let expiry = (try? secrets.secret(for: KeychainKeys.expiry)).flatMap(Double.init) ?? 0
        if Date().timeIntervalSince1970 < expiry - 60 {
            try? await fetchUser(accessToken: accessToken)
        } else if let refreshToken = try? secrets.secret(for: KeychainKeys.refreshToken), !refreshToken.isEmpty {
            do {
                var form: [String: String] = [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": settings.discordClientID
                ]
                if let secret = try? secrets.secret(for: KeychainKeys.clientSecret), !secret.isEmpty {
                    form["client_secret"] = secret
                }
                let token = try await requestToken(form: form)
                try storeToken(token)
                try await fetchUser(accessToken: token.accessToken)
                logs.log(.info, .network, "Discord session refreshed")
            } catch {
                logs.log(.warning, .network, "Discord session refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func signOut() {
        // Best-effort token revocation, then wipe local credentials.
        if let token = try? secrets.secret(for: KeychainKeys.accessToken), !token.isEmpty {
            let clientID = settings.discordClientID
            Task { [session] in
                var request = URLRequest(url: URL(string: "https://discord.com/api/v10/oauth2/token/revoke")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.formEncode([
                    "token": token,
                    "token_type_hint": "access_token",
                    "client_id": clientID
                ])
                _ = try? await session.data(for: request)
            }
        }
        try? secrets.deleteSecret(for: KeychainKeys.accessToken)
        try? secrets.deleteSecret(for: KeychainKeys.refreshToken)
        try? secrets.deleteSecret(for: KeychainKeys.expiry)
        user = nil
        statusMessage = nil
        logs.log(.info, .network, "Signed out of Discord")
    }

    // MARK: - HTTP

    private func requestToken(form: [String: String]) async throws -> DiscordTokenResponse {
        var request = URLRequest(url: URL(string: "https://discord.com/api/v10/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(form)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WebhookError.httpStatus(code, "token exchange rejected")
        }
        return try JSONDecoder().decode(DiscordTokenResponse.self, from: data)
    }

    private func fetchUser(accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://discord.com/api/v10/users/@me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WebhookError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, "profile fetch failed")
        }
        user = try JSONDecoder().decode(DiscordUser.self, from: data)
    }

    private func storeToken(_ token: DiscordTokenResponse) throws {
        try secrets.setSecret(token.accessToken, for: KeychainKeys.accessToken)
        if let refresh = token.refreshToken {
            try secrets.setSecret(refresh, for: KeychainKeys.refreshToken)
        }
        let expiry = Date().timeIntervalSince1970 + token.expiresIn
        try secrets.setSecret(String(expiry), for: KeychainKeys.expiry)
    }

    // MARK: - Crypto helpers

    private static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = form.map { key, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}
