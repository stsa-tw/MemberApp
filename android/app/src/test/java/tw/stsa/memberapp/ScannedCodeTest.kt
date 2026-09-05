package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tw.stsa.memberapp.feature.checkin.ScannedCode
import tw.stsa.memberapp.model.IndicoEvent
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID

/**
 * Base64 of the 16 raw bytes of 3f2504e0-4f89-11d3-9a0c-0305e82c3301, which is
 * how Indico writes a ticket UUID into a QR.
 */
private const val TICKET_SECRET = "PyUE4E+JEdOaDAMF6CwzAQ=="
private const val PERSON_SECRET = "C34PShwtTl+KmwwdLj9KWw=="
private val TICKET_UUID: UUID = UUID.fromString("3f2504e0-4f89-11d3-9a0c-0305e82c3301")

private fun ticketQr(
    version: Int = 2,
    host: String = "event.stsa.tw",
    secret: String = TICKET_SECRET,
    person: String? = null,
): String {
    val fields = buildList {
        add("$version")
        add("\"$host\"")
        add("\"$secret\"")
        if (person != null) add("\"$person\"")
    }
    return """{"i":[${fields.joinToString(",")}]}"""
}

class ScannedCodeTest {

    // MARK: - Member cards

    @Test
    fun `reads a member card`() {
        val scanned = ScannedCode.parse("stsa\$abcdefghij0123456789")
        assertEquals(ScannedCode.MemberCode("abcdefghij0123456789"), scanned)
    }

    /**
     * MembershipAPI's CODE_LENGTH is 20. A different length is not a code this
     * app minted, so it is not one worth sending to `validate_code`.
     */
    @Test
    fun `rejects a member card of the wrong length`() {
        assertNull(ScannedCode.parse("stsa\$tooshort"))
        assertNull(ScannedCode.parse("stsa\$abcdefghij01234567890"))
    }

    /** The codes are drawn from ascii_letters + digits only. */
    @Test
    fun `rejects non-alphanumeric member codes`() {
        assertNull(ScannedCode.parse("stsa\$abcdefghij012345678-"))
    }

    /** Scanners and clipboards add trailing newlines. */
    @Test
    fun `ignores surrounding whitespace`() {
        val scanned = ScannedCode.parse("  stsa\$abcdefghij0123456789\n")
        assertEquals(ScannedCode.MemberCode("abcdefghij0123456789"), scanned)
    }

    // MARK: - Indico tickets

    @Test
    fun `reads a ticket`() {
        val ticket = ScannedCode.parse(ticketQr()) as ScannedCode.Ticket
        assertEquals(TICKET_UUID, ticket.checkinSecret)
        assertEquals("event.stsa.tw", ticket.host)
        assertNull(ticket.accompanyingPersonId)
    }

    /**
     * Indico strips `https://` to save bytes but leaves `http://` alone, and the
     * host is compared against ours before any request is made.
     */
    @Test
    fun `normalises the issuer host`() {
        for (issuer in listOf(
            "event.stsa.tw",
            "https://event.stsa.tw",
            "http://event.stsa.tw",
            "event.stsa.tw/",
        )) {
            val ticket = ScannedCode.parse(ticketQr(host = issuer)) as ScannedCode.Ticket
            assertEquals("event.stsa.tw", ticket.host)
        }
    }

    /**
     * A fourth element means the ticket belongs to an accompanying person, who
     * has no registration of their own.
     */
    @Test
    fun `reads an accompanying person ticket`() {
        val ticket = ScannedCode.parse(ticketQr(person = PERSON_SECRET)) as ScannedCode.Ticket
        assertEquals(UUID.fromString("0b7e0f4a-1c2d-4e5f-8a9b-0c1d2e3f4a5b"), ticket.accompanyingPersonId)
    }

    /**
     * Indico bumps the version when the field layout changes. Parsing a future
     * one hopefully would put the wrong bytes in the UUID slot and surface as
     * the wrong person rather than as an error.
     */
    @Test
    fun `refuses an unknown ticket version`() {
        assertNull(ScannedCode.parse(ticketQr(version = 3)))
        assertNull(ScannedCode.parse(ticketQr(version = 1)))
    }

    /**
     * The site-access plugin adds its own key alongside `i`. Ignoring unknown
     * keys is what keeps that from looking like a corrupt ticket.
     */
    @Test
    fun `ignores extra keys from plugins`() {
        val qr = """{"i":[2,"event.stsa.tw","$TICKET_SECRET"],"adams":"https://adams.example"}"""
        assertTrue(ScannedCode.parse(qr) is ScannedCode.Ticket)
    }

    @Test
    fun `rejects a secret that is not sixteen bytes`() {
        assertNull(ScannedCode.parse(ticketQr(secret = "PyUE4E+JEdM=")))
        assertNull(ScannedCode.parse(ticketQr(secret = "not base64 at all")))
    }

    // MARK: - Everything else

    @Test
    fun `rejects codes that are neither`() {
        assertNull(ScannedCode.parse("https://event.stsa.tw/event/12/"))
        assertNull(ScannedCode.parse(""))
        assertNull(ScannedCode.parse("""{"i":[2]}"""))
        assertNull(ScannedCode.parse("{}"))
    }
}

/** The event runs 13:30–15:30 on 2026-08-15 in the fixture below. */
class CheckinWindowTest {
    private fun event(): IndicoEvent = IndicoEvent.decode(
        """
        {"id": 10, "title": "工作坊",
         "startDate": {"date": "2026-08-15", "time": "13:30:00", "tz": "Asia/Singapore"},
         "endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}}
        """,
    )

    private fun moment(text: String): Instant = OffsetDateTime.parse(text).toInstant()

    @Test
    fun `is open while the event runs`() {
        assertTrue(event().isWithinCheckinWindow(moment("2026-08-15T14:00:00+08:00")))
    }

    /**
     * The whole point of not using isUpcoming: events overrun, and the door must
     * not close on a staffer who is still working it.
     */
    @Test
    fun `stays open after the scheduled end`() {
        val event = event()
        assertTrue(event.isWithinCheckinWindow(moment("2026-08-15T15:35:00+08:00")))
        assertTrue(event.isWithinCheckinWindow(moment("2026-08-16T09:00:00+08:00")))
    }

    /**
     * Someone missed at the door is reconciled the same day or the next one, not
     * a week later.
     */
    @Test
    fun `closes once the grace has passed`() {
        assertFalse(event().isWithinCheckinWindow(moment("2026-08-17T09:00:00+08:00")))
    }

    /**
     * No restriction before the start: an organiser checking next month's event
     * should find the door already there rather than having to wait for the day
     * to learn whether they can open it.
     */
    @Test
    fun `is open well before the start`() {
        val event = event()
        assertTrue(event.isWithinCheckinWindow(moment("2026-08-15T12:00:00+08:00")))
        assertTrue(event.isWithinCheckinWindow(moment("2026-06-01T12:00:00+08:00")))
    }
}
