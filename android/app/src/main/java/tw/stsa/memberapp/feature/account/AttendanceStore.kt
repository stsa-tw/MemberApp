package tw.stsa.memberapp.feature.account

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.net.httpGet
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * How many events the signed-in member has been checked in to.
 *
 * Read from the STSA plugin's `GET /api/stsa/registered-events` on Indico,
 * which answers for the caller alone — a member's own token sees their own
 * registrations and their `checked_in` flag, which the organiser-only check-in
 * API would not have let them read.
 *
 * Deliberately **not** filtered with `status=checked_in`. That is the event's
 * status for this member, and an event that is still upcoming or ongoing keeps
 * that status even once they have been checked in — so the filter dropped
 * someone who had just been to an event that had not finished. The flag on
 * each registration is what says whether they were there.
 *
 * Only this academic year's events are counted, so the number means "how
 * involved were you lately" rather than a total that only ever grows. The year
 * turns over on 1 July, and the window is
 * handed to Indico as `from` so it does the filtering.
 *
 * Counts **events**, not registrations: two forms for one event, or two
 * check-ins, are still one event attended. Registered-but-absent does not
 * count — padding the number with them would be the wrong kind of generous.
 *
 * Needs the Indico link. Without one there is nothing to ask, so nothing is
 * shown rather than a zero that claims to know. Mirrors `AttendanceStore` on
 * iOS.
 */
class AttendanceStore {

    /**
     * What Indico last said, one entry per registration. Null until it has
     * answered, and again after sign-out. Never a stand-in empty list: "we have
     * not been told" and "none yet" are different things, and only the second
     * belongs on the screen.
     */
    var entries by mutableStateOf<List<Entry>?>(null)
        private set

    /** Events the member was checked in to, newest first, each once. */
    val attended: List<Entry>? get() = entries?.let(::attended)

    /**
     * Events they registered for and were not checked in to — yet to happen,
     * under way, or missed — soonest first. An event they *were* checked in to
     * never appears here, even if a second registration for it was not.
     */
    val notAttended: List<Entry>? get() = entries?.let(::notAttended)

    val count: Int? get() = attended?.size

    /**
     * Leaves the previous answer alone on any failure. A flaky connection should
     * not take a number off the screen that was right a minute ago, and a token
     * Indico will not accept for this endpoint simply never shows one.
     */
    suspend fun load(indico: IndicoAuthManager) {
        if (!indico.isLinked) return
        val response = runCatching { httpGet("$ENDPOINT?from=${academicYearStart()}", indico.authorizationHeaders()) }.getOrNull() ?: return
        if (response.status != 200) return
        entries = decode(response.body) ?: return
    }

    /** The previous member's number must not greet the next one. */
    fun clear() {
        entries = null
    }

    companion object {
        private const val ENDPOINT = "https://event.stsa.tw/api/stsa/registered-events"
        private val SINGAPORE = ZoneId.of("Asia/Singapore")

        /**
         * The first day of the academic year that [today] falls in, as the plain
         * date Indico takes for `from` — "a date alone is the start of that day".
         * Read in Singapore's calendar, which is also what Indico's own timezone
         * is here, so the day does not shift with wherever the phone happens to be.
         */
        fun academicYearStart(today: LocalDate = LocalDate.now(SINGAPORE)): String {
            val year = if (today.monthValue >= 7) today.year else today.year - 1
            return "%04d-07-01".format(year)
        }

        /**
         * The registrations in the body, or null if it is not a registration
         * list at all.
         *
         * Read off the parsed tree, and strict about types, to agree with iOS:
         * an entry that does not have an integer event id and a boolean
         * `checked_in` makes the whole answer unusable rather than quietly
         * uncounted.
         */
        fun decode(body: String): List<Entry>? =
            runCatching {
                val list = Json.parseToJsonElement(body).jsonObject["registrations"] as? JsonArray
                    ?: return@runCatching null
                list.map { element ->
                    val entry = element.jsonObject
                    val eventId = entry.primitive("event", "id")?.takeIf { !it.isString }?.intOrNull
                    val checkedIn = entry.primitive("registration", "checked_in")
                        ?.takeIf { !it.isString }?.booleanOrNull
                    if (eventId == null || checkedIn == null) error("malformed entry")
                    Entry(
                        eventId = eventId,
                        title = entry.primitive("event", "title")?.contentOrNull.orEmpty(),
                        start = entry.primitive("event", "start_dt")?.contentOrNull
                            ?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() },
                        zone = entry.primitive("event", "timezone")?.contentOrNull
                            ?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: SINGAPORE,
                        url = entry.primitive("event", "url")?.contentOrNull,
                        status = (entry["status"] as? JsonPrimitive)?.contentOrNull.orEmpty(),
                        checkedIn = checkedIn,
                    )
                }
            }.getOrNull()

        fun attended(entries: List<Entry>): List<Entry> =
            once(entries.filter { it.checkedIn }).sortedByDescending { it.start ?: Instant.MIN }

        fun notAttended(entries: List<Entry>): List<Entry> {
            val attendedIds = entries.filter { it.checkedIn }.map { it.eventId }.toSet()
            return once(entries.filter { it.eventId !in attendedIds })
                .sortedBy { it.start ?: Instant.MAX }
        }

        /** Two forms for one event, or two check-ins, are one event. */
        private fun once(entries: List<Entry>): List<Entry> = entries.distinctBy { it.eventId }

        private fun JsonObject.primitive(parent: String, key: String) =
            (this[parent] as? JsonObject)?.get(key) as? JsonPrimitive
    }

    /** One registration, as much of it as the screen shows. */
    data class Entry(
        /** Indico's event id. Two registrations for one event share it. */
        val eventId: Int,
        val title: String,
        val start: Instant?,
        val zone: ZoneId,
        val url: String?,
        /**
         * Indico's own word for where the event stands for this member:
         * `upcoming`, `ongoing`, `checked_in`, `no_show`, `pending`.
         */
        val status: String,
        val checkedIn: Boolean,
    )
}
