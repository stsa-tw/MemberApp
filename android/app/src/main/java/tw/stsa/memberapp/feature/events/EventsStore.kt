package tw.stsa.memberapp.feature.events

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import tw.stsa.memberapp.R
import tw.stsa.memberapp.model.IndicoEvent
import tw.stsa.memberapp.net.httpGet
import java.time.Instant

/**
 * Loads events from the STSA Indico instance.
 *
 * The category export is public, so this deliberately carries no credentials —
 * events are visible on the web without signing in, and requiring a token here
 * would only make the tab fail for no gain. Registration is the part that needs
 * an account, and that happens on Indico itself.
 */
class EventsStore(private val context: Context) {

    var events by mutableStateOf<List<IndicoEvent>>(emptyList())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set

    fun upcoming(now: Instant = Instant.now()): List<IndicoEvent> =
        events.filter { it.isUpcoming(now) }.sortedBy { it.start }

    fun past(now: Instant = Instant.now()): List<IndicoEvent> =
        events.filter { !it.isUpcoming(now) }.sortedByDescending { it.start }

    suspend fun load() {
        isLoading = true
        try {
            val response = httpGet(ENDPOINT)
            if (response.status != 200) {
                errorMessage = context.getString(R.string.error_indico_http, response.status)
                return
            }
            events = IndicoEvent.decodeExport(response.body)
            errorMessage = null
        } catch (error: Exception) {
            errorMessage = error.message ?: error.javaClass.simpleName
        } finally {
            isLoading = false
        }
    }

    private companion object {
        /**
         * Root category. Everything STSA runs lives under it today; if that
         * changes, this is the one thing to repoint.
         */
        const val ENDPOINT =
            "https://event.stsa.tw/export/categ/0.json?from=-180d&to=730d&limit=200"
    }
}
