package tw.stsa.memberapp.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID

/**
 * One registration as the Indico check-in API reports it.
 *
 * Source: `CheckinRegistrationSchema` in
 * `indico/modules/events/registration/schemas.py`, confirmed on v3.3.13. The
 * schema returns a good deal more — pricing, tags, the whole submitted form —
 * but 報到 needs only enough to tell a worker who is standing in front of them
 * and whether they have already been through.
 */
@Serializable
data class CheckinRegistration(
    val id: Int,
    @SerialName("regform_id") val regformId: Int,
    @SerialName("event_id") val eventId: Int,
    @SerialName("full_name") val fullName: String,
    val email: String,
    @Serializable(with = RegistrationStateSerializer::class)
    val state: State = State.UNKNOWN,
    @SerialName("checked_in") val checkedIn: Boolean = false,
    @SerialName("checked_in_dt") private val checkedInRaw: String? = null,
    @SerialName("checkin_secret") private val checkinSecretRaw: String? = null,
) {
    /**
     * marshmallow emits ISO 8601 with an offset, and includes fractional
     * seconds only when the stored value has them — [OffsetDateTime] takes
     * both spellings.
     */
    val checkedInAt: Instant?
        get() = checkedInRaw?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }

    /**
     * Indico's `ticket_uuid`. Same value a ticket QR carries, which is what
     * makes a scanned ticket resolvable without knowing the event first.
     */
    val checkinSecret: UUID?
        get() = checkinSecretRaw?.let { runCatching { UUID.fromString(it) }.getOrNull() }

    /**
     * Whether this person should be admitted at all. A withdrawn or rejected
     * registration still appears in the list, and checking one in would record
     * attendance for someone who is not supposed to be there.
     */
    val isAdmissible: Boolean
        get() = state == State.COMPLETE || state == State.UNPAID

    /**
     * `RegistrationState` in
     * `indico/modules/events/registration/models/registrations.py`. Serialised
     * by name, so [wire] holds the values verbatim.
     */
    enum class State(val wire: String) {
        COMPLETE("complete"),
        PENDING("pending"),
        REJECTED("rejected"),
        WITHDRAWN("withdrawn"),
        UNPAID("unpaid"),

        /**
         * Indico may add states; an unknown one must not fail the whole list
         * and strand a worker at the door.
         */
        UNKNOWN("unknown"),
        ;

        companion object {
            fun from(raw: String): State = entries.firstOrNull { it.wire == raw } ?: UNKNOWN
        }
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun decode(body: String): CheckinRegistration = json.decodeFromString(serializer(), body)

        fun decodeList(body: String): List<CheckinRegistration> =
            json.decodeFromString(ListSerializer(serializer()), body)
    }
}

private object RegistrationStateSerializer : KSerializer<CheckinRegistration.State> {
    override val descriptor = PrimitiveSerialDescriptor("state", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): CheckinRegistration.State =
        CheckinRegistration.State.from(decoder.decodeString())

    override fun serialize(encoder: Encoder, value: CheckinRegistration.State) =
        encoder.encodeString(value.wire)
}

/**
 * One registration form in an event, as the check-in API reports it.
 *
 * An event can carry several. When it does the worker has to pick, because a
 * registration only exists inside one of them.
 */
@Serializable
data class CheckinRegForm(
    val id: Int,
    @SerialName("event_id") val eventId: Int,
    val title: String = "",
    @SerialName("is_open") val isOpen: Boolean = false,
    @SerialName("registration_count") val registrationCount: Int = 0,
    @SerialName("checked_in_count") val checkedInCount: Int = 0,
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun decodeList(body: String): List<CheckinRegForm> =
            json.decodeFromString(ListSerializer(serializer()), body)
    }
}
