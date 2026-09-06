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
        /// Indico issued a token for somebody other than the member signed in
        /// here. `afterSigningIn` is what separates the two very different
        /// causes: before, the browser may simply have been carrying somebody
        /// else's session; after, the member has just proved they hold that
        /// Indico account, so the address on it is the thing that is wrong.
        case wrongAccount(indico: String, afterSigningIn: Bool)

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
            case .wrongAccount(let indico, let afterSigningIn):
                afterSigningIn
                    ? String(localized: "你的活動網站帳號登記的是 \(indico)，與這裡的 STSA 帳號不同。")
                    : String(localized: "活動網站目前登入的是 \(indico)，與這裡的 STSA 帳號不同。")
            }
        }
    }

    private static let keychainService = "tw.stsa.membership.indico"
    private static let keychainAccount = "authState"

    /// Whether the member has authorized the app against Indico. Drives whether
    /// the ticket UI offers "link" or goes straight to fetching.
    private(set) var isLinked = false
    private(set) var isBusy = false

    /// What Indico actually granted, which is not always what was asked for.
    /// Read rather than assumed: the application's allowed scopes are server
    /// config, so a request for `registrants` can come back without it.
    private(set) var grantedScopes: Set<String> = []

    @ObservationIgnored private var token: String?

    init() {
        restore()
    }

    // MARK: - Linking

    /// Runs the authorization flow. Call this at the point the member asks for
    /// something that needs it, not at sign-in — see the note in `TicketStore`.
    /// Whether this authorization can record a check-in, as opposed to only
    /// reading a roster.
    var canRecordCheckin: Bool {
        grantedScopes.contains(IndicoAuthConfiguration.checkinScope)
    }

    /// - Parameter forcingSignIn: run the page in a browser that carries no
    ///   cookies, so whoever the shared one is signed in as is irrelevant and
    ///   the member signs in as themselves.
    ///
    ///   This used to happen automatically the moment the shared browser
    ///   answered as somebody else. It worked, and it was mute: the member got a
    ///   second sheet asking for a password seconds after signing in, with
    ///   nothing on screen saying why, and cancelling it said nothing either. So
    ///   the retry is now something they are told about and ask for — see the
    ///   banner on the event page — and this is how they ask.
    func link(
        scopes: [String] = IndicoAuthConfiguration.scopes,
        forcingSignIn: Bool = false
    ) async throws {
        // Already known to be signed in as somebody else, so the shared browser
        // has nothing new to say — asking it again only puts up a login page
        // that cannot succeed, and the answer is already on screen.
        if let refused, !forcingSignIn {
            throw LinkError.wrongAccount(indico: refused.indico,
                                         afterSigningIn: refused.afterSigningIn)
        }

        try await authorize(scopes: scopes, ephemeral: forcingSignIn)
    }

    private func authorize(scopes: [String], ephemeral: Bool) async throws {
        isBusy = true
        defer { isBusy = false }

        // The standard initialiser derives the PKCE verifier and S256 challenge.
        // Do not switch to the `clientSecret` overload: this client is public and
        // Indico's application has "Allow PKCE flow" on precisely so it can be.
        let request = OIDAuthorizationRequest(
            configuration: IndicoAuthConfiguration.serviceConfiguration,
            clientId: IndicoAuthConfiguration.clientID,
            scopes: scopes,
            redirectURL: IndicoAuthConfiguration.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        log("opening \(ephemeral ? "a cookie-less" : "the shared") browser")

        let callback: URL
        do {
            callback = try await IndicoBrowserSession.authorize(
                url: request.authorizationRequestURL(),
                ephemeral: ephemeral
            )
        } catch {
            // The browser leg is the one part of this with no server to ask
            // afterwards: when the sheet closes with nothing, the only record
            // that it happened at all is here.
            log("browser returned nothing — \(error.localizedDescription)")
            throw error
        }
        // Never the URL itself. It carries the authorization code, and
        // `tools/oauth-bridge/README.md` asks for that to stay out of logs on
        // the way in — a debug build's console is no different.
        log("callback received")

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
        logLinkResult(response)

        // Asked *before* it is kept, and that order is the point. Adopting first
        // put the wrong token in the Keychain and `isLinked` on `true` for the
        // length of a network round trip — long enough for the ticket and door
        // screens to fire their own requests under it — and left it there for
        // good if the check itself could not complete. Nothing is written until
        // Indico has said whose it is.
        try await verifyOwner(token: token, afterSigningIn: ephemeral)
        adopt(token, scopes: Self.scopes(from: response.scope) ?? Set(scopes))
    }

    /// Who the member is here, so a token can be checked against them.
    ///
    /// Set from the composition root when the profile is known, the same way
    /// `TicketStore.subject` is. Email rather than `sub`, because the two
    /// providers do not share a subject: Indico has its own user ids, and the
    /// address is the one identifier both systems carry for the same person.
    var expectedEmail: String? {
        didSet {
            guard expectedEmail != oldValue else { return }
            // A different address is a different person asking, so whatever the
            // browser answered for the last one says nothing about this one.
            refused = nil
            // A token restored from the keychain has never been checked against
            // anybody: `restore()` runs in `init`, before there is a profile to
            // compare it to, and it trusts whatever the last install left there.
            // On the phone this was first found on, that is precisely the
            // officer's token — so the check has to happen here too, and not
            // only on a link the member just made.
            Task { await verifyRestored() }
        }
    }

    /// The last address Indico answered with that was not the member's.
    ///
    /// Session-only, and cleared the moment a different member is signed in — it
    /// exists so the app stops asking a browser whose answer is already known to
    /// be the wrong one, and so the screen can say which of the two problems
    /// this is.
    private(set) var refused: RefusedAccount?

    struct RefusedAccount: Equatable {
        let indico: String
        /// Indico's name for the account. The address alone does not let anyone
        /// recognise themselves — a member with three addresses cannot tell
        /// which of them is on which system — and telling the two identities
        /// apart is the whole decision this leaves to the member.
        let name: String?
        /// True when the member had just signed in themselves, in a browser
        /// carrying no session at all. That rules out "somebody else was still
        /// logged in here" and leaves only one explanation: the Indico account
        /// they hold is registered under a different address.
        let afterSigningIn: Bool
    }

    /// Refuses a token that belongs to somebody else.
    ///
    /// **The hole this closes.** `unlink()` drops *our* token, and `endSession`
    /// calls it — but Indico's own login is a **cookie in the system browser**,
    /// and no app can clear another app's cookies. So a phone where a 幹部 signed
    /// out and a member signed in still had the officer's session at
    /// `/oauth/authorize`; and because this application is registered as trusted
    /// on Indico, there is no consent screen for the new member to notice it on.
    /// The browser handed back an authorization for the *previous* person, and
    /// the app had no way to tell. That is how a member's phone ended up holding
    /// an organiser's token, which is Indico's answer to who may open a door.
    ///
    /// So the token is asked who it belongs to. `/api/user/` wants `read:user`,
    /// and `_lookup_request_user` in `indico/web/util.py` adds `read:everything`
    /// to the accepted scopes of every GET — so the token already in hand can
    /// answer, with no extra grant and no extra prompt.
    ///
    /// A mismatch throws the token away rather than keeping it: the member is
    /// better off with no Indico link than with someone else's.
    /// Checks the token `restore()` took on trust, which is the only one that
    /// can already be in the Keychain unverified — `init` runs before there is a
    /// profile to compare it against.
    ///
    /// Unlinks only when Indico actually names somebody else. An unreachable
    /// Indico proves nothing, and dropping a good link because the wifi blinked
    /// would cost the member their tickets for no reason.
    private func verifyRestored() async {
        guard isLinked, let token else {
            log("owner check: skipped — no token to check")
            return
        }
        do {
            // Nobody signed in for this one — it came out of the Keychain.
            try await verifyOwner(token: token, afterSigningIn: false)
        } catch LinkError.wrongAccount {
            unlink()
        } catch {
            log("owner check: inconclusive — could not ask Indico: \(error.localizedDescription)")
        }
    }

    private func verifyOwner(token: String, afterSigningIn: Bool) async throws {
        guard let expected = expectedEmail?.lowercased(), !expected.isEmpty else {
            log("owner check: skipped — no expected address yet, so nothing to compare against")
            return
        }
        guard let url = URL(string: "https://event.stsa.tw/api/user/") else { return }

        // Built here rather than through `authorizedRequest`, which reads the
        // stored token — the whole point is to ask about one that has not been
        // stored yet.
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        // A null body is an unauthenticated request, and an unreadable one is not
        // evidence of anything. Neither is grounds to accuse the token.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let owner = object["email"] as? String
        else {
            log("owner check: inconclusive — Indico did not name an owner: "
                + (String(data: data, encoding: .utf8) ?? "unreadable body"))
            return
        }

        guard owner.lowercased() == expected else {
            log("owner check: REFUSED — app is \(expected), token belongs to \(owner.lowercased())")
            let name = [object["first_name"] as? String, object["last_name"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            refused = RefusedAccount(indico: owner.lowercased(),
                                     name: name.isEmpty ? nil : name,
                                     afterSigningIn: afterSigningIn)
            throw LinkError.wrongAccount(indico: owner, afterSigningIn: afterSigningIn)
        }

        refused = nil
        log("owner check: ok — token belongs to \(owner.lowercased())")
    }

    /// DEBUG only. This check is silent when it passes and, until it was asked
    /// out loud, silent when it never ran either — which is indistinguishable
    /// from passing and is exactly what made it hard to tell whether a phone was
    /// holding somebody else's token.
    private func log(_ message: String) {
        #if DEBUG
        print("[Indico] \(message)")
        #endif
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
        grantedScopes = []
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

    /// Indico reports granted scopes as a space-separated list, per RFC 6749.
    private static func scopes(from raw: String?) -> Set<String>? {
        guard let raw, !raw.isEmpty else { return nil }
        return Set(raw.split(separator: " ").map(String.init))
    }

    private func adopt(_ token: String, scopes: Set<String>) {
        self.token = token
        grantedScopes = scopes
        isLinked = true

        // Stored together: a token whose scopes are unknown would send the door
        // to Indico only to be refused, after the worker had already scanned.
        let stored = Stored(token: token, scopes: Array(scopes).sorted())

        do {
            try Keychain.set(try JSONEncoder().encode(stored),
                             service: Self.keychainService, account: Self.keychainAccount)
        } catch {
            // Same reasoning as AuthManager: losing the write costs the member one
            // more authorization tap. Never fall back to a file.
            print("[Indico] Could not persist the token to keychain: \(error)")
        }
    }

    private func restore() {
        guard let data = try? Keychain.get(service: Self.keychainService, account: Self.keychainAccount)
        else { return }

        if let stored = try? JSONDecoder().decode(Stored.self, from: data), !stored.token.isEmpty {
            token = stored.token
            grantedScopes = Set(stored.scopes)
            isLinked = true
            return
        }

        // Anything written before scopes were recorded is a bare token string.
        // It is still a valid authorization, so keep it and assume the only
        // scope that was ever requested then, rather than making the member
        // link again.
        guard let bare = String(data: data, encoding: .utf8), !bare.isEmpty else { return }
        token = bare
        grantedScopes = Set(IndicoAuthConfiguration.scopes)
        isLinked = true
    }

    /// Keychain payload. Versionless on purpose: the decode either succeeds or
    /// falls back to the bare-token form above.
    private struct Stored: Codable {
        let token: String
        let scopes: [String]
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
