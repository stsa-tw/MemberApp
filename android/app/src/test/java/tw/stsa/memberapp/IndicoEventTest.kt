package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tw.stsa.memberapp.model.IndicoEvent
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId

private fun makeEvent(
    id: String = "10",
    title: String = "工作坊",
    location: String? = "i2Hub",
    room: String? = "#04-32",
    description: String? = null,
    type: String? = "conference",
): IndicoEvent {
    val fields = buildList {
        add(""""id": $id""")
        add(""""title": "$title"""")
        add(""""startDate": {"date": "2026-08-15", "time": "13:30:00", "tz": "Asia/Singapore"}""")
        add(""""endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}""")
        if (location != null) add(""""location": "$location"""")
        if (room != null) add(""""room": "$room"""")
        if (description != null) add(""""description": "$description"""")
        if (type != null) add(""""type": "$type"""")
    }
    return IndicoEvent.decode("{${fields.joinToString(",")}}")
}

class IndicoEventDecodingTest {

    /**
     * Indico has emitted `id` as both a JSON string and a JSON number across
     * versions, and the app keys on it either way.
     */
    @Test
    fun `accepts a numeric id`() {
        assertEquals("10", makeEvent(id = "10").id)
    }

    @Test
    fun `accepts a string id`() {
        assertEquals("10", makeEvent(id = "\"10\"").id)
    }

    /**
     * Indico splits a moment into date, time and tz instead of emitting
     * ISO 8601, so the parse is hand-rolled and worth pinning.
     */
    @Test
    fun `builds dates from indico split moments in the stated time zone`() {
        val event = makeEvent()
        val singapore = ZoneId.of("Asia/Singapore")
        val expectedStart = LocalDateTime.of(2026, 8, 15, 13, 30)
            .atZone(singapore)
            .toInstant()

        assertEquals(expectedStart, event.start)
        assertEquals(Duration.ofHours(2), Duration.between(event.start, event.end))
        assertEquals(singapore, event.zone)
    }

    /**
     * An unparseable moment falls back rather than throwing, so one malformed
     * event cannot take down the whole feed.
     */
    @Test
    fun `an unparseable date falls back instead of failing the decode`() {
        val json = """
            {"id": 1, "title": "x",
             "startDate": {"date": "not-a-date", "time": "13:30:00", "tz": "Asia/Singapore"},
             "endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}}
        """
        val event = IndicoEvent.decode(json)

        assertEquals(IndicoEvent.UNPARSEABLE_MOMENT, event.start)
    }

    /** An unknown time zone must not fail the decode either. */
    @Test
    fun `an unknown time zone falls back to the system one`() {
        val json = """
            {"id": 1, "title": "x",
             "startDate": {"date": "2026-08-15", "time": "13:30:00", "tz": "Mars/Olympus"},
             "endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Mars/Olympus"}}
        """

        assertEquals(ZoneId.systemDefault(), IndicoEvent.decode(json).zone)
    }

    @Test
    fun `a missing description decodes as empty rather than throwing`() {
        assertTrue(makeEvent(description = null).summary.isEmpty())
    }

    /** The export wraps its results, and that is what EventsStore reads. */
    @Test
    fun `decodes the export envelope`() {
        val json = """
            {"count": 1, "ts": 0, "url": "x", "results": [
              {"id": 10, "title": "工作坊",
               "startDate": {"date": "2026-08-15", "time": "13:30:00", "tz": "Asia/Singapore"},
               "endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}}
            ]}
        """

        val events = IndicoEvent.decodeExport(json)

        assertEquals(1, events.size)
        assertEquals("10", events[0].id)
    }
}

class IndicoEventSummaryTest {

    /**
     * Descriptions arrive as HTML. The detail screen lays out plain paragraphs,
     * so block tags become breaks and everything else is dropped.
     */
    @Test
    fun `block tags become line breaks`() {
        assertEquals("第一段\n第二段", makeEvent(description = "<p>第一段</p><p>第二段</p>").summary)
    }

    @Test
    fun `inline tags are stripped without leaving a gap`() {
        assertEquals("報名截止了", makeEvent(description = "報名<strong>截止</strong>了").summary)
    }

    @Test
    fun `entities are decoded`() {
        val event = makeEvent(description = "Slasify &amp; SLI &ldquo;工作坊&rdquo;")

        assertEquals("Slasify & SLI “工作坊”", event.summary)
    }

    /**
     * `&amp;` is applied last, so text that was escaped twice stays escaped
     * rather than being decoded into markup on the second pass.
     */
    @Test
    fun `a double escaped entity is not decoded twice`() {
        assertEquals("&lt;b&gt;", makeEvent(description = "&amp;lt;b&amp;gt;").summary)
    }

    /**
     * Dropping tags leaves runs of blank lines behind; they collapse so the
     * detail screen does not show a gap where a `<div>` used to be.
     */
    @Test
    fun `runs of blank lines collapse`() {
        val event = makeEvent(description = "<div>一</div><br><br><br><div>二</div>")

        assertEquals("一\n\n二", event.summary)
    }
}

class IndicoEventPlaceTest {

    @Test
    fun `joins venue and room`() {
        assertEquals("i2Hub · #04-32", makeEvent().place)
    }

    /** Indico leaves either field blank, so whichever is present is used alone. */
    @Test
    fun `uses whichever field is present`() {
        assertEquals("i2Hub", makeEvent(room = null).place)
        assertEquals("#04-32", makeEvent(location = null).place)
    }

    /**
     * Blank is not the same as absent in Indico's export — a whitespace-only
     * field must not render as a stray separator.
     */
    @Test
    fun `treats whitespace only fields as absent`() {
        assertEquals("i2Hub", makeEvent(room = "   ").place)
        assertNull(makeEvent(location = "  ", room = " ").place)
    }

    @Test
    fun `is null when neither field is present`() {
        assertNull(makeEvent(location = null, room = null).place)
    }
}

/**
 * Organisers decorate Indico titles freely, and the app strips that at decode
 * time so every screen gets the same clean string.
 *
 * The digit cases are the ones that matter. iOS has to dodge
 * `Unicode.Scalar.Properties.isEmoji`, which is true for plain digits and for
 * `#`/`*`; this side tests the general category instead, and these pin that it
 * reaches the same answer.
 */
class IndicoEventTitleTest {

    private fun title(raw: String): String = makeEvent(title = raw).title

    @Test
    fun `drops a trailing emoji`() {
        assertEquals(
            "2026 STSA Boba Chat｜Back to School Edition",
            title("2026 STSA Boba Chat｜Back to School Edition 🧋"),
        )
    }

    @Test
    fun `drops a run of them`() {
        assertEquals("2026 STSA 中秋烤肉趴", title("2026 STSA 中秋烤肉趴 🌕🔥"))
    }

    @Test
    fun `closes the gap left in the middle`() {
        assertEquals("STSA Boba Chat", title("STSA 🧋 Boba Chat"))
    }

    @Test
    fun `does not eat the year`() {
        assertEquals("2026 STSA Career Talk", title("2026 STSA Career Talk"))
    }

    @Test
    fun `does not eat hashes or asterisks`() {
        assertEquals("Room #04-32 *額滿*", title("Room #04-32 *額滿*"))
    }

    @Test
    fun `drops a joined sequence whole`() {
        assertEquals("家庭日", title("家庭日 👨‍👩‍👧‍👦"))
    }

    @Test
    fun `drops a flag`() {
        assertEquals("台灣之夜", title("台灣之夜 🇹🇼"))
    }

    /**
     * Pinning a behaviour rather than an ideal: a title with nothing left is
     * worse than one that kept its decoration.
     */
    @Test
    fun `keeps a title that was nothing but emoji`() {
        assertEquals("🎉🎉", title("🎉🎉"))
    }
}
