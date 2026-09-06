package tw.stsa.memberapp.feature.checkin

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.model.CheckinRegForm
import tw.stsa.memberapp.model.CheckinRegistration

/**
 * The organiser side of an event: whether this account runs it, and who has
 * turned up.
 *
 * The counterpart of iOS's `CheckinStore`, and the layer *outside* the scanner.
 * [CheckinSession] is still what a worker holds at a door — one event, one form,
 * the list in memory for offline matching. This lives for the whole app, because
 * the event page needs the answer before anyone opens a camera.
 *
 * **Asked, not assumed.** The entry to 報到 used to be gated on the `isOfficer`
 * group claim, which answers a different question: a 幹部 is not necessarily a
 * 幹部 *of this event*, so the button appeared for people whose first tap was a
 * 403. Indico decides instead — `/api/checkin/event/<id>/forms/` is
 * `RHManageEventBase`, so a successful call is the permission, and the group
 * claim goes back to being what `Profile.groups` says it is: not a security
 * boundary, and not used as one.
 *
 * **Why the counts are free.** That same probe answers with each form's
 * `registration_count` and `checked_in_count`, so the row can say "12 / 40
 * 已報到" off one cheap request. iOS pulls the whole roster to work the same
 * number out; there is no reason to here, and the roster is left for the screen
 * that actually lists people.
 */
class CheckinStore {

    enum class Access {
        UNKNOWN,
        CHECKING,

        /** This account manages the event and may read its registrations. */
        ALLOWED,
        DENIED,
    }

    private val access = mutableStateMapOf<String, Access>()
    private val forms = mutableStateMapOf<String, List<CheckinRegForm>>()
    private val rosters = mutableStateMapOf<String, List<CheckinRegistration>>()

    var isLoadingRoster by mutableStateOf(false)
        private set

    fun access(eventId: String): Access = access[eventId] ?: Access.UNKNOWN

    fun forms(eventId: String): List<CheckinRegForm> = forms[eventId].orEmpty()

    fun registrations(eventId: String): List<CheckinRegistration> = rosters[eventId].orEmpty()

    /**
     * How many have arrived, out of how many are coming.
     *
     * Read from the roster once there is one and from the probe's own totals
     * until then. That order matters after a scan: the probe's numbers are a
     * snapshot from before the door opened, while the roster is folded forward
     * by [update] as people are checked in.
     */
    fun checkedInCount(eventId: String): Int =
        rosters[eventId]?.count { it.checkedIn } ?: forms(eventId).sumOf { it.checkedInCount }

    fun registeredCount(eventId: String): Int =
        rosters[eventId]?.size ?: forms(eventId).sumOf { it.registrationCount }

    /**
     * Asks Indico whether this account runs the event. Asked once per event per
     * launch: the answer does not change while someone is looking at a screen,
     * and this is on the path of every event anyone opens.
     */
    suspend fun probe(eventId: String, indico: IndicoAuthManager) {
        if (access(eventId) != Access.UNKNOWN || !indico.isLinked) return
        // The check-in API is addressed by numeric id; an event whose id is not
        // one is not an event this API knows.
        val numericId = eventId.toIntOrNull() ?: run {
            access[eventId] = Access.DENIED
            return
        }

        access[eventId] = Access.CHECKING
        try {
            val found = IndicoCheckinClient(indico).regforms(numericId)
            forms[eventId] = found
            access[eventId] = if (found.isNotEmpty()) Access.ALLOWED else Access.DENIED
        } catch (error: CheckinError) {
            // 403 is the ordinary answer for a member who does not staff this
            // event, and it is not worth a message: the row simply is not there.
            access[eventId] = Access.DENIED
        }
    }

    /** The list itself, which only the organiser screen needs. */
    suspend fun loadRoster(eventId: String, indico: IndicoAuthManager) {
        if (rosters.containsKey(eventId)) return
        val numericId = eventId.toIntOrNull() ?: return
        val known = forms(eventId).ifEmpty { return }

        isLoadingRoster = true
        try {
            val client = IndicoCheckinClient(indico)
            rosters[eventId] = known.flatMap { form ->
                runCatching { client.registrations(numericId, form.id) }.getOrDefault(emptyList())
            }
        } finally {
            isLoadingRoster = false
        }
    }

    /**
     * Folds a scan back into the roster, so the count on the way out of the
     * scanner is the count the door just produced rather than the one it started
     * with. [CheckinSession] does the same to its own copy; this is the shared
     * one behind it.
     */
    fun update(registration: CheckinRegistration) {
        val eventId = registration.eventId.toString()
        val current = rosters[eventId] ?: return
        rosters[eventId] = current.map { if (it.id == registration.id) registration else it }
    }

    /**
     * Clears everything. Called from an explicit sign-out, alongside the ticket
     * store — a roster names people, and it should not outlive the account that
     * was allowed to read it.
     */
    fun clear() {
        access.clear()
        forms.clear()
        rosters.clear()
    }
}
