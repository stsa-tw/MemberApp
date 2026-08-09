package tw.stsa.memberapp.auth

import android.net.Uri
import androidx.core.net.toUri

/**
 * Static OIDC client registration for the STSA authentik tenant.
 *
 * This is a **public client**: there is no client secret, and none should ever
 * be added. Proof of possession comes from PKCE (S256), which AppAuth derives
 * automatically in `AuthorizationRequest.Builder`.
 *
 * Endpoints are deliberately absent — authentik does not host them under the
 * issuer path and moves them between releases, so they are always read from
 * the discovery document at `<issuer>/.well-known/openid-configuration`.
 *
 * Every value here is shared with `ios/MemberApp/Auth/AuthConfiguration.swift`.
 * They are two clients of one registration, so a change on one side without the
 * other produces 401s at `get_code` on that platform only.
 */
object AuthConfiguration {
    /**
     * Deliberately the `membership` provider — the one the web card uses — and
     * **not** `stsa-membership-ios`, which also exists and looks like the
     * obvious choice.
     *
     * MembershipAPI pins both `iss` and `aud` to a single registration, so it
     * only accepts tokens from this provider. `membership` is also the provider
     * that has the `offline_access` scope mapping, without which there is no
     * refresh token and the session dies after five minutes.
     */
    val ISSUER: Uri = "https://idms.stsa.tw/application/o/membership/".toUri()

    /**
     * Client IDs are not secrets for public clients — this is sent in the
     * clear on every authorize request and is safe to keep in source.
     */
    const val CLIENT_ID = "ZTK0PFLpwU2saDe4UMz2zYAF1TxNsE9ERyJt2S73"

    /**
     * Must match the `appAuthRedirectScheme` manifest placeholder in
     * app/build.gradle.kts, which is what registers AppAuth's redirect receiver.
     */
    val REDIRECT_URI: Uri = "tw.stsa.membership://callback".toUri()

    /** `offline_access` is what makes authentik return a refresh token. */
    val SCOPES = listOf("openid", "profile", "email", "offline_access")
}
