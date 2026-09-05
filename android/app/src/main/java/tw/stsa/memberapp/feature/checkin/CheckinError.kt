package tw.stsa.memberapp.feature.checkin

import android.content.Context
import tw.stsa.memberapp.R

/** Everything 報到 can tell a worker went wrong, transport and resolution alike. */
sealed class CheckinError : Exception() {
    object NotAuthenticated : CheckinError()

    /** Signed in to Indico, but not a check-in worker on this event. */
    object Forbidden : CheckinError()

    /** No such ticket or registration. */
    object NotFound : CheckinError()

    data class Server(val status: Int, val body: String) : CheckinError()

    object MalformedResponse : CheckinError()

    /** A ticket issued by some other Indico instance. */
    data class ForeignInstance(val host: String) : CheckinError()

    /** A ticket belonging to an accompanying person, who has no registration. */
    object AccompanyingPerson : CheckinError()

    /** A valid ticket, but for a different event than the one being staffed. */
    object WrongEvent : CheckinError()

    /** The member card's code was expired or never real. */
    object ExpiredMemberCode : CheckinError()

    /** A known member with no registration in this form. */
    data class NotRegistered(val name: String) : CheckinError()

    /** Registered, but withdrawn or rejected. */
    data class NotAdmissible(val name: String) : CheckinError()

    object UnrecognisedCode : CheckinError()

    /**
     * The Indico authorization is read-only. Recording a check-in needs
     * `registrants`, which the staffer grants once from the door screen.
     */
    object NeedsAuthorization : CheckinError()

    fun message(context: Context): String = when (this) {
        NotAuthenticated -> context.getString(R.string.error_checkin_401)
        Forbidden -> context.getString(R.string.error_checkin_403)
        NotFound -> context.getString(R.string.error_checkin_404)
        is Server -> context.getString(R.string.error_checkin_server, status, body.take(120))
        MalformedResponse -> context.getString(R.string.error_checkin_malformed)
        is ForeignInstance -> context.getString(R.string.error_checkin_foreign, host)
        AccompanyingPerson -> context.getString(R.string.error_checkin_accompanying)
        WrongEvent -> context.getString(R.string.error_checkin_wrong_event)
        ExpiredMemberCode -> context.getString(R.string.error_checkin_expired_code)
        is NotRegistered -> context.getString(R.string.error_checkin_not_registered, name)
        is NotAdmissible -> context.getString(R.string.error_checkin_not_admissible, name)
        UnrecognisedCode -> context.getString(R.string.error_checkin_unrecognised)
        NeedsAuthorization -> context.getString(R.string.error_checkin_needs_authorization)
    }

    companion object {
        fun of(status: Int, body: String): CheckinError = when (status) {
            401 -> NotAuthenticated
            403 -> Forbidden
            404 -> NotFound
            else -> Server(status, body)
        }
    }
}
