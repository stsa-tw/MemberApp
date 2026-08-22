package tw.stsa.memberapp.feature.events

import android.content.Context
import androidx.compose.runtime.mutableStateMapOf
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject
import tw.stsa.memberapp.R
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.net.httpGet

/**
 * Works out whether the member holds a ticket for an event, and where to open it.
 *
 * Indico has no "my registrations" endpoint, and its check-in API needs
 * `registration_checkin` on the event — an organiser permission a member does
 * not have. What a member *can* do is read any GET endpoint as themselves, so
 * asking for their own ticket is both the answer to "am I registered?" and the
 * ticket itself, in one request.
 *
 * | Indico's answer | What it means |
 * |---|---|
 * | 200 `application/pdf` | registered, complete, ticket issued |
 * | 403 | not registered — *or* registered and awaiting approval/payment, *or* the organiser has tickets switched off |
 *
 * That 403 genuinely cannot be told apart from outside; every ticket format runs
 * the same four checks in `RHTicketDownload._check_access`. So the UI does not
 * try to explain it — it offers the Indico page and lets Indico do the
 * explaining.
 *
 * **Why the PDF and not a Wallet pass.** Indico also serves
 * `…/ticket/google-wallet` and `…/ticket/apple-wallet`, and those would be the
 * better ticket. Both currently answer **500 `RecursionError: maximum recursion
 * depth exceeded`** on this instance, for every event, in a plain browser as
 * well as from here. When that is fixed server-side, switching back is a matter
 * of changing the path and the expected content type.
 *
 * Nothing is written to disk and no ticket is held in memory: a ticket QR *is*
 * the credential — whoever holds it can be checked in as that member — so the
 * app keeps only the URL and hands it to the browser, which already has the
 * member's Indico session.
 */
class TicketStore(context: Context) {

    private val appContext = context.applicationContext

    sealed interface State {
        data object Idle : State
        data object Loading : State

        /** The member has not authorized the app against Indico yet. */
        data object NeedsLinking : State

        /** Nothing to show. Deliberately does not claim to know why. */
        data object Unavailable : State

        /**
         * Where the ticket lives. Opened in the browser rather than fetched
         * again — the session there is what authenticates it.
         */
        data class Available(val url: String) : State
        data class Failed(val message: String) : State
    }

    /**
     * The part of the decision that depends only on the response, split out so
     * it can be tested without a network.
     */
    enum class Outcome { AVAILABLE, UNAVAILABLE, NEEDS_LINKING, FAILED }

    private val states = mutableStateMapOf<String, State>()

    /** An event's registration forms do not change under us. */
    private val formIds = mutableMapOf<String, List<Int>>()

    /**
     * What was already learned about this member's tickets, across launches.
     *
     * Only the *fact* and the form it came from — never the ticket: no URL, no
     * `checkin_secret`, nothing a scanner could accept. That is what keeps this
     * out of the encrypted [tw.stsa.memberapp.auth.TokenStore] and in ordinary
     * preferences, next to the profile claims.
     *
     * It exists because a **past** event's answer cannot change: the event is
     * over and the registration is history. Asking again would make Indico render
     * a PDF per row every time someone opens the archive. Upcoming events are
     * still asked live every launch — those genuinely do change — and their
     * answers land here, so by the time an event moves into the archive it is
     * already known.
     */
    private val prefs = appContext.getSharedPreferences("tickets", Context.MODE_PRIVATE)
    private var remembered = mutableMapOf<String, Pair<Boolean, Int?>>()

    /**
     * Keyed on `sub`, per the rule that local storage never keys on an email or a
     * username. Set from the composition root once the profile is known.
     */
    var subject: String? = null
        set(value) {
            if (field == value) return
            field = value
            remembered = readRemembered(value)
        }

    fun state(eventId: String): State = states[eventId] ?: State.Idle

    /**
     * Answers from what is already known, without touching the network.
     *
     * @return `true` when the question had already been settled, so the caller
     *   can skip asking Indico.
     */
    fun hydrate(eventId: String): Boolean {
        if (isSettled(eventId)) return true
        val known = remembered[eventId] ?: return false

        val (hasTicket, formId) = known
        states[eventId] = if (hasTicket && formId != null) {
            State.Available(ticketUrl(eventId, formId))
        } else {
            State.Unavailable
        }
        return true
    }

    /**
     * Looks up the event's registration forms, then asks each for a pass until
     * one answers. Most events have exactly one form, so this is normally two
     * requests.
     */
    suspend fun load(eventId: String, indico: IndicoAuthManager) {
        if (!indico.isLinked) {
            states[eventId] = State.NeedsLinking
            return
        }

        states[eventId] = State.Loading

        try {
            val headers = indico.authorizationHeaders()
            val formIds = registrationForms(eventId, headers)
            if (formIds.isEmpty()) {
                states[eventId] = State.Unavailable
                return
            }

            var fallback = Outcome.UNAVAILABLE
            for (formId in formIds) {
                val url = ticketUrl(eventId, formId)
                val response = httpGet(url, headers, readBody = false)

                when (outcome(response.status, response.contentType)) {
                    Outcome.AVAILABLE -> {
                        states[eventId] = State.Available(url)
                        remember(eventId, hasTicket = true, formId = formId)
                        return
                    }

                    Outcome.NEEDS_LINKING -> {
                        states[eventId] = State.NeedsLinking
                        return
                    }

                    Outcome.UNAVAILABLE -> continue

                    // Keep looking — another form may still answer — but do not
                    // let a real failure be reported as "nothing here".
                    Outcome.FAILED -> fallback = Outcome.FAILED
                }
            }

            if (fallback == Outcome.FAILED) {
                states[eventId] = State.Failed(appContext.getString(R.string.ticket_fetch_failed))
            } else {
                states[eventId] = State.Unavailable
                remember(eventId, hasTicket = false, formId = null)
            }
        } catch (error: TokenRejectedException) {
            states[eventId] = State.NeedsLinking
        } catch (error: Exception) {
            states[eventId] = State.Failed(
                error.message ?: appContext.getString(R.string.ticket_fetch_failed)
            )
        }
    }

    /**
     * Loads only what has not been resolved yet.
     *
     * The events list uses this rather than [load] so that opening the tab
     * repeatedly does not make Indico regenerate the same PDFs. The detail
     * screen still calls [load], because that is where someone lands right after
     * registering and expects the answer to have changed.
     */
    suspend fun loadIfNeeded(eventId: String, indico: IndicoAuthManager) {
        if (state(eventId) != State.Idle) return
        load(eventId, indico)
    }

    /**
     * Whether the member is known to hold a ticket. `false` while unknown — an
     * absent badge is a better lie than a wrong one.
     */
    fun holdsTicket(eventId: String): Boolean = state(eventId) is State.Available

    /**
     * Whether the answer for this event is in. Callers that *hide* rows on the
     * answer need this: "not registered" and "not asked yet" both read as
     * [holdsTicket] `false`, and treating the second as the first empties a list
     * that is merely still loading.
     */
    fun isSettled(eventId: String): Boolean =
        state(eventId) !is State.Idle && state(eventId) !is State.Loading

    /**
     * Records a failure raised outside [load] — the authorization flow — so it
     * surfaces in the same place as the rest.
     */
    fun report(error: Throwable, eventId: String) {
        states[eventId] = State.Failed(
            error.message ?: appContext.getString(R.string.ticket_fetch_failed)
        )
    }

    /**
     * Clears everything, including what was remembered across launches.
     *
     * Called from an explicit sign-out — the member asking for their traces to
     * leave this phone. A session that merely *expired* deliberately does not
     * call this: they did not ask to be signed out, and keeping the answers means
     * the archive is still instant when they sign back in. The entry is keyed on
     * `sub`, so a different member never sees it either way.
     */
    fun clear() {
        states.clear()
        formIds.clear()
        remembered.clear()
        subject?.let { prefs.edit { remove(rememberedKey(it)) } }
    }

    private fun remember(eventId: String, hasTicket: Boolean, formId: Int?) {
        val subject = subject ?: return
        remembered[eventId] = hasTicket to formId

        val encoded = JSONObject()
        remembered.forEach { (id, known) ->
            encoded.put(
                id,
                JSONObject()
                    .put("hasTicket", known.first)
                    .put("formId", known.second ?: JSONObject.NULL),
            )
        }
        prefs.edit { putString(rememberedKey(subject), encoded.toString()) }
    }

    private fun readRemembered(subject: String?): MutableMap<String, Pair<Boolean, Int?>> {
        val stored = subject?.let { prefs.getString(rememberedKey(it), null) }
            ?: return mutableMapOf()
        val parsed = runCatching { JSONObject(stored) }.getOrNull() ?: return mutableMapOf()

        val out = mutableMapOf<String, Pair<Boolean, Int?>>()
        parsed.keys().forEach { id ->
            val entry = parsed.optJSONObject(id) ?: return@forEach
            val formId = if (entry.isNull("formId")) null else entry.optInt("formId")
            out[id] = entry.optBoolean("hasTicket") to formId
        }
        return out
    }

    private fun rememberedKey(subject: String) = "tickets.known.$subject"

    private suspend fun registrationForms(
        eventId: String,
        headers: Map<String, String>,
    ): List<Int> {
        formIds[eventId]?.let { return it }
        // Anonymous works for public events, but restricted ones need the token,
        // and sending it costs nothing.
        val response = httpGet("$HOST/event/$eventId/api/registration-forms", headers)
        // A rejected token must not look like "this event has no forms" — that
        // would report a broken link as "no ticket here" and leave the member
        // with no way to notice.
        if (response.status == 401) throw TokenRejectedException()
        if (response.status != 200) return emptyList()

        val array = runCatching { JSONArray(response.body) }.getOrNull() ?: return emptyList()
        val ids = (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.optInt("id")?.takeIf { it > 0 }
        }
        formIds[eventId] = ids
        return ids
    }

    /**
     * Raised when Indico rejects the token outright, so [load] can tell that
     * apart from an event that simply has no registration form.
     */
    private class TokenRejectedException : Exception()

    companion object {
        private const val HOST = "https://event.stsa.tw"

        fun ticketUrl(eventId: String, formId: Int) =
            "$HOST/event/$eventId/registrations/$formId/ticket.pdf"

        /**
         * @param contentType is not decoration. The JDK client follows redirects,
         *   so a request that lost its authorization comes back as a perfectly
         *   good 200 — carrying Indico's *login page*. Only a PDF body is a
         *   ticket.
         */
        fun outcome(status: Int, contentType: String?): Outcome = when {
            status == 200 ->
                if (contentType?.lowercase()?.startsWith("application/pdf") == true) {
                    Outcome.AVAILABLE
                } else {
                    Outcome.FAILED
                }
            // The token was rejected: revoked from Indico's settings, or the
            // application was disabled.
            status == 401 -> Outcome.NEEDS_LINKING
            status == 403 || status == 404 -> Outcome.UNAVAILABLE
            else -> Outcome.FAILED
        }
    }
}
