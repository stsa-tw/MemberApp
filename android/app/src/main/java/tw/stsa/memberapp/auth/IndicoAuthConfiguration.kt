package tw.stsa.memberapp.auth

import android.net.Uri
import androidx.core.net.toUri
import net.openid.appauth.AuthorizationServiceConfiguration

/**
 * Static OAuth 2.0 client registration for the STSA Indico instance.
 *
 * Deliberately separate from [AuthConfiguration] rather than folded into it.
 * These are two different providers with two different registrations, and they
 * cannot be merged: MembershipAPI pins `iss` and `aud` to the authentik one,
 * and Indico only accepts tokens it issued itself.
 *
 * Indico is **not** an OIDC provider — `<issuer>/.well-known/openid-configuration`
 * 404s on this instance. The endpoints below are transcribed from the RFC 8414
 * document at `/.well-known/oauth-authorization-server` and written out rather
 * than discovered, because AppAuth's discovery only speaks OIDC.
 *
 * Every value here is shared with
 * `ios/MemberApp/Auth/IndicoAuthConfiguration.swift`.
 */
object IndicoAuthConfiguration {

    val AUTHORIZATION_ENDPOINT: Uri = "https://event.stsa.tw/oauth/authorize".toUri()
    val TOKEN_ENDPOINT: Uri = "https://event.stsa.tw/oauth/token".toUri()

    /**
     * A public client, like the authentik one. Indico's metadata lists `none` in
     * `token_endpoint_auth_methods_supported` and the application has "Allow
     * PKCE flow" on. Indico generates a client secret on the application page
     * anyway; it is deliberately unrecorded and unused.
     */
    const val CLIENT_ID = "3b1959b4-d9df-40ea-8b3a-b7b80a259612"

    /**
     * **The bridge URL, not the app's own scheme.** Indico's redirect validator
     * accepts `http(s)` only and rejects `tw.stsa.membership://callback` with
     * `ValueError: Invalid URI` — confirmed by trying it on this instance, not
     * just by reading `indico/modules/oauth/forms.py`. `tools/oauth-bridge/`
     * exists to carry the authorization response across to the app's scheme,
     * which AppAuth's redirect receiver is already registered for through the
     * `appAuthRedirectScheme` manifest placeholder.
     *
     * Indico matches a redirect by protocol, host and **path prefix**, so any
     * path starting with this one would also be accepted by Indico. The worker
     * is the narrower of the two checks: it 404s anything that is not exactly
     * this path. Keep both specific.
     */
    val REDIRECT_URI: Uri = "https://app.stsa.tw/oauth/app-callback".toUri()

    /**
     * `read:everything` is what lets a member's own token GET any endpoint *as
     * them* — `_lookup_request_user` in `indico/web/util.py` adds it to the
     * accepted scopes for every GET. It reads nothing the member could not
     * already see on the website.
     *
     * `registrants` looks like the narrower and therefore better choice. It is
     * not: the check-in API it unlocks also requires `registration_checkin` on
     * the event, which is an organiser permission, so a member's token cannot
     * use it to read even their own registration.
     */
    val SCOPES = listOf("read:everything")

    val serviceConfiguration = AuthorizationServiceConfiguration(
        AUTHORIZATION_ENDPOINT,
        TOKEN_ENDPOINT,
    )
}
