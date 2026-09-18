package tw.stsa.memberapp.feature.checkin

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.model.CheckinRegForm
import tw.stsa.memberapp.model.CheckinRegistration

/**
 * One worker's 報到 session for one registration form: the registrant list, and
 * the rules that turn a scan into a registration.
 *
 * Holding the whole list is deliberate. A member card names a person, not a
 * registration, so it can only be matched locally — and a venue's wifi is the
 * least reliable thing at any event, so the list is fetched once at the door
 * rather than per scan.
 *
 * One session is one *form*, not one event. 烤場集合 runs a 報名表 and a
 * 遊覽車報名表, which hold separate registrations with separate `checked_in`
 * flags — two desks, two lists. The form is chosen on the organiser screen and
 * arrives here as [formId]; this screen used to be handed the event alone and,
 * when it found more than one form, opened with an empty list and turned
 * everybody away.
 */
class CheckinSession(
    val eventId: Int,
    val formId: Int,
    private val indico: IndicoAuthManager,
    private val client: IndicoCheckinClient = IndicoCheckinClient(indico),
    private val members: MemberCodeResolver = MemberCodeResolver(),
) {
    sealed interface Phase {
        object Idle : Phase
        object Loading : Phase
        object Ready : Phase

        /** Signed in to Indico, but not a check-in worker on this event. */
        object Denied : Phase

        data class Failed(val error: CheckinError) : Phase
    }

    var phase by mutableStateOf<Phase>(Phase.Idle)
        private set
    var regforms by mutableStateOf<List<CheckinRegForm>>(emptyList())
        private set
    var regform by mutableStateOf<CheckinRegForm?>(null)
        private set
    var registrations by mutableStateOf<List<CheckinRegistration>>(emptyList())
        private set
    var isSubmitting by mutableStateOf(false)
        private set

    /**
     * How many check-ins this session has written, used only to tell a refresh
     * that started earlier that it is now out of date.
     */
    private var writes = 0

    /**
     * How many are expected at this door, and how many have come through.
     *
     * Withdrawn and rejected registrations are in neither. They stay on Indico's
     * list — `~is_deleted` is the only filter the API applies — but nobody is
     * waiting for them, and counting them made a denominator no door could
     * reach.
     */
    val expectedCount: Int get() = registrations.count { !it.isCancelled }

    val checkedInCount: Int get() = registrations.count { it.checkedIn && !it.isCancelled }

    // MARK: - Loading

    /**
     * Loads the event's forms and then this door's registrants.
     *
     * The forms call is also the permission check: 403 here is the normal answer
     * for a member who is not staffing this event, so it becomes [Phase.Denied]
     * rather than an error banner.
     */
    suspend fun load() {
        phase = Phase.Loading
        try {
            regforms = client.regforms(eventId)
            // The form was chosen before this screen opened. One that is no
            // longer on the event is not something a worker can pick their way
            // out of from behind a camera.
            val chosen = regforms.firstOrNull { it.id == formId }
            if (chosen == null) {
                phase = Phase.Failed(CheckinError.NotFound)
                return
            }
            select(chosen)
        } catch (error: CheckinError) {
            phase = if (error is CheckinError.Forbidden) Phase.Denied else Phase.Failed(error)
        }
    }

    private suspend fun select(form: CheckinRegForm) {
        regform = form
        registrations = client.registrations(eventId, form.id)
        phase = Phase.Ready
    }

    /**
     * Re-asks Indico for this door's list, without disturbing the screen.
     *
     * Deliberately not [load]: that announces [Phase.Loading], which would pull
     * the camera down and put a spinner in its place — every five seconds, while
     * a 幹部 is trying to point it at a QR code. This changes nothing but the
     * list and the count drawn from it.
     *
     * A door that loses its network keeps the list it has. The list is what a
     * member card is matched against, so the wifi going out should cost the
     * count its freshness, not the desk its ability to admit anybody.
     */
    suspend fun refresh() {
        if (phase != Phase.Ready) return
        val form = regform ?: return

        // Read before the request goes out and compared after it comes back: a
        // check-in recorded while this was in flight is newer than anything the
        // response can contain, and letting a stale list land on top of it would
        // take the person back off the screen they were just admitted on.
        val generation = writes
        val fresh = try {
            client.registrations(eventId, form.id)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            return
        }
        if (writes != generation) return
        registrations = fresh
    }

    /**
     * Keeps this door's list current for as long as the calling coroutine lives.
     *
     * The door is the screen that most needs it: it stays open for hours, the
     * other doors do not stop while it is, and without this the count under the
     * viewfinder is the one the screen started with — so a member another 幹部
     * already admitted scans here as a first arrival.
     *
     * Asks before it waits, because the screen restarts this every time the app
     * returns to the foreground, and a phone that has been in a pocket for ten
     * minutes is holding the worst list at the door. On the way in that first
     * call costs nothing: [load] is still running, and [refresh] declines to
     * touch a session that is not yet [Phase.Ready].
     */
    suspend fun autoRefresh() {
        while (true) {
            refresh()
            delay(CheckinStore.REFRESH_INTERVAL_MS)
        }
    }

    // MARK: - Resolving a scan

    /**
     * Turns raw QR text into the registration standing in front of the worker.
     *
     * Throws rather than returning null so every refusal carries its reason: a
     * worker at a door needs to know *why* a code did not work, and "not
     * registered" and "wrong event" call for very different responses.
     */
    suspend fun resolve(raw: String): CheckinRegistration =
        when (val scanned = ScannedCode.parse(raw)) {
            is ScannedCode.Ticket -> resolveTicket(scanned)
            is ScannedCode.MemberCode -> resolveMember(members.resolve(scanned.code))
            null -> throw CheckinError.UnrecognisedCode
        }

    private suspend fun resolveTicket(ticket: ScannedCode.Ticket): CheckinRegistration {
        if (ticket.host != IndicoCheckinClient.HOST) throw CheckinError.ForeignInstance(ticket.host)
        // Indico's own app can check an accompanying person in on their own
        // ticket; this app has no concept of them, and checking in the
        // registrant who brought them would be a quiet lie.
        if (ticket.accompanyingPersonId != null) throw CheckinError.AccompanyingPerson

        // The ticket endpoint is not scoped to an event — Indico resolves the
        // secret globally — so a ticket for another event this worker also
        // staffs would otherwise resolve and check in against the wrong door.
        val registration = client.registration(ticket.checkinSecret)
        if (registration.eventId != eventId) throw CheckinError.WrongEvent

        return requireAdmissible(registration)
    }

    private suspend fun resolveMember(identity: MemberIdentity): CheckinRegistration {
        match(identity.email, registrations)?.let { return requireAdmissible(it) }

        // A miss is worth one more question before it is reported as one. The
        // member who booked the coach as well is standing at the wrong desk, not
        // absent, and telling a worker "not registered" about somebody who very
        // much is registered is how one event's two lists became one confusing
        // one.
        val elsewhere = elsewhere(identity.email)
        throw if (elsewhere.isEmpty()) {
            CheckinError.NotRegistered(identity.name, formTitle)
        } else {
            CheckinError.RegisteredElsewhere(identity.name, elsewhere.map { it.title }, formTitle)
        }
    }

    private val formTitle: String get() = regform?.title.orEmpty()

    /**
     * The event's other forms this address is registered in.
     *
     * One request per other form, and only when a scan has already missed —
     * which is rare, and exactly the moment the answer is worth having. A form
     * that cannot be read is simply not reported; a door that lost its network
     * should say "not registered", not fail.
     */
    private suspend fun elsewhere(email: String): List<CheckinRegForm> =
        regforms.filter { it.id != formId }
            .filter { form ->
                runCatching { match(email, client.registrations(eventId, form.id)) != null }
                    .getOrDefault(false)
            }

    // MARK: - Recording attendance

    /**
     * Records attendance — or takes it back — and folds Indico's answer into the
     * local list, so the running count and any later scan of the same person are
     * right without re-fetching.
     *
     * `checkedIn = false` is the undo, and the same endpoint: Indico clears
     * `checked_in_dt` with the flag, so a mistake at the door leaves no trace of
     * an arrival that did not happen.
     */
    suspend fun checkIn(
        registration: CheckinRegistration,
        checkedIn: Boolean = true,
    ): CheckinRegistration {
        // Reading a roster needs only `read:everything`; writing needs the wider
        // grant, which is asked for on this screen and nowhere else.
        if (!indico.canRecordCheckin) throw CheckinError.NeedsAuthorization
        isSubmitting = true
        try {
            val updated = client.checkIn(registration, checkedIn)
            writes += 1
            registrations = registrations.map { if (it.id == updated.id) updated else it }
            return updated
        } finally {
            isSubmitting = false
        }
    }

    companion object {
        /**
         * Email is the only identifier the two systems share: MembershipAPI
         * reports the authentik account's address, Indico stores whatever the
         * member typed into the registration form. Compared case-insensitively,
         * since Indico lowercases addresses and authentik does not.
         *
         * A member who registered under a different address will not match. They
         * are told so by name, which is recoverable — the worker scans their
         * ticket instead — rather than being reported as an unknown code.
         */
        fun match(email: String, registrations: List<CheckinRegistration>): CheckinRegistration? {
            val wanted = normalised(email)
            if (wanted.isEmpty()) return null

            val matches = registrations.filter { normalised(it.email) == wanted }
            // One form can hold more than one registration for an address:
            // withdrawing and registering again leaves the old row behind, and a
            // manager adding somebody who had already registered is warned
            // rather than stopped. So the choice is made deliberately —
            //
            // - one that is admissible *and* already checked in, so a second
            //   scan of the same person reads 已經報到過 instead of quietly
            //   offering to admit their other copy and counting one arrival
            //   twice;
            // - failing that an admissible one, since a withdrawn leftover is
            //   not the answer to "is this person expected";
            // - failing that the first, so the screen can explain what it found.
            return matches.firstOrNull { it.isAdmissible && it.checkedIn }
                ?: matches.firstOrNull { it.isAdmissible }
                ?: matches.firstOrNull()
        }

        private fun normalised(email: String): String = email.trim().lowercase()

        private fun requireAdmissible(registration: CheckinRegistration): CheckinRegistration {
            if (!registration.isAdmissible) throw CheckinError.NotAdmissible(registration.fullName)
            return registration
        }
    }
}
