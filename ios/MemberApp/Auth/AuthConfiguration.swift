import AppAuth
import Foundation

/// Static OIDC client registration for the STSA authentik tenant.
///
/// This is a **public client**: there is no client secret, and none should ever
/// be added. Proof of possession comes from PKCE (S256), which AppAuth derives
/// automatically in `OIDAuthorizationRequest`'s standard initialiser.
///
/// Endpoints are deliberately absent — authentik does not host them under the
/// issuer path and moves them between releases, so they are always read from
/// the discovery document at `<issuer>/.well-known/openid-configuration`.
enum AuthConfiguration {
    /// Deliberately the `membership` provider — the one the web card uses — and
    /// **not** `stsa-membership-ios`, which also exists and looks like the
    /// obvious choice.
    ///
    /// MembershipAPI pins both `iss` and `aud` to a single registration, so it
    /// only accepts tokens from this provider; tokens from the iOS-named one are
    /// rejected with 401 at `get_code`. `membership` is also the provider that
    /// has the `offline_access` scope mapping, without which there is no refresh
    /// token and the session dies after five minutes.
    ///
    /// The cost of sharing a client with the web app is that iOS sessions cannot
    /// be revoked separately and the API cannot tell the two apart. Splitting
    /// them again means teaching MembershipAPI to accept several providers, and
    /// then pointing these two constants back at `stsa-membership-ios`.
    static let issuer = URL(string: "https://idms.stsa.tw/application/o/membership/")!

    /// Client IDs are not secrets for public clients — this is sent in the
    /// clear on every authorize request and is safe to keep in source.
    static let clientID = "ZTK0PFLpwU2saDe4UMz2zYAF1TxNsE9ERyJt2S73"

    /// Must match `CFBundleURLSchemes` in `Config/Info.plist`.
    static let redirectURI = URL(string: "tw.stsa.membership://callback")!

    /// `offline_access` is what makes authentik return a refresh token.
    static let scopes = [
        OIDScopeOpenID,
        OIDScopeProfile,
        OIDScopeEmail,
        "offline_access",
    ]
}
