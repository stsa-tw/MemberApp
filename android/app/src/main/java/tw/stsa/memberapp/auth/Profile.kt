package tw.stsa.memberapp.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The claims returned by authentik's userinfo endpoint.
 *
 * `sub` is the only stable identifier: authentik lets users change their email
 * and username, and `groups` is recomputed on every login. Anything stored
 * locally against a user must be keyed on `sub`.
 */
@Serializable
data class Profile(
    val sub: String,
    val email: String? = null,
    @SerialName("email_verified") val emailVerified: Boolean? = null,
    val name: String? = null,
    @SerialName("given_name") val givenName: String? = null,
    @SerialName("preferred_username") val preferredUsername: String? = null,
    val nickname: String? = null,
    /**
     * Group memberships. Fine for driving UI — hiding a tab, showing a badge —
     * but never a security boundary: it is a self-reported claim from a token
     * this app does not verify. Real authorisation is re-checked server-side
     * against the token signature.
     */
    val groups: List<String> = emptyList(),
) {
    /** Best available human-readable name, in the order authentik populates them. */
    val displayName: String
        get() = name ?: nickname ?: givenName ?: preferredUsername ?: email ?: sub

    /**
     * Derived from the school email domain — the same signal authentik uses to
     * verify student status. There is no school claim, so this is inference,
     * not authority: unknown domains return null rather than a guess.
     */
    val school: String?
        get() {
            val domain = email?.substringAfterLast('@', "")?.lowercase()
            if (domain.isNullOrEmpty()) return null
            return when {
                domain.endsWith("nus.edu.sg") || domain.endsWith("u.nus.edu") -> "NUS"
                domain.endsWith("ntu.edu.sg") || domain.endsWith("e.ntu.edu.sg") -> "NTU"
                domain.endsWith("smu.edu.sg") -> "SMU"
                domain.endsWith("sutd.edu.sg") -> "SUTD"
                else -> null
            }
        }

    /**
     * Drives UI only — see the note on [groups]. Anything that actually matters
     * must be re-checked server-side.
     */
    val isOfficer: Boolean get() = groups.contains("STSA 幹部")

    companion object {
        /**
         * authentik returns more claims than this app models, and adds to them
         * between releases, so unknown keys are skipped rather than throwing.
         */
        val json: Json = Json { ignoreUnknownKeys = true }

        fun decode(body: String): Profile = json.decodeFromString(serializer(), body)
    }
}
