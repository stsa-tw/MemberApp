package tw.stsa.memberapp.feature.card

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import tw.stsa.memberapp.R
import tw.stsa.memberapp.auth.AuthManager
import java.time.Instant
import kotlin.time.Duration.Companion.seconds

/**
 * Fetches and keeps fresh the code behind the member card's QR.
 *
 * The server mints a new code per request and stores it in Redis for 300
 * seconds (`CODE_TTL` in MembershipAPI). The web card re-fetches every 250s to
 * stay inside that window; this does the same, but only while the card is on
 * screen — there is no reason to hold a live code in the user's pocket.
 */
class MembershipCodeStore(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    var payload by mutableStateOf<String?>(null)
        private set
    var issuedAt by mutableStateOf<Instant?>(null)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set

    private var refreshJob: Job? = null

    val expiresAt: Instant? get() = issuedAt?.plusSeconds(LIFETIME_SECONDS)

    /** True once the code the user is showing can no longer be validated. */
    fun hasExpired(at: Instant): Boolean {
        val expiry = expiresAt ?: return false
        return !at.isBefore(expiry)
    }

    // MARK: - Lifecycle

    /** Fetches immediately, then keeps refreshing until [stop]. */
    fun start(auth: AuthManager) {
        stop()
        refreshJob = scope.launch {
            while (isActive) {
                refresh(auth)
                delay(REFRESH_INTERVAL_SECONDS.seconds)
            }
        }
    }

    fun stop() {
        refreshJob?.cancel()
        refreshJob = null
    }

    suspend fun refresh(auth: AuthManager) {
        isRefreshing = true
        try {
            // Goes through performActionWithFreshTokens, so an access token
            // older than five minutes is renewed before this call rather than
            // 401ing.
            val response = auth.authorizedGet(ENDPOINT)
            if (response.status != 200) {
                errorMessage = message(response.status, response.body)
                return
            }
            payload = PREFIX + json.decodeFromString(CodeResponse.serializer(), response.body).code
            issuedAt = Instant.now()
            errorMessage = null
        } catch (error: Exception) {
            // The previous code is deliberately kept: it may still be inside its
            // 300s window, and a card that blanks out on a flaky connection is
            // worse than one showing a code that might still scan.
            errorMessage = error.message ?: error.javaClass.simpleName
        } finally {
            isRefreshing = false
        }
    }

    private fun message(status: Int, body: String): String {
        val detail = body.take(120)
        return when (status) {
            401 -> context.getString(R.string.error_code_401, detail)
            403 -> context.getString(R.string.error_code_403, detail)
            else -> context.getString(R.string.error_code_server, status, detail)
        }
    }

    @Serializable
    private data class CodeResponse(val code: String)

    companion object {
        /** MembershipAPI's `CODE_TTL`. After this the code is dead server-side. */
        const val LIFETIME_SECONDS = 300L

        /** Matches the web card's cadence — comfortably inside [LIFETIME_SECONDS]. */
        const val REFRESH_INTERVAL_SECONDS = 250L

        /** The scanner rejects anything not carrying this prefix. */
        private const val PREFIX = "stsa$"
        private const val ENDPOINT = "https://idms.stsa.tw/membership/api/get_code"

        private val json = Json { ignoreUnknownKeys = true }
    }
}
