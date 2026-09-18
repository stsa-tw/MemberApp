package tw.stsa.memberapp.feature.checkin

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
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

    /**
     * How many check-ins this app has written for an event, used only to tell a
     * refetch that started earlier that it is now out of date.
     */
    private val writes = mutableMapOf<String, Int>()

    /**
     * The events with a roster fetch already in flight, so a poll coming round
     * again does not start a second one behind it.
     */
    private val inFlight = mutableSetOf<String>()

    var isLoadingRoster by mutableStateOf(false)
        private set

    /** True while a check-in written from the roster is in flight. */
    var isSubmitting by mutableStateOf(false)
        private set

    fun access(eventId: String): Access = access[eventId] ?: Access.UNKNOWN

    fun forms(eventId: String): List<CheckinRegForm> = forms[eventId].orEmpty()

    fun registrations(eventId: String): List<CheckinRegistration> = rosters[eventId].orEmpty()

    /** One form's registrants — the list a door actually works from. */
    fun registrations(eventId: String, formId: Int): List<CheckinRegistration> =
        registrations(eventId).filter { it.regformId == formId }

    /**
     * How many have arrived, out of how many are coming — for one form.
     *
     * Per form because an event's forms are separate lists: 烤場集合 runs a 報名表
     * and a 遊覽車報名表, and a member on both is one person holding two
     * registrations rather than a duplicate of themselves. Added together they
     * made a denominator no door could reach.
     *
     * Read from the roster once there is one and from the probe's own totals
     * until then. That order matters after a scan: the probe's numbers are a
     * snapshot from before the door opened, while the roster is folded forward
     * by [update] as people are checked in.
     *
     * Withdrawn and rejected registrations are in neither half once the roster
     * lands — nobody is waiting for them at a door. Indico's own
     * `registration_count` is `existing_registrations_count`, which counts them
     * and counts accompanying persons as seats, so the number can shift a little
     * when the list arrives and replaces it.
     */
    fun checkedInCount(eventId: String, formId: Int): Int =
        expected(eventId, formId)?.count { it.checkedIn }
            ?: forms(eventId).firstOrNull { it.id == formId }?.checkedInCount
            ?: 0

    fun registeredCount(eventId: String, formId: Int): Int =
        expected(eventId, formId)?.size
            ?: forms(eventId).firstOrNull { it.id == formId }?.registrationCount
            ?: 0

    /** The whole event, for the one-line summary on the event page. */
    fun checkedInCount(eventId: String): Int =
        expected(eventId)?.count { it.checkedIn } ?: forms(eventId).sumOf { it.checkedInCount }

    fun registeredCount(eventId: String): Int =
        expected(eventId)?.size ?: forms(eventId).sumOf { it.registrationCount }

    private fun expected(eventId: String): List<CheckinRegistration>? =
        rosters[eventId]?.filter { !it.isCancelled }

    private fun expected(eventId: String, formId: Int): List<CheckinRegistration>? =
        rosters[eventId]?.filter { it.regformId == formId && !it.isCancelled }

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
        fetchRoster(eventId, indico)
    }

    /**
     * Asks Indico again, for the door that is not the only one.
     *
     * The count on this phone moved when *this* phone recorded a check-in, and
     * that was all it knew: a second 幹部 on a second phone, or anyone using
     * Indico's own app, moved a number this one never saw. The list was fetched
     * once per launch and believed for the rest of the event.
     */
    suspend fun refreshRoster(eventId: String, indico: IndicoAuthManager) {
        fetchRoster(eventId, indico)
    }

    /**
     * Keeps one event's roster current for as long as the calling coroutine
     * lives.
     *
     * A loop the caller owns rather than a timer the store owns: a screen going
     * away, or the app leaving the foreground, cancels the coroutine and the
     * polling stops with it. Nothing re-asks Indico about a door nobody is
     * standing at.
     *
     * Asks before it waits, because the caller restarts this every time the app
     * returns to the foreground — and a phone that has been in a pocket for ten
     * minutes is holding the worst list in the building. Waiting first would
     * show it for five more seconds to somebody already reading it. The extra
     * request this costs on the way in is usually not made at all: every screen
     * here also fetches on appear, and [inFlight] folds the two together.
     */
    suspend fun autoRefresh(eventId: String, indico: IndicoAuthManager) {
        while (true) {
            fetchRoster(eventId, indico)
            delay(REFRESH_INTERVAL_MS)
        }
    }

    private suspend fun fetchRoster(eventId: String, indico: IndicoAuthManager) {
        val numericId = eventId.toIntOrNull() ?: return
        val known = forms(eventId).ifEmpty { return }

        // One fetch per event at a time. Polling on a venue's wifi will sooner
        // or later come round before the last request landed, and stacking them
        // buys nothing: they all ask the same question, and the slowest would
        // answer it last.
        if (!inFlight.add(eventId)) return

        // The flag behind a first-load spinner, and nothing else: once there is
        // a list on screen, a refresh must not take it away and put a spinner
        // there — least of all one arriving every five seconds.
        val isFirstLoad = !rosters.containsKey(eventId)
        if (isFirstLoad) isLoadingRoster = true

        // Read before the requests go out and compared after they come back: a
        // check-in recorded while this was in flight is newer than anything the
        // response can contain, and letting a stale list land on top of it would
        // take the person back off the screen they were just admitted on.
        val generation = writes[eventId] ?: 0

        try {
            val client = IndicoCheckinClient(indico)
            var isComplete = true
            val entries = known.flatMap { form ->
                try {
                    client.registrations(numericId, form.id)
                } catch (cancelled: CancellationException) {
                    // Routine now that this is polled: a screen going away or
                    // the app backgrounding cancels mid-request. Swallowed as an
                    // ordinary failure it would read as a venue with no wifi,
                    // and on a first load store the empty list that produced.
                    throw cancelled
                } catch (error: Exception) {
                    isComplete = false
                    emptyList()
                }
            }

            if ((writes[eventId] ?: 0) != generation) return

            // A refresh that could not read every form must not shorten a list
            // the door is working from — the venue's wifi dropping should cost
            // the count its freshness, not its rows.
            if (!isComplete && !isFirstLoad) return

            rosters[eventId] = entries
        } finally {
            inFlight.remove(eventId)
            if (isFirstLoad) isLoadingRoster = false
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
        writes[eventId] = (writes[eventId] ?: 0) + 1
        val current = rosters[eventId] ?: return
        rosters[eventId] = current.map { if (it.id == registration.id) registration else it }
    }

    /**
     * Records attendance, or takes it back, from the roster rather than a door.
     *
     * [CheckinSession] does this for a scan; this is the same write for the list
     * on 幹部功能, where a name is tapped instead. Deliberately the same flag and
     * the same endpoint — a check-in made from the list is not a second kind of
     * check-in, and Indico cannot tell them apart.
     *
     * A withdrawn registration can be *un*-checked-in but not checked in: the
     * one thing this is for is correcting somebody who should never have been
     * marked as arrived.
     */
    suspend fun setCheckedIn(
        registration: CheckinRegistration,
        checkedIn: Boolean,
        indico: IndicoAuthManager,
    ): CheckinRegistration {
        if (!indico.canRecordCheckin) throw CheckinError.NeedsAuthorization
        if (checkedIn && !registration.isAdmissible) {
            throw CheckinError.NotAdmissible(registration.fullName)
        }
        isSubmitting = true
        try {
            val updated = IndicoCheckinClient(indico).checkIn(registration, checkedIn)
            update(updated)
            return updated
        } finally {
            isSubmitting = false
        }
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
        writes.clear()
        inFlight.clear()
    }

    companion object {
        /**
         * How often a roster on screen re-asks Indico.
         *
         * Five seconds because of what the staleness actually costs: a 幹部 waves
         * somebody through believing they are the first to admit them, and no
         * screen anywhere will later disagree. It is one request per
         * registration form — two for 烤場集合 — and only while a 幹部 is looking
         * at the list or standing at the door, so the traffic is a handful of
         * phones for the hours an event is being run, not every member in the
         * app. iOS's `CheckinStore.refreshInterval` is the same number.
         */
        const val REFRESH_INTERVAL_MS = 5_000L
    }
}
