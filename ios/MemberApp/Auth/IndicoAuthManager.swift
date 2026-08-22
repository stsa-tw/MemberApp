import AppAuth
import Foundation
import Observation

/// OAuth 2.0 authorization code + PKCE against the STSA Indico instance.
///
/// This is the *second* identity in the app and it is not a second sign-in.
/// authentik says who the member is; this says "and that person has linked
/// their Indico account", which is what makes it possible to read their own
/// registrations and tickets without any server of ours in the middle.
///
/// Deliberately smaller than `AuthManager`, because Indico's tokens are a
/// different shape:
///
/// - **They never expire.** `OAuthToken.get_expires_in()` returns `0` and
///   `is_expired()` returns `false` in Indico's own model, and there is no
///   refresh token to redeem. So there is no refresh loop here and nothing to
///   renew on foreground.
/// - **There is no `offline_access` equivalent**, and no userinfo — the token is
///   an opaque bearer string and nothing else.
///
/// Because the token never expires, `AuthManager`'s rule that nothing may hold
/// an access token does not carry over: that rule exists because authentik's
/// tokens live five minutes, and `performAction(freshTokens:)` is how you avoid
/// holding a stale one. Here freshness has no meaning. The token still lives in
/// the Keychain and nowhere else.
@MainActor
@Observable
final class IndicoAuthManager {
    enum LinkError: LocalizedError {
        case notLinked
        case stateMismatch
        case tokenUnavailable
        case server(error: String, description: String?)

        var errorDescription: String? {
            switch self {
            case .notLinked:
                "Indico account is not linked."
            case .stateMismatch:
                "The authorization response did not match the request."
            case .tokenUnavailable:
                "Indico did not return an access token."
            case .server(let error, let description):
                "Indico refused the authorization: \(description ?? error)"
            }
        }
    }

    private static let keychainService = "tw.stsa.membership.indico"
    private static let keychainAccount = "authState"

    /// Whether the member has authorized the app against Indico. Drives whether
    /// the ticket UI offers "link" or goes straight to fetching.
    private(set) var isLinked = false
    private(set) var isBusy = false

    @ObservationIgnored private var token: String?

    init() {
        restore()
    }

    // MARK: - Linking

    /// Runs the authorization flow. Call this at the point the member asks for
    /// something that needs it, not at sign-in — see the note in `TicketStore`.
    func link() async throws {
        isBusy = true
        defer { isBusy = false }

        // The standard initialiser derives the PKCE verifier and S256 challenge.
        // Do not switch to the `clientSecret` overload: this client is public and
        // Indico's application has "Allow PKCE flow" on precisely so it can be.
        let request = OIDAuthorizationRequest(
            configuration: IndicoAuthConfiguration.serviceConfiguration,
            clientId: IndicoAuthConfiguration.clientID,
            scopes: IndicoAuthConfiguration.scopes,
            redirectURL: IndicoAuthConfiguration.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        let callback = try await IndicoBrowserSession.authorize(url: request.authorizationRequestURL())
        let code = try Self.authorizationCode(from: callback, expecting: request.state)

        // `redirectURL` here must be the value that was sent to the authorize
        // endpoint — the bridge, not the scheme the response came back on. Indico
        // compares the two and rejects the exchange if they differ.
        let tokenRequest = OIDTokenRequest(
            configuration: IndicoAuthConfiguration.serviceConfiguration,
            grantType: OIDGrantTypeAuthorizationCode,
            authorizationCode: code,
            redirectURL: IndicoAuthConfiguration.redirectURI,
            clientID: IndicoAuthConfiguration.clientID,
            clientSecret: nil,
            scope: nil,
            refreshToken: nil,
            codeVerifier: request.codeVerifier,
            additionalParameters: nil
        )

        let response: OIDTokenResponse = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(tokenRequest) { response, error in
                if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: error ?? LinkError.tokenUnavailable)
                }
            }
        }

        guard let token = response.accessToken else { throw LinkError.tokenUnavailable }
        adopt(token)
        logLinkResult(response)
    }

    /// Pulls the code out of the callback, refusing anything whose `state` is not
    /// the one this request generated. AppAuth would normally do this; since the
    /// browser leg is ours, so is the check.
    private static func authorizationCode(from callback: URL, expecting state: String?) throws -> String {
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw LinkError.server(error: error, description: value("error_description"))
        }
        guard value("state") == state else { throw LinkError.stateMismatch }
        guard let code = value("code") else { throw LinkError.tokenUnavailable }
        return code
    }

    /// Drops the Indico token. Local-only, like `AuthManager.logout()` — the
    /// authorization itself is revoked by the member from Indico's own settings,
    /// which is the only place that can actually do it.
    func unlink() {
        try? Keychain.remove(service: Self.keychainService, account: Self.keychainAccount)
        token = nil
        isLinked = false
    }

    // MARK: - Tokens

    /// The Indico bearer token, or an error if the account is not linked.
    ///
    /// A plain string rather than an `OIDAuthState`, because none of what that
    /// type manages applies: the token never expires, there is no refresh token,
    /// and `performAction(freshTokens:)` would only invent a reason to fail.
    func bearerToken() throws -> String {
        guard let token else { throw LinkError.notLinked }
        return token
    }

    func authorizedRequest(for url: URL) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try bearerToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Persistence

    private func adopt(_ token: String) {
        self.token = token
        isLinked = true

        do {
            try Keychain.set(Data(token.utf8), service: Self.keychainService, account: Self.keychainAccount)
        } catch {
            // Same reasoning as AuthManager: losing the write costs the member one
            // more authorization tap. Never fall back to a file.
            print("[Indico] Could not persist the token to keychain: \(error)")
        }
    }

    private func restore() {
        guard let data = try? Keychain.get(service: Self.keychainService, account: Self.keychainAccount),
              let stored = String(data: data, encoding: .utf8),
              !stored.isEmpty
        else { return }

        token = stored
        isLinked = true
    }

    // MARK: - Verification logging

    private func logLinkResult(_ response: OIDTokenResponse) {
        #if DEBUG
        print("""
        [Indico] ── account linked ──────────────────────────────
        [Indico] token type:        \(response.tokenType ?? "none reported")
        [Indico] scopes granted:    \(response.scope ?? "none reported")
        [Indico] refresh token:     \(response.refreshToken != nil ? "YES — unexpected, Indico issues none" : "no (expected)")
        [Indico] access expires:    \(response.accessTokenExpirationDate.map(String.init(describing:)) ?? "never (expected)")
        [Indico] ────────────────────────────────────────────────
        """)
        #endif
    }
}
