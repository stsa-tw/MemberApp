import AppAuth
import Foundation
import Observation
import UIKit

/// OIDC authorization-code + PKCE against the STSA authentik tenant.
///
/// Design is driven by the 5-minute access-token lifetime: nothing ever holds
/// an access token string. `accessToken()` goes through
/// `OIDAuthState.performAction(freshTokens:)` on every call, which returns the
/// cached token if it is still valid and silently redeems the refresh token if
/// it is not. Callers get a token that is good *right now* or an error.
@MainActor
@Observable
final class AuthManager {
    enum AuthError: LocalizedError {
        case notAuthenticated
        case sessionExpired
        case noPresenter
        case missingUserinfoEndpoint
        case userinfoFailed(status: Int, body: String)
        case tokenUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                "Not signed in."
            case .sessionExpired:
                String(localized: "登入已失效，請重新登入。")
            case .noPresenter:
                "No foreground window to present the sign-in page from."
            case .missingUserinfoEndpoint:
                "The discovery document did not advertise a userinfo endpoint."
            case .userinfoFailed(let status, let body):
                "userinfo returned HTTP \(status): \(body)"
            case .tokenUnavailable:
                "The authorization server did not return an access token."
            }
        }
    }

    private static let keychainService = "tw.stsa.membership.oidc"
    private static let keychainAccount = "authState"
    private static let subjectDefaultsKey = "auth.currentSubject"

    private(set) var isLoggedIn = false
    private(set) var profile: Profile?
    private(set) var isBusy = false

    @ObservationIgnored private var authState: OIDAuthState?
    @ObservationIgnored private var userAgentSession: (any OIDExternalUserAgentSession)?
    @ObservationIgnored private var serviceConfiguration: OIDServiceConfiguration?

    init() {
        restore()
    }

    // MARK: - Session lifecycle

    func login() async throws {
        isBusy = true
        defer { isBusy = false }

        let configuration = try await discoverConfiguration()

        // The standard initialiser (no clientSecret overload) derives a PKCE
        // code_verifier and an S256 code_challenge on its own. Do not replace
        // it with the clientSecret variant — this client is public.
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: AuthConfiguration.clientID,
            scopes: AuthConfiguration.scopes,
            redirectURL: AuthConfiguration.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        let presenter = try topViewController()

        // AppAuth drives ASWebAuthenticationSession here, so the sign-in page
        // runs in Safari's session and participates in SSO. Never swap this for
        // a WKWebView.
        let state: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            userAgentSession = OIDAuthState.authState(
                byPresenting: request,
                presenting: presenter
            ) { authState, error in
                if let authState {
                    continuation.resume(returning: authState)
                } else {
                    continuation.resume(throwing: error ?? AuthError.tokenUnavailable)
                }
            }
        }

        userAgentSession = nil
        adopt(state)

        let (profile, rawUserinfo) = try await fetchProfile()
        self.profile = profile
        cache(profile)

        logLoginResult(rawUserinfo: rawUserinfo, state: state)
    }

    /// Drops every local credential.
    ///
    /// Deliberately local-only. Because the flow runs in the shared Safari
    /// session, the authentik session cookie survives — the next `login()` may
    /// complete without a prompt. If you need to end the IdP session too, that
    /// is an RP-initiated logout against
    /// `serviceConfiguration?.discoveryDocument?.endSessionEndpoint`.
    func logout() {
        if let sub = profile?.sub ?? UserDefaults.standard.string(forKey: Self.subjectDefaultsKey) {
            UserDefaults.standard.removeObject(forKey: Self.profileKey(for: sub))
        }
        UserDefaults.standard.removeObject(forKey: Self.subjectDefaultsKey)
        try? Keychain.remove(service: Self.keychainService, account: Self.keychainAccount)

        userAgentSession = nil
        authState = nil
        profile = nil
        isLoggedIn = false
    }

    /// True when the person dismissed the sign-in sheet themselves. Callers
    /// should treat this as "nothing happened", not as a failure worth an alert.
    static func isUserCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == OIDGeneralErrorDomain
            && error.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue
    }

    /// Hands the redirect back to the in-flight authorization request.
    /// Wired up from `.onOpenURL` in `MemberAppApp`.
    @discardableResult
    func resume(_ url: URL) -> Bool {
        guard let session = userAgentSession else { return false }
        let handled = session.resumeExternalUserAgentFlow(with: url)
        if handled { userAgentSession = nil }
        return handled
    }

    // MARK: - Tokens

    /// The only supported way to get an access token.
    ///
    /// Never store the return value. Access tokens live 5 minutes; call this
    /// again for the next request and let AppAuth decide whether a refresh is
    /// needed.
    func accessToken() async throws -> String {
        guard let authState else { throw AuthError.notAuthenticated }

        do {
            let token: String = try await withCheckedThrowingContinuation { continuation in
                authState.performAction { accessToken, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let accessToken {
                        continuation.resume(returning: accessToken)
                    } else {
                        continuation.resume(throwing: AuthError.tokenUnavailable)
                    }
                }
            }

            // A refresh rotates the token response (and on authentik, often the
            // refresh token too), so write the updated state back.
            persist(authState)
            isLoggedIn = authState.isAuthorized

            return token
        } catch {
            // A session dying is ordinary: authentik rotates refresh tokens, they
            // expire after 30 days, and they can be revoked from the account page.
            // What is not ordinary is what used to happen next — this method threw
            // before it could update `isLoggedIn`, so the app stayed on the
            // signed-in screen with a session that could never work again, showing
            // a raw OAuth error and a Retry button that could not succeed. The
            // only way out was to find 登出 in 設定.
            //
            // AppAuth has already folded a permanent OAuth failure into the state
            // (`updateWithTokenResponse` routes `OIDOAuthTokenErrorDomain` to
            // `updateWithAuthorizationError`), so it can be asked.
            if authState.authorizationError != nil {
                logout()
                throw AuthError.sessionExpired
            }

            // Transient failure — a rotation may still have landed before it, so
            // keep whatever AppAuth wrote rather than leaving a superseded refresh
            // token in the keychain.
            persist(authState)
            throw error
        }
    }

    /// Renews the access token if it has lapsed, so the next request does not
    /// pay for a token exchange first.
    ///
    /// Called when the app comes to the foreground — not on a timer. An access
    /// token is only needed at the moment of a request, and `performAction`
    /// already renews one transparently, so polling would spend battery and
    /// rotate refresh tokens for nothing. Safe to call often: AppAuth returns
    /// the cached token while it is fresh and queues concurrent callers onto a
    /// single refresh when it is not.
    func refreshIfNeeded() async {
        guard isLoggedIn else { return }
        _ = try? await accessToken()

        // The keychain survives app deletion but UserDefaults does not, so a
        // reinstall restores the session with no cached profile — signed in,
        // but with no idea who the member is. Re-fetch rather than showing an
        // account screen with blank fields.
        if profile == nil, let (fetched, _) = try? await fetchProfile() {
            profile = fetched
            cache(fetched)
        }
    }

    /// Builds a request carrying a token that is fresh at the moment of the call.
    /// Use this for every outbound API call rather than holding a token.
    func authorizedRequest(for url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Discovery

    private func discoverConfiguration() async throws -> OIDServiceConfiguration {
        if let serviceConfiguration { return serviceConfiguration }

        let configuration: OIDServiceConfiguration = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(forIssuer: AuthConfiguration.issuer) { configuration, error in
                if let configuration {
                    continuation.resume(returning: configuration)
                } else {
                    continuation.resume(throwing: error ?? AuthError.tokenUnavailable)
                }
            }
        }

        serviceConfiguration = configuration
        return configuration
    }

    // MARK: - Userinfo

    /// Returns the decoded profile plus the raw body, so the caller can log the
    /// exact claim set authentik issued.
    private func fetchProfile() async throws -> (Profile, Data) {
        let configuration = try await discoverConfiguration()
        guard let endpoint = configuration.discoveryDocument?.userinfoEndpoint else {
            throw AuthError.missingUserinfoEndpoint
        }

        let request = try await authorizedRequest(for: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AuthError.userinfoFailed(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "<binary>"
            )
        }

        return (try JSONDecoder().decode(Profile.self, from: data), data)
    }

    // MARK: - Persistence

    private func adopt(_ state: OIDAuthState) {
        authState = state
        isLoggedIn = state.isAuthorized
        persist(state)
    }

    private func persist(_ state: OIDAuthState) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            try Keychain.set(data, service: Self.keychainService, account: Self.keychainAccount)
        } catch {
            // Losing the write means the user re-authenticates next launch —
            // bad UX, not a correctness problem. Never fall back to a file.
            print("[Auth] Could not persist auth state to keychain: \(error)")
        }
    }

    private func restore() {
        guard let data = try? Keychain.get(service: Self.keychainService, account: Self.keychainAccount),
              let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
        else { return }

        authState = state
        isLoggedIn = state.isAuthorized

        if let sub = UserDefaults.standard.string(forKey: Self.subjectDefaultsKey),
           let cached = UserDefaults.standard.data(forKey: Self.profileKey(for: sub)) {
            profile = try? JSONDecoder().decode(Profile.self, from: cached)
        }
    }

    /// Profile claims are not credentials, so they live in UserDefaults — but
    /// keyed on `sub`, never on email or username.
    private func cache(_ profile: Profile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.profileKey(for: profile.sub))
        UserDefaults.standard.set(profile.sub, forKey: Self.subjectDefaultsKey)
    }

    private static func profileKey(for sub: String) -> String { "auth.profile.\(sub)" }

    // MARK: - Verification logging

    private func logLoginResult(rawUserinfo: Data, state: OIDAuthState) {
        #if DEBUG
        let pretty: String = {
            guard let object = try? JSONSerialization.jsonObject(with: rawUserinfo),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                  let string = String(data: data, encoding: .utf8)
            else { return String(data: rawUserinfo, encoding: .utf8) ?? "<undecodable>" }
            return string
        }()

        print("""
        [Auth] ── login succeeded ────────────────────────────────
        [Auth] refresh token returned: \(state.refreshToken != nil ? "YES" : "NO — check that offline_access is granted for this application in authentik")
        [Auth] access token expires:   \(state.lastTokenResponse?.accessTokenExpirationDate.map(String.init(describing:)) ?? "unknown")
        [Auth] scopes granted:         \(state.lastTokenResponse?.scope ?? "none reported")
        [Auth] raw userinfo response:
        \(pretty)
        [Auth] ─────────────────────────────────────────────────────
        """)
        #endif
    }

    // MARK: - Presentation

    private func topViewController() throws -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? scenes.compactMap(\.keyWindow).first

        guard var top = window?.rootViewController else { throw AuthError.noPresenter }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
