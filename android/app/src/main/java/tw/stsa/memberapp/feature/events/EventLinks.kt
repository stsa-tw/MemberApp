package tw.stsa.memberapp.feature.events

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import androidx.core.net.toUri
import tw.stsa.memberapp.model.IndicoEvent

/**
 * The two places an event points off to: the phone's calendar and its map.
 *
 * Both are handoffs to whatever app the member has chosen for the job, which is
 * why neither needs a permission — `ACTION_INSERT` opens the calendar's own
 * new-event screen with the fields filled in, and the member saves it there or
 * does not. The app never touches the calendar provider itself, so no
 * `WRITE_CALENDAR`, and nothing it cannot see gets read.
 *
 * Every launch is guarded by a try rather than by `resolveActivity`. From API 30
 * the latter answers null unless the target is listed in the manifest's
 * `<queries>` — starting the intent works regardless, so the query would only be
 * a second thing to keep in sync, and one that fails closed on a device that
 * *does* have a calendar. Do not "fix" this by adding a `resolveActivity` check.
 */
internal object EventLinks {

    /**
     * Hands the event to the calendar app, pre-filled.
     *
     * Deliberately not a direct insert through `CalendarContract`: that needs
     * `WRITE_CALENDAR`, and it would write into whichever calendar the app
     * picked, silently — the kind of thing that turns up in somebody's shared
     * work calendar. The system screen is one extra tap and it shows them the
     * whole entry, lets them choose the calendar, and lets them back out.
     *
     * @return false where the device has no calendar app to hand it to.
     */
    fun addToCalendar(context: Context, event: IndicoEvent): Boolean {
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, event.title)
            // Epoch millis, so the zone below is about how the entry is *written*
            // rather than when it happens — a member who saves a Taipei event and
            // then flies somewhere still sees the hour the organiser announced.
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, event.start.toEpochMilli())
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, event.end.toEpochMilli())
            .putExtra(CalendarContract.Events.EVENT_TIMEZONE, event.zone.id)

        // The full line, room included — a calendar app geocodes this field
        // itself to offer travel time, and shows the text to whoever opens the
        // entry, which is the half that wants the floor number.
        event.locationLine?.let { intent.putExtra(CalendarContract.Events.EVENT_LOCATION, it) }

        // The Indico page rather than the description, which is a flattened HTML
        // blob that can run to several screens. What a member opening this a
        // month later wants is the way back to the event — where the description
        // is, readable, along with anything that changed since. iOS puts it in
        // `EKEvent.url`; `CalendarContract.Events` has no such column, so it goes
        // in the description here.
        event.url?.let { intent.putExtra(CalendarContract.Events.DESCRIPTION, it) }

        return context.launch(intent)
    }

    /**
     * Opens the event's location in whatever handles maps.
     *
     * `geo:` with a query rather than coordinates — see `IndicoEvent.mapQuery`
     * for why a search and not a pin. The leading `0,0` is the scheme's
     * required-but-ignored centre when a `q` is present.
     *
     * Falls back to Google Maps on the web, which any browser takes, for a
     * device with no map app installed.
     *
     * @return false where neither a map app nor a browser would take it.
     */
    fun openMap(context: Context, query: String): Boolean {
        val geo = Intent(Intent.ACTION_VIEW, "geo:0,0?q=${Uri.encode(query)}".toUri())
        if (context.launch(geo)) return true

        val web = Intent(
            Intent.ACTION_VIEW,
            "https://www.google.com/maps/search/?api=1&query=${Uri.encode(query)}".toUri(),
        )
        return context.launch(web)
    }

    private fun Context.launch(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }
}
