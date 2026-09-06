package tw.stsa.memberapp.feature.checkin

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.model.CheckinRegForm
import tw.stsa.memberapp.model.CheckinRegistration

/**
 * One worker's 報到 session for one event: the registrant list, and the rules
 * that turn a scan into a registration.
 *
 * Holding the whole list is deliberate. A member card names a person, not a
 * registration, so it can only be matched locally — and a venue's wifi is the
 * least reliable thing at any event, so the list is fetched once at the door
 * rather than per scan.
 */
class CheckinSession(
    val eventId: Int,
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

    val checkedInCount: Int get() = registrations.count { it.checkedIn }

    // MARK: - Loading

    /**
     * Loads the forms and, when there is only one, its registrants.
     *
     * The forms call is also the permission check: 403 here is the normal answer
     * for a member who is not staffing this event, so it becomes [Phase.Denied]
     * rather than an error banner.
     */
    suspend fun load() {
        phase = Phase.Loading
        try {
            regforms = client.regforms(eventId)
            // Most STSA events have exactly one form, so skip a pointless
            // choice; when there are several the worker picks.
            val only = regforms.singleOrNull()
            if (only != null) select(only) else phase = Phase.Ready
        } catch (error: CheckinError) {
            phase = if (error is CheckinError.Forbidden) Phase.Denied else Phase.Failed(error)
        }
    }

    suspend fun select(form: CheckinRegForm) {
        regform = form
        registrations = client.registrations(eventId, form.id)
        phase = Phase.Ready
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

    private fun resolveMember(identity: MemberIdentity): CheckinRegistration {
        val registration = match(identity.email, registrations)
            ?: throw CheckinError.NotRegistered(identity.name)
        return requireAdmissible(registration)
    }

    // MARK: - Recording attendance

    /**
     * Records attendance and folds Indico's answer back into the local list, so
     * the running count and any later scan of the same person are right without
     * re-fetching.
     */
    suspend fun checkIn(registration: CheckinRegistration): CheckinRegistration {
        // Reading a roster needs only `read:everything`; writing needs the wider
        // grant, which is asked for on this screen and nowhere else.
        if (!indico.canRecordCheckin) throw CheckinError.NeedsAuthorization
        isSubmitting = true
        try {
            val updated = client.checkIn(registration)
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
            // A form can hold more than one registration for an address. Prefer
            // one that can actually be admitted over a withdrawn leftover.
            return matches.firstOrNull { it.isAdmissible } ?: matches.firstOrNull()
        }

        private fun normalised(email: String): String = email.trim().lowercase()

        private fun requireAdmissible(registration: CheckinRegistration): CheckinRegistration {
            if (!registration.isAdmissible) throw CheckinError.NotAdmissible(registration.fullName)
            return registration
        }
    }
}
