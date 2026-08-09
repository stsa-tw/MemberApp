package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tw.stsa.memberapp.model.Channel

class ChannelCatalogueTest {

    /**
     * `id` is the persistence key written to preferences. A duplicate would
     * silently merge two channels' subscription state.
     */
    @Test
    fun `ids are unique`() {
        val ids = Channel.all.map { it.id }

        assertEquals(ids.size, ids.toSet().size)
    }

    /**
     * A school channel is matched to a member by `Profile.school`, so its
     * `school` value has to be one of the strings that property can return.
     */
    @Test
    fun `school channels use the same abbreviations profile produces`() {
        val schools = Channel.all.mapNotNull { it.school }.toSet()

        assertTrue(schools.toString(), setOf("NUS", "NTU", "SMU", "SUTD").containsAll(schools))
    }

    /**
     * Schools are identified by their abbreviation rather than an icon — the
     * general-purpose channels are the ones carrying icons.
     */
    @Test
    fun `school channels carry a badge instead of an icon`() {
        for (channel in Channel.all.filter { it.school != null }) {
            assertNull(channel.id, channel.icon)
            assertTrue(channel.id, channel.badge.isNotEmpty())
        }
    }
}

class ChannelDefaultSubscriptionTest {

    @Test
    fun `everyone starts with the all members and freshmen channels`() {
        assertEquals(setOf("all", "freshmen"), Channel.defaultSubscriptions(null))
    }

    @Test
    fun `a known school adds its own channel`() {
        assertEquals(setOf("all", "freshmen", "nus"), Channel.defaultSubscriptions("NUS"))
        assertEquals(setOf("all", "freshmen", "ntu"), Channel.defaultSubscriptions("NTU"))
        assertEquals(setOf("all", "freshmen", "smu"), Channel.defaultSubscriptions("SMU"))
    }

    /**
     * `Profile.school` can return "SUTD", but the catalogue has no SUTD channel,
     * so a SUTD member seeds with the two general channels only. That is the
     * current intent — adding the channel is what changes this, and this
     * expectation is what will tell you to update it.
     */
    @Test
    fun `a school with no channel yet seeds the general channels only`() {
        assertEquals(setOf("all", "freshmen"), Channel.defaultSubscriptions("SUTD"))
    }

    @Test
    fun `an unrecognised school is ignored rather than adding nothing silently wrong`() {
        assertEquals(setOf("all", "freshmen"), Channel.defaultSubscriptions("MIT"))
    }
}
