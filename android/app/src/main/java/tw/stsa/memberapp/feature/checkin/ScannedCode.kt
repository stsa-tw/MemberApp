package tw.stsa.memberapp.feature.checkin

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.ByteBuffer
import java.util.Base64
import java.util.UUID

/**
 * A QR code read by the 報到 scanner, once it has been recognised.
 *
 * The scanner accepts two unrelated formats, which is the point of it: an
 * Indico ticket and an STSA member card. They reach a registration by different
 * routes — a ticket carries that registration's own secret, while a member card
 * only identifies a person and still has to be matched against the event's
 * registrant list.
 *
 * Recognising a code is deliberately separate from resolving one: this type
 * touches no network and is the part worth pinning in tests.
 */
sealed interface ScannedCode {

    /**
     * An Indico ticket. Format per `get_ticket_qr_code_data` in
     * `indico/modules/events/registration/util.py`, confirmed on v3.3.13.
     */
    data class Ticket(
        /** Indico's `ticket_uuid`, named `checkin_secret` on the wire. */
        val checkinSecret: UUID,

        /**
         * The Indico instance that issued the ticket, without a scheme.
         * Checked before use: a ticket from another Indico is not ours to check
         * in, and would 404 against our own API anyway.
         */
        val host: String,

        /**
         * Set only on a ticket issued to an accompanying person, who has no
         * registration of their own. Indico's own app can check these in
         * individually; this app cannot yet, so callers reject them rather than
         * silently checking in the person who brought them.
         */
        val accompanyingPersonId: UUID?,
    ) : ScannedCode

    /**
     * The code behind a member card, with the `stsa$` prefix stripped.
     * Resolved through MembershipAPI's `validate_code`.
     */
    data class MemberCode(val code: String) : ScannedCode

    companion object {
        private const val MEMBER_CODE_PREFIX = "stsa$"

        /** `CODE_LENGTH` in MembershipAPI, drawn from `ascii_letters + digits`. */
        private const val MEMBER_CODE_LENGTH = 20

        /**
         * Bumped by Indico whenever the QR layout changes. An unknown version is
         * refused rather than parsed hopefully: the fields would be in the wrong
         * places and the failure would surface as a wrong person, not an error.
         */
        private const val SUPPORTED_TICKET_VERSION = 2

        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Returns null for anything unrecognised — a URL, a boarding pass, a
         * ticket from a future format version. The caller shows "unrecognised
         * code" rather than guessing.
         */
        fun parse(raw: String): ScannedCode? {
            val text = raw.trim()
            return memberCode(text) ?: ticket(text)
        }

        private fun memberCode(text: String): MemberCode? {
            if (!text.startsWith(MEMBER_CODE_PREFIX)) return null
            val code = text.removePrefix(MEMBER_CODE_PREFIX)
            if (code.length != MEMBER_CODE_LENGTH) return null
            if (!code.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' }) return null
            return MemberCode(code)
        }

        private fun ticket(text: String): Ticket? = runCatching {
            // Plugins may add sibling keys — CERN's site-access plugin adds an
            // ADaMS URL — so read `i` and ignore anything else present.
            val fields = json.parseToJsonElement(text).jsonObject["i"]?.jsonArray ?: return null
            if (fields.size < 3) return null
            if (fields[0].jsonPrimitive.int != SUPPORTED_TICKET_VERSION) return null

            val secret = uuidFromBase64(fields[2].jsonPrimitive.content) ?: return null
            // A fourth element means the ticket belongs to an accompanying person.
            val person = if (fields.size >= 4) uuidFromBase64(fields[3].jsonPrimitive.content) else null

            Ticket(
                checkinSecret = secret,
                host = host(fields[1].jsonPrimitive.content),
                accompanyingPersonId = person,
            )
        }.getOrNull()

        /**
         * Indico base64-encodes the UUID's 16 raw bytes rather than its
         * hyphenated text, purely to keep the QR small enough to scan off a
         * phone screen.
         */
        private fun uuidFromBase64(encoded: String): UUID? = runCatching {
            val bytes = Base64.getDecoder().decode(encoded)
            if (bytes.size != 16) return null
            val buffer = ByteBuffer.wrap(bytes)
            UUID(buffer.long, buffer.long)
        }.getOrNull()

        /**
         * Indico strips `https://` from the URL it writes into the QR to save
         * bytes, but leaves `http://` in place, so handle both.
         */
        private fun host(url: String): String =
            url.removePrefix("https://").removePrefix("http://").trimEnd('/')
    }
}
