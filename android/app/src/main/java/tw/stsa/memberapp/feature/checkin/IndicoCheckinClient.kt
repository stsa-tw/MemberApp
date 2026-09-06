package tw.stsa.memberapp.feature.checkin

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.model.CheckinRegForm
import tw.stsa.memberapp.model.CheckinRegistration
import tw.stsa.memberapp.net.HttpResponse
import tw.stsa.memberapp.net.httpSend
import java.util.UUID

/**
 * Everything 報到 does against Indico.
 *
 * These endpoints are not in Indico's published API docs — they are what the
 * official check-in app uses, behind the `registrants` scope, and upstream makes
 * no backwards-compatibility promise about them. Paths and payloads here were
 * read from `indico/modules/events/registration/blueprint.py` and
 * `controllers/api/checkin.py` at v3.3.13, which is what `event.stsa.tw` runs.
 */
class IndicoCheckinClient(
    private val indico: IndicoAuthManager,
    private val send: suspend (String, String, Map<String, String>, String?) -> HttpResponse = ::httpSend,
) {
    /**
     * The event's registration forms.
     *
     * Doubles as the permission probe: Indico answers 403 unless the signed-in
     * account holds `registration_checkin` on this event, so a successful call
     * is what earns the 報到 button rather than any claim the app carries.
     */
    suspend fun regforms(eventId: Int): List<CheckinRegForm> =
        CheckinRegForm.decodeList(get("/api/checkin/event/$eventId/forms/"))

    /**
     * Every registration in one form, checked-in or not.
     *
     * Fetched whole and held for the session: a member card identifies a person,
     * not a registration, so matching happens locally against this list. It is
     * also what lets the scanner keep working when the venue's wifi does not.
     */
    suspend fun registrations(eventId: Int, regformId: Int): List<CheckinRegistration> =
        CheckinRegistration.decodeList(
            get("/api/checkin/event/$eventId/forms/$regformId/registrations/"),
        )

    /**
     * Resolves a scanned ticket straight to its registration.
     *
     * Note this endpoint is not scoped to an event — Indico looks the ticket up
     * globally and applies the permission check to whatever event it belongs to.
     * A worker could therefore resolve a ticket for a different event they
     * happen to staff, so callers must compare `eventId` against the event they
     * opened; [CheckinSession] does.
     */
    suspend fun registration(ticket: UUID): CheckinRegistration =
        CheckinRegistration.decode(get("/api/checkin/ticket/${ticket.toString().lowercase()}"))

    /**
     * Records attendance. Returns the registration as Indico now holds it.
     *
     * Idempotent in practice: PATCHing `checked_in` that is already true is
     * accepted and simply re-sends the same state, so a double scan is harmless.
     * `checked_in_dt` keeps the original moment.
     */
    suspend fun checkIn(
        registration: CheckinRegistration,
        checkedIn: Boolean = true,
    ): CheckinRegistration {
        val path = "/api/checkin/event/${registration.eventId}" +
            "/forms/${registration.regformId}/registrations/${registration.id}"
        val body = JsonObject(mapOf("checked_in" to JsonPrimitive(checkedIn))).toString()
        return CheckinRegistration.decode(request(path, "PATCH", body))
    }

    private suspend fun get(path: String): String = request(path, "GET", null)

    private suspend fun request(path: String, method: String, body: String?): String {
        val headers = indico.authorizationHeaders() + ("Accept" to "application/json")
        val response = send(BASE_URL + path, method, headers, body)
        if (response.status != 200) throw CheckinError.of(response.status, response.body)
        return response.body
    }

    companion object {
        /**
         * The instance whose tickets this app will accept. A ticket naming any
         * other host is refused before a request is made.
         */
        const val HOST = "event.stsa.tw"

        private const val BASE_URL = "https://$HOST"
    }
}
