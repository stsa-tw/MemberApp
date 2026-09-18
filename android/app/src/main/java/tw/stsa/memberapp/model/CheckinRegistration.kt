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
 * schema returns a good deal more — pricing, the whole submitted form — but 報到
 * needs only enough to tell a worker who is standing in front of them, what the
 * organiser marked them as, and whether they have already been through.
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
    @SerialName("tags") private val tagsRaw: List<RegistrationTag> = emptyList(),
    @SerialName("checked_in_dt") private val checkedInRaw: String? = null,
    @SerialName("checkin_secret") private val checkinSecretRaw: String? = null,
) {
    /**
     * The organiser's own marks on this registration.
     *
     * Indico sorts them by title before it sends them, so the order is left
     * alone. An untitled one is dropped rather than drawn as an empty chip,
     * which reads as a rendering bug rather than as the empty tag it is.
     */
    val tags: List<RegistrationTag>
        get() = tagsRaw.filter { it.title.isNotBlank() }

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
     * Withdrawn or rejected: still on Indico's list, and not somebody a door is
     * waiting for.
     *
     * Indico draws the same line in the same place — `active_registration_count`
     * is every registration that is not one of these two — so leaving them out
     * of a count here is what makes it mean the same thing as the number on
     * Indico's own management page.
     */
    val isCancelled: Boolean
        get() = state == State.WITHDRAWN || state == State.REJECTED

    /**
     * Whether this registrant answers to what a 幹部 typed.
     *
     * Name, email *and* tags. The first two because a worker reading a name off
     * a screen and one reading an address back to a member are the same errand;
     * tags because the other question a desk asks of a list is "who is on the
     * coach", and the organiser already answered it by tagging them.
     *
     * An empty needle matches everyone, so a search field nobody has typed into
     * hides nobody. iOS's `CheckinRegistration.matches(_:)` is the same rule.
     */
    fun matches(needle: String): Boolean {
        val wanted = needle.trim().lowercase()
        if (wanted.isEmpty()) return true
        return fullName.lowercase().contains(wanted) ||
            email.lowercase().contains(wanted) ||
            tags.any { it.title.lowercase().contains(wanted) }
    }

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

        /**
         * The order a roster reads in, on every screen that draws one.
         *
         * Not checked in first — the people a door is still waiting for —
         * alphabetical inside each group so a name can be found by eye, and
         * anyone who withdrew at the very bottom: kept visible, because "where
         * did they go" is a question the list should answer, but they are
         * nobody's next arrival. iOS's `isOrderedBefore(_:_:)` sorts the same.
         */
        val ROSTER_ORDER: Comparator<CheckinRegistration> =
            compareBy<CheckinRegistration> { it.isCancelled }
                .thenBy { it.checkedIn }
                .thenBy { it.fullName }

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
 * A tag a manager has put on a registration, as Indico's `RegistrationTag`.
 *
 * Read here and never written: the check-in API hands tags over with the
 * registration and has no endpoint that changes them, which is the right way
 * round. A tag is the organiser's note to the door — 素食, 講者, 待補款 — and the
 * desk is who needs to read it, not who decides it.
 */
@Serializable
data class RegistrationTag(
    val id: Int,
    val title: String = "",
    /**
     * A Semantic UI colour *name* — `red`, `teal`, `grey` — not a hex value,
     * whatever Indico's own column comment says: the field behind it is a
     * `SUIColorPickerField`, whose choices are `get_sui_colors()`.
     */
    val color: String = "",
)

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
