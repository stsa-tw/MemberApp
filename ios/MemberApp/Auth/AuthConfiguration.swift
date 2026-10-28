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

    /// Where a member deletes their account (App Store guideline 5.1.1(v)).
    ///
    /// authentik's `account-deletion` flow, reached through the brand's default
    /// authentication flow. Authentication comes first because the deletion
    /// flow requires a signed-in browser and simply denies one that is not; a
    /// browser that already is signed in skips past it, because the flow is
    /// `require_unauthenticated` with the default "message, continue" denied
    /// action, which follows a relative `next`.
    static let accountDeletionURL = URL(
        string: "https://idms.stsa.tw/flows/-/default/authentication/?next=%2Fif%2Fflow%2Faccount-deletion%2F"
    )!

    /// The authentication flow the iOS app signs in through, in place of the
    /// brand's default one.
    ///
    /// It offers Sign in with Apple and none of the other third-party sign-ins
    /// the web page has. That is what App Store guideline 4.8 turns on: an app
    /// that signs people in with another company's account must offer an
    /// equivalent that is Apple's, or else offer no third-party sign-in at all.
    ///
    /// authentik picks the authentication flow from the brand, and nothing in an
    /// OIDC request can ask for another. So the app opens this flow itself and
    /// hands it the authorize request as `next`, the same way account deletion
    /// reaches its flow; when the person is signed in the flow sends the browser
    /// on to the authorize endpoint, and PKCE and the redirect are untouched.
    static let signInFlowURL = URL(string: "https://idms.stsa.tw/if/flow/ios-authentication-flow/")!

    /// `offline_access` is what makes authentik return a refresh token.
    static let scopes = [
        OIDScopeOpenID,
        OIDScopeProfile,
        OIDScopeEmail,
        "offline_access",
    ]
}
