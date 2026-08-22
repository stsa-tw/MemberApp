package tw.stsa.memberapp.auth

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.ResponseTypeValues
import net.openid.appauth.TokenResponse
import tw.stsa.memberapp.BuildConfig
import tw.stsa.memberapp.R
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * OAuth 2.0 authorization code + PKCE against the STSA Indico instance.
 *
 * This is the *second* identity in the app and it is not a second sign-in.
 * authentik says who the member is; this says "and that person has linked their
 * Indico account", which is what makes it possible to read their own
 * registrations and tickets without any server of ours in the middle.
 *
 * Deliberately smaller than [AuthManager], because Indico's tokens are a
 * different shape:
 *
 * - **They never expire.** `OAuthToken.get_expires_in()` returns `0` and
 *   `is_expired()` returns `false` in Indico's own model, and there is no
 *   refresh token to redeem. So there is no refresh loop here and nothing to
 *   renew on foreground.
 * - **There is no userinfo and no `offline_access` equivalent** — the token is
 *   an opaque bearer string and nothing else.
 *
 * Because the token never expires, [AuthManager]'s rule that nothing may hold an
 * access token does not carry over: that rule exists because authentik's tokens
 * live five minutes, and `performActionWithFreshTokens` is how you avoid holding
 * a stale one. Here freshness has no meaning. The token still lives in the
 * encrypted [TokenStore] and nowhere else.
 */
class IndicoAuthManager(context: Context) {

    private val appContext = context.applicationContext

    /**
     * Its own store with its own Keystore key, so unlinking Indico cannot
     * disturb the authentik session and vice versa.
     */
    private val tokenStore = TokenStore(
        appContext,
        prefsName = "indico",
        keyAlias = "tw.stsa.membership.indico",
    )

    private val authService = AuthorizationService(appContext)

    /**
     * Whether the member has authorized the app against Indico. Drives whether
     * the ticket UI offers to link or goes straight to fetching.
     */
    var isLinked by mutableStateOf(false)
        private set
    var isBusy by mutableStateOf(false)
        private set

    private var authState: AuthState? = null

    init {
        restore()
    }

    // MARK: - Linking

    /**
     * Builds the intent that opens the authorization page.
     *
     * Called at the point the member asks for something that needs it, not at
     * sign-in — see the note in `TicketStore`.
     *
     * The redirect goes to the https bridge, which 302s to
     * `tw.stsa.membership://callback`; AppAuth's own receiver activity is
     * already registered for that scheme by the `appAuthRedirectScheme` manifest
     * placeholder, so the response comes back through the activity result exactly
     * as the authentik flow's does.
     */
    fun authorizationIntent(): Intent {
        isBusy = true
        try {
            // The standard builder derives a PKCE code_verifier and an S256
            // code_challenge on its own. Do not call setCodeVerifier(null) —
            // that turns PKCE off, and this client is public.
            val request = AuthorizationRequest.Builder(
                IndicoAuthConfiguration.serviceConfiguration,
                IndicoAuthConfiguration.CLIENT_ID,
                ResponseTypeValues.CODE,
                IndicoAuthConfiguration.REDIRECT_URI,
            ).setScopes(IndicoAuthConfiguration.SCOPES).build()

            return authService.getAuthorizationRequestIntent(request)
        } catch (error: Throwable) {
            isBusy = false
            throw error
        }
    }

    /** Exchanges the authorization code for the Indico token. */
    suspend fun completeAuthorization(data: Intent?) {
        isBusy = true
        try {
            val intent = data ?: throw UserCancelledException()

            val response = AuthorizationResponse.fromIntent(intent)
            val failure = AuthorizationException.fromIntent(intent)
            if (response == null) throw failure ?: linkError(R.string.error_token_unavailable)

            val state = AuthState(response, failure)
            state.update(exchange(response), null)
            adopt(state)

            logLinkResult(state)
        } finally {
            isBusy = false
        }
    }

    /** Called when the launcher returns without ever starting the flow. */
    fun abandonAuthorization() {
        isBusy = false
    }

    /**
     * Drops the Indico token. Local-only, like [AuthManager.logout] — the
     * authorization itself is revoked by the member from Indico's own settings,
     * which is the only place that can actually do it.
     */
    fun unlink() {
        tokenStore.clear()
        authState = null
        isLinked = false
    }

    // MARK: - Tokens

    /**
     * The Indico bearer token, or an error if the account is not linked.
     *
     * Read straight off the stored state rather than through
     * `performActionWithFreshTokens`. That call would ask AppAuth whether the
     * token is fresh and, on a token carrying `expires_in: 0`, decide it is not
     * and try to redeem a refresh token Indico never issued — turning a
     * perfectly good permanent token into a hard failure.
     */
    fun token(): String =
        authState?.accessToken ?: throw linkError(R.string.error_indico_not_linked)

    fun authorizationHeaders(): Map<String, String> =
        mapOf("Authorization" to "Bearer ${token()}")

    // MARK: - Persistence

    private suspend fun adopt(state: AuthState) {
        authState = state
        isLinked = state.accessToken != null
        persist(state)
    }

    private suspend fun persist(state: AuthState) {
        val payload = state.jsonSerializeString()
        withContext(Dispatchers.IO) { tokenStore.write(payload) }
    }

    private fun restore() {
        val payload = tokenStore.read() ?: return
        val state = runCatching { AuthState.jsonDeserialize(payload) }.getOrNull() ?: return

        authState = state
        isLinked = state.accessToken != null
    }

    private suspend fun exchange(response: AuthorizationResponse): TokenResponse =
        suspendCancellableCoroutine { continuation ->
            authService.performTokenRequest(response.createTokenExchangeRequest()) { tokens, error ->
                if (tokens != null) {
                    continuation.resume(tokens)
                } else {
                    continuation.resumeWithException(
                        error ?: linkError(R.string.error_token_unavailable)
                    )
                }
            }
        }

    private fun linkError(resource: Int, vararg args: Any): Exception =
        IllegalStateException(appContext.getString(resource, *args))

    // MARK: - Verification logging

    private fun logLinkResult(state: AuthState) {
        if (!BuildConfig.DEBUG) return

        // `expires_in` is the one unknown in this flow. Indico's model says its
        // tokens never expire, but what authlib actually puts in the response is
        // what decides whether AppAuth would ever try to refresh. Print it once
        // rather than guessing.
        Log.d(
            TAG,
            """
            ── account linked ──────────────────────────────
            scopes granted:  ${state.scope ?: "none reported"}
            refresh token:   ${if (state.refreshToken != null) "YES — unexpected, Indico issues none" else "no (expected)"}
            access expires:  ${state.accessTokenExpirationTime?.toString() ?: "never (expected)"}
            ────────────────────────────────────────────────
            """.trimIndent(),
        )
    }

    private companion object {
        const val TAG = "Indico"
    }
}
