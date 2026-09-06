package tw.stsa.memberapp.feature.checkin

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import tw.stsa.memberapp.net.HttpResponse
import tw.stsa.memberapp.net.httpSend

/** Who a member card's code belongs to, per MembershipAPI. */
@Serializable
data class MemberIdentity(
    val name: String,
    val email: String,
    val username: String,
)

/**
 * Turns the code behind a member card into the person holding it.
 *
 * `validate_code` takes no credentials — anyone who can reach `idms.stsa.tw`
 * and holds a live code can resolve it — and, unlike `get_code`, it neither
 * consumes the code nor shortens its life: MembershipAPI reads it back out of
 * Redis with `GET`, so it stays valid for its full `CODE_TTL` of 300 seconds
 * and answers any number of times. Two consequences worth knowing:
 *
 * - A re-scan after a bad angle just works. Nothing here needs to be careful
 *   about spending a code.
 * - A photographed card is a working credential until it expires. The card
 *   rotates every 250s, so the window is small, but it is why 報到 shows the
 *   member's name for the worker to check against the person in front of them
 *   rather than checking anyone in silently.
 */
class MemberCodeResolver(
    private val send: suspend (String, String, Map<String, String>, String?) -> HttpResponse = ::httpSend,
) {
    /**
     * Throws [CheckinError.ExpiredMemberCode] for a code Redis no longer has —
     * MembershipAPI answers 400, not 404, for both expired and never-valid.
     */
    suspend fun resolve(code: String): MemberIdentity {
        val response = send(
            "$BASE_URL/validate_code/$code",
            "GET",
            mapOf("Accept" to "application/json"),
            null,
        )
        if (response.status == 400) throw CheckinError.ExpiredMemberCode
        if (response.status != 200) throw CheckinError.of(response.status, response.body)

        val envelope = runCatching { json.decodeFromString(Envelope.serializer(), response.body) }
            .getOrElse { throw CheckinError.MalformedResponse }

        return envelope.token?.takeIf { envelope.valid } ?: throw CheckinError.ExpiredMemberCode
    }

    /** MembershipAPI wraps the identity as `{"token": {...}, "valid": true}`. */
    @Serializable
    private data class Envelope(val valid: Boolean = false, val token: MemberIdentity? = null)

    companion object {
        private const val BASE_URL = "https://idms.stsa.tw/membership/api"

        private val json = Json { ignoreUnknownKeys = true }
    }
}
