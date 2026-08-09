package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tw.stsa.memberapp.model.Deal
import java.time.LocalDate

/**
 * `logo` is a drawable id, so it is borrowed from a real sample rather than
 * invented — nothing here depends on which logo it is.
 *
 * There is no counterpart to iOS's `expiryLabelIsAbsentWhenTheDateIsIncomplete`:
 * `expires` is a `LocalDate`, which cannot be half-filled the way a
 * `DateComponents` can, so the case it guards against does not exist here.
 */
private fun makeDeal(expires: LocalDate?) = Deal(
    logo = Deal.samples[0].logo,
    brand = "Test Brand",
    summary = "",
    terms = emptyList(),
    expires = expires,
)

class DealExpiryTest {

    @Test
    fun `has not expired before the end date`() {
        val deal = makeDeal(LocalDate.of(2026, 6, 30))

        assertFalse(deal.hasExpired(LocalDate.of(2026, 6, 29)))
    }

    @Test
    fun `has expired after the end date`() {
        val deal = makeDeal(LocalDate.of(2026, 6, 30))

        assertTrue(deal.hasExpired(LocalDate.of(2026, 7, 1)))
    }

    /**
     * The end date counts as expired from its own start, so the offer is dead
     * during the day it names — matching iOS, where the date resolves to
     * midnight. The label renders that same date as "至 2026/6/30", which reads
     * as inclusive. Pinned as current behaviour on both platforms: if the intent
     * is to keep the code usable all day, `Deal.hasExpired` is what changes and
     * this expectation flips with its iOS twin.
     */
    @Test
    fun `the end date itself counts as expired`() {
        val deal = makeDeal(LocalDate.of(2026, 6, 30))

        assertTrue(deal.hasExpired(LocalDate.of(2026, 6, 30)))
    }

    /**
     * HSBC's offer has no stated end date, and an absent date must never read as
     * "expired" — that would hide a live partnership.
     */
    @Test
    fun `an offer with no end date never expires`() {
        assertFalse(makeDeal(null).hasExpired(LocalDate.of(2099, 1, 1)))
    }
}

class DealSampleTest {

    /** `id` is the brand name, and the deals list is keyed on it. */
    @Test
    fun `sample brands are unique`() {
        val ids = Deal.samples.map { it.id }

        assertEquals(ids.size, ids.toSet().size)
    }

    /**
     * HSBC is an information partnership, not a discount — it is the reason
     * `code` and `headline` are optional, so it stands in for that whole shape.
     */
    @Test
    fun `an information partner carries no code or headline`() {
        val hsbc = Deal.samples.first { it.brand.contains("HSBC") }

        assertNull(hsbc.code)
        assertNull(hsbc.headline)
        assertNotNull(hsbc.link)
        assertNotNull(hsbc.linkTitle)
    }
}
