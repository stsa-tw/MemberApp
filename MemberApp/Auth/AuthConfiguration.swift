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
    static let issuer = URL(string: "https://idms.stsa.tw/application/o/stsa-membership-ios/")!

    /// Client IDs are not secrets for public clients — this is sent in the
    /// clear on every authorize request and is safe to keep in source.
    static let clientID = "kM2ZTsdapHIENbpvwZsWpLLW8srBLp9Ux6vZa7vl"

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
