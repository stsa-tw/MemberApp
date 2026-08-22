package tw.stsa.memberapp.auth

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import net.openid.appauth.TokenResponse
import org.json.JSONObject
import tw.stsa.memberapp.BuildConfig
import tw.stsa.memberapp.R
import tw.stsa.memberapp.net.HttpResponse
import tw.stsa.memberapp.net.httpGet
import java.time.Instant
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Raised when the sign-in tab was dismissed rather than completed. */
class UserCancelledException : Exception()

/**
 * OIDC authorization-code + PKCE against the STSA authentik tenant.
 *
 * Design is driven by the 5-minute access-token lifetime: nothing ever holds
 * an access token string. [accessToken] goes through
 * `AuthState.performActionWithFreshTokens` on every call, which returns the
 * cached token if it is still valid and silently redeems the refresh token if
 * it is not. Callers get a token that is good *right now* or an error.
 */
class AuthManager(context: Context) {

    private val appContext = context.applicationContext
    private val tokenStore = TokenStore(appContext)
    private val prefs = appContext.getSharedPreferences(PROFILE_PREFS, Context.MODE_PRIVATE)

    /**
     * Held for the app's lifetime rather than per sign-in: it also services
     * every token refresh, and rebuilding it would drop the Custom Tabs service
     * binding that makes the browser hand-off fast.
     */
    private val authService = AuthorizationService(appContext)

    var isLoggedIn by mutableStateOf(false)
        private set
    var profile by mutableStateOf<Profile?>(null)
        private set
    var isBusy by mutableStateOf(false)
        private set

    private var authState: AuthState? = null
    private var serviceConfiguration: AuthorizationServiceConfiguration? = null

    /**
     * What the diagnostics section needs to show, sampled on demand — the token
     * state lives inside AppAuth's object graph and is not observable.
     */
    data class TokenSnapshot(
        val hasRefreshToken: Boolean,
        val accessTokenExpiry: Instant?,
        val scopesGranted: String?,
    )

    init {
        // Synchronous on purpose. Resolving "is there a session" asynchronously
        // would show the welcome screen for a frame and then replace it, which
        // is the exact flash the single-gate rule exists to prevent.
        restore()
    }

    // MARK: - Session lifecycle

    /**
     * Builds the intent that opens the sign-in page, after discovery.
     *
     * The caller launches it with an activity-result launcher and hands the
     * result back to [completeAuthorization]. There is no `resume(url)` step
     * like iOS has: the redirect lands on AppAuth's own receiver activity,
     * which returns it through that result.
     */
    suspend fun authorizationIntent(): Intent {
        isBusy = true
        try {
            val configuration = discoverConfiguration()

            // The standard builder derives a PKCE code_verifier and an S256
            // code_challenge on its own. Do not call setCodeVerifier(null) —
            // that turns PKCE off, and this client is public.
            val request = AuthorizationRequest.Builder(
                configuration,
                AuthConfiguration.CLIENT_ID,
                ResponseTypeValues.CODE,
                AuthConfiguration.REDIRECT_URI,
            ).setScopes(AuthConfiguration.SCOPES).build()

            // AppAuth drives a Custom Tab here, so the sign-in page runs in the
            // browser's session and participates in SSO. Never swap this for a
            // WebView.
            return authService.getAuthorizationRequestIntent(request)
        } catch (error: Throwable) {
            isBusy = false
            throw error
        }
    }

    /** Exchanges the authorization code and loads the profile. */
    suspend fun completeAuthorization(data: Intent?) {
        isBusy = true
        try {
            // A dismissed Custom Tab comes back as RESULT_CANCELED with no data.
            val intent = data ?: throw UserCancelledException()

            val response = AuthorizationResponse.fromIntent(intent)
            val failure = AuthorizationException.fromIntent(intent)
            if (response == null) throw failure ?: authError(R.string.error_token_unavailable)

            val state = AuthState(response, failure)
            val tokens = exchange(response)
            state.update(tokens, null)
            adopt(state)

            val (fetched, rawUserinfo) = fetchProfile()
            profile = fetched
            cache(fetched)

            logLoginResult(rawUserinfo, state)
        } finally {
            isBusy = false
        }
    }

    /** Called when the sign-in launcher returns without ever starting the flow. */
    fun abandonAuthorization() {
        isBusy = false
    }

    /**
     * Drops every local credential.
     *
     * Deliberately local-only. Because the flow runs in the shared browser
     * session, the authentik session cookie survives — the next sign-in may
     * complete without a prompt. If you need to end the IdP session too, that
     * is an RP-initiated logout against the discovery document's
     * `end_session_endpoint`.
     */
    fun logout() {
        val sub = profile?.sub ?: prefs.getString(SUBJECT_KEY, null)
        prefs.edit {
            if (sub != null) remove(profileKey(sub))
            remove(SUBJECT_KEY)
        }
        tokenStore.clear()

        authState = null
        profile = null
        isLoggedIn = false
    }

    // MARK: - Tokens

    /**
     * The only supported way to get an access token.
     *
     * Never store the return value. Access tokens live 5 minutes; call this
     * again for the next request and let AppAuth decide whether a refresh is
     * needed.
     */
    suspend fun accessToken(): String {
        val state = authState ?: throw authError(R.string.error_not_authenticated)

        val token = try {
            suspendCancellableCoroutine<String> { continuation ->
                state.performActionWithFreshTokens(authService) { accessToken, _, error ->
                    when {
                        error != null -> continuation.resumeWithException(error)
                        accessToken != null -> continuation.resume(accessToken)
                        else -> continuation.resumeWithException(
                            authError(R.string.error_token_unavailable)
                        )
                    }
                }
            }
        } catch (error: Throwable) {
            // A session dying is ordinary: authentik rotates refresh tokens, they
            // expire after 30 days, and they can be revoked from the account page.
            // What is not ordinary is what used to happen next — this method threw
            // before it could update [isLoggedIn], so the app stayed on the
            // signed-in screen with a session that could never work again, showing
            // a raw OAuth error and a Retry button that could not succeed. The only
            // way out was to find 登出 in 設定.
            //
            // AppAuth has already folded a permanent OAuth failure into the state,
            // so it can be asked.
            if (state.authorizationException != null) {
                withContext(Dispatchers.Main) { logout() }
                throw authError(R.string.error_session_expired)
            }

            // Transient failure — a rotation may still have landed before it, so
            // keep whatever AppAuth wrote rather than leaving a superseded refresh
            // token in the store.
            persist(state)
            throw error
        }

        // A refresh rotates the token response (and on authentik, often the
        // refresh token too), so write the updated state back.
        persist(state)
        withContext(Dispatchers.Main) { isLoggedIn = state.isAuthorized }

        return token
    }

    /**
     * Builds a request carrying a token that is fresh at the moment of the call.
     * Use this for every outbound API call rather than holding a token.
     */
    suspend fun authorizedGet(url: String): HttpResponse =
        httpGet(url, mapOf("Authorization" to "Bearer ${accessToken()}"))

    /**
     * Renews the access token if it has lapsed, so the next request does not
     * pay for a token exchange first.
     *
     * Called when the app comes to the foreground — not on a timer. An access
     * token is only needed at the moment of a request, and
     * `performActionWithFreshTokens` already renews one transparently, so
     * polling would spend battery and rotate refresh tokens for nothing.
     */
    suspend fun refreshIfNeeded() {
        if (!isLoggedIn) return
        runCatching { accessToken() }

        // The encrypted blob survives an app update but the cached claims can be
        // cleared independently, so a restored session may have no idea who the
        // member is. Re-fetch rather than showing an account screen with blank
        // fields.
        if (profile == null) {
            runCatching { fetchProfile() }.getOrNull()?.let { (fetched, _) ->
                profile = fetched
                cache(fetched)
            }
        }
    }

    fun snapshot(): TokenSnapshot = TokenSnapshot(
        hasRefreshToken = authState?.refreshToken != null,
        accessTokenExpiry = authState?.accessTokenExpirationTime?.let(Instant::ofEpochMilli),
        scopesGranted = authState?.scope,
    )

    // MARK: - Discovery

    private suspend fun discoverConfiguration(): AuthorizationServiceConfiguration {
        serviceConfiguration?.let { return it }

        val configuration = suspendCancellableCoroutine { continuation ->
            AuthorizationServiceConfiguration.fetchFromIssuer(
                AuthConfiguration.ISSUER
            ) { fetched, error ->
                if (fetched != null) {
                    continuation.resume(fetched)
                } else {
                    continuation.resumeWithException(
                        error ?: authError(R.string.error_token_unavailable)
                    )
                }
            }
        }

        serviceConfiguration = configuration
        return configuration
    }

    private suspend fun exchange(response: AuthorizationResponse): TokenResponse =
        suspendCancellableCoroutine { continuation ->
            authService.performTokenRequest(response.createTokenExchangeRequest()) { tokens, error ->
                if (tokens != null) {
                    continuation.resume(tokens)
                } else {
                    continuation.resumeWithException(
                        error ?: authError(R.string.error_token_unavailable)
                    )
                }
            }
        }

    // MARK: - Userinfo

    /**
     * Returns the decoded profile plus the raw body, so the caller can log the
     * exact claim set authentik issued.
     */
    private suspend fun fetchProfile(): Pair<Profile, String> {
        val configuration = discoverConfiguration()
        val endpoint = configuration.discoveryDoc?.userinfoEndpoint
            ?: throw authError(R.string.error_no_userinfo_endpoint)

        val response = authorizedGet(endpoint.toString())
        if (response.status != 200) {
            throw authError(R.string.error_userinfo_failed, response.status, response.body)
        }

        return Profile.decode(response.body) to response.body
    }

    // MARK: - Persistence

    private suspend fun adopt(state: AuthState) {
        authState = state
        isLoggedIn = state.isAuthorized
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
        isLoggedIn = state.isAuthorized

        val sub = prefs.getString(SUBJECT_KEY, null) ?: return
        val cached = prefs.getString(profileKey(sub), null) ?: return
        profile = runCatching { Profile.decode(cached) }.getOrNull()
    }

    /**
     * Profile claims are not credentials, so they live in plain preferences —
     * but keyed on `sub`, never on email or username.
     */
    private fun cache(profile: Profile) {
        val encoded = runCatching { Profile.json.encodeToString(Profile.serializer(), profile) }
            .getOrNull() ?: return
        prefs.edit {
            putString(profileKey(profile.sub), encoded)
            putString(SUBJECT_KEY, profile.sub)
        }
    }

    // MARK: - Errors

    private fun authError(resource: Int, vararg args: Any): Exception =
        IllegalStateException(appContext.getString(resource, *args))

    // MARK: - Verification logging

    private fun logLoginResult(rawUserinfo: String, state: AuthState) {
        if (!BuildConfig.DEBUG) return

        val pretty = runCatching { JSONObject(rawUserinfo).toString(2) }.getOrDefault(rawUserinfo)
        val refresh = if (state.refreshToken != null) {
            "YES"
        } else {
            "NO — check that offline_access is granted for this application in authentik"
        }
        val expiry = state.accessTokenExpirationTime?.let(Instant::ofEpochMilli)?.toString()
            ?: "unknown"

        Log.d(
            TAG,
            """
            ── login succeeded ────────────────────────────────
            refresh token returned: $refresh
            access token expires:   $expiry
            scopes granted:         ${state.scope ?: "none reported"}
            raw userinfo response:
            $pretty
            ─────────────────────────────────────────────────────
            """.trimIndent(),
        )
    }

    companion object {
        private const val TAG = "Auth"
        private const val PROFILE_PREFS = "profile"
        private const val SUBJECT_KEY = "auth.currentSubject"

        private fun profileKey(sub: String) = "auth.profile.$sub"

        /**
         * True when the person dismissed the sign-in page themselves. Callers
         * should treat this as "nothing happened", not as a failure worth an
         * alert.
         */
        fun isUserCancellation(error: Throwable): Boolean = when (error) {
            is UserCancelledException -> true
            is AuthorizationException ->
                error.type == AuthorizationException.TYPE_GENERAL_ERROR &&
                    error.code == AuthorizationException.GeneralErrors.USER_CANCELED_AUTH_FLOW.code
            else -> false
        }
    }
}
