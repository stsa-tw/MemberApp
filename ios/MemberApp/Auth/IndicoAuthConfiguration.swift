import AppAuth
import Foundation

/// Static OAuth 2.0 client registration for the STSA Indico instance.
///
/// Deliberately separate from `AuthConfiguration` rather than folded into it.
/// These are two different providers with two different registrations, and they
/// cannot be merged: MembershipAPI pins `iss` and `aud` to the authentik one,
/// and Indico only accepts tokens it issued itself.
///
/// Indico is **not** an OIDC provider — `<issuer>/.well-known/openid-configuration`
/// 404s on this instance. The endpoints below are transcribed from the RFC 8414
/// document at `/.well-known/oauth-authorization-server` and written out rather
/// than discovered, because AppAuth's discovery only speaks OIDC.
enum IndicoAuthConfiguration {
    static let authorizationEndpoint = URL(string: "https://event.stsa.tw/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://event.stsa.tw/oauth/token")!

    /// A public client, like the authentik one. Indico's metadata lists `none`
    /// in `token_endpoint_auth_methods_supported` and the application has
    /// "Allow PKCE flow" on. Indico generates a client secret on the application
    /// page anyway; it is deliberately unrecorded and unused.
    static let clientID = "3b1959b4-d9df-40ea-8b3a-b7b80a259612"

    /// **The bridge URL, not the app's own scheme.** Indico's redirect validator
    /// accepts `http(s)` only and rejects `tw.stsa.membership://callback` with
    /// `ValueError: Invalid URI` — confirmed by trying it on this instance, not
    /// just by reading `indico/modules/oauth/forms.py`. `tools/oauth-bridge/`
    /// exists to carry the authorization response across to the app's scheme.
    ///
    /// Indico matches a redirect by protocol, host and **path prefix**, so any
    /// path starting with this one would also be accepted by Indico. The worker
    /// is the narrower of the two checks: it 404s anything that is not exactly
    /// this path. Keep both specific.
    static let redirectURI = URL(string: "https://app.stsa.tw/oauth/app-callback")!

    /// What the bridge forwards to, and therefore what the browser session has
    /// to watch for. AppAuth derives the callback scheme from `redirectURI` and
    /// would wait for `https`, which never arrives — see `IndicoUserAgent`.
    ///
    /// Must match `CFBundleURLSchemes` in `Config/Info.plist`; it is the same
    /// scheme the authentik flow returns through.
    static let callbackScheme = "tw.stsa.membership"

    /// `read:everything` is what lets a member's own token GET any endpoint *as
    /// them* — `_lookup_request_user` in `indico/web/util.py` adds it to the
    /// accepted scopes for every GET. It reads nothing the member could not
    /// already see on the website.
    ///
    /// `registrants` looks like the narrower and therefore better choice. It is
    /// not: the check-in API it unlocks also requires `registration_checkin` on
    /// the event, which is an organiser permission, so a member's token cannot
    /// use it to read even their own registration.
    static let scopes = ["read:everything"]

    static var serviceConfiguration: OIDServiceConfiguration {
        OIDServiceConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint
        )
    }
}
