package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Test
import tw.stsa.memberapp.feature.events.TicketStore

/**
 * Indico answers a ticket request with a status code and little else, so this
 * mapping is the whole of what the app knows. The cases pin Indico's actual
 * behaviour rather than an ideal API:
 *
 * - 403 covers "not registered", "registered but not yet complete" and "tickets
 *   are switched off", all from `RHTicketDownload._check_access`. They are
 *   deliberately collapsed, because they cannot be told apart.
 * - 404 would be a ticket format Indico cannot produce for this event. Nothing
 *   to offer, same as 403.
 *
 * The app asks for `ticket.pdf` rather than a Wallet pass because both of
 * Indico's Wallet endpoints currently answer 500 on this instance — see
 * [TicketStore].
 */
class TicketOutcomeTest {

    private val pdf = "application/pdf"

    @Test
    fun `a pdf ticket is available`() {
        assertEquals(TicketStore.Outcome.AVAILABLE, TicketStore.outcome(200, pdf))
    }

    @Test
    fun `content type parameters do not break the match`() {
        assertEquals(TicketStore.Outcome.AVAILABLE, TicketStore.outcome(200, "$pdf; charset=binary"))
    }

    /**
     * The important one. The JDK client follows redirects, so a request that lost
     * its authorization comes back as a 200 carrying Indico's login page. A 200
     * alone is not a ticket.
     */
    @Test
    fun `html with a 200 is a failure rather than a ticket`() {
        assertEquals(TicketStore.Outcome.FAILED, TicketStore.outcome(200, "text/html; charset=utf-8"))
    }

    @Test
    fun `a missing content type is a failure`() {
        assertEquals(TicketStore.Outcome.FAILED, TicketStore.outcome(200, null))
    }

    @Test
    fun `a rejected token asks to link again`() {
        assertEquals(TicketStore.Outcome.NEEDS_LINKING, TicketStore.outcome(401, null))
    }

    @Test
    fun `forbidden means there is nothing to show`() {
        assertEquals(TicketStore.Outcome.UNAVAILABLE, TicketStore.outcome(403, null))
    }

    @Test
    fun `no ticket for this form means there is nothing to show`() {
        assertEquals(TicketStore.Outcome.UNAVAILABLE, TicketStore.outcome(404, null))
    }

    @Test
    fun `server errors are failures`() {
        assertEquals(TicketStore.Outcome.FAILED, TicketStore.outcome(500, null))
    }

    @Test
    fun `a transport failure with no response is a failure`() {
        assertEquals(TicketStore.Outcome.FAILED, TicketStore.outcome(0, null))
    }
}
