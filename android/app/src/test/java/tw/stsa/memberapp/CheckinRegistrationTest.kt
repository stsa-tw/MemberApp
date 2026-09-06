package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tw.stsa.memberapp.feature.checkin.CheckinSession
import tw.stsa.memberapp.model.CheckinRegistration
import java.util.UUID

private fun makeRegistration(
    id: Int = 1,
    email: String = "member@u.nus.edu",
    fullName: String = "陳小明",
    state: String = "complete",
    checkedIn: Boolean = false,
    checkedInAt: String? = null,
    eventId: Int = 12,
    regformId: Int = 3,
    checkinSecret: String? = "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
): CheckinRegistration {
    val fields = buildList {
        add(""""id": $id""")
        add(""""regform_id": $regformId""")
        add(""""event_id": $eventId""")
        add(""""full_name": "$fullName"""")
        add(""""email": "$email"""")
        add(""""state": "$state"""")
        add(""""checked_in": $checkedIn""")
        if (checkedInAt != null) add(""""checked_in_dt": "$checkedInAt"""")
        if (checkinSecret != null) add(""""checkin_secret": "$checkinSecret"""")
    }
    return CheckinRegistration.decode("{${fields.joinToString(",")}}")
}

class CheckinRegistrationDecodingTest {

    @Test
    fun `decodes the fields the door needs`() {
        val registration = makeRegistration(checkedIn = true, checkedInAt = "2026-09-05T10:30:00+00:00")
        assertEquals(1, registration.id)
        assertEquals("陳小明", registration.fullName)
        assertEquals("member@u.nus.edu", registration.email)
        assertEquals(CheckinRegistration.State.COMPLETE, registration.state)
        assertTrue(registration.checkedIn)
        assertNotNull(registration.checkedInAt)
        assertEquals(UUID.fromString("3f2504e0-4f89-11d3-9a0c-0305e82c3301"), registration.checkinSecret)
    }

    /**
     * marshmallow includes fractional seconds only when the stored value has
     * them, so both spellings arrive from the same instance.
     */
    @Test
    fun `decodes both timestamp spellings`() {
        assertNotNull(makeRegistration(checkedInAt = "2026-09-05T10:30:00+00:00").checkedInAt)
        assertNotNull(makeRegistration(checkedInAt = "2026-09-05T10:30:00.123456+00:00").checkedInAt)
    }

    /** A registration that has never been through has no `checked_in_dt`. */
    @Test
    fun `tolerates a missing timestamp`() {
        assertNull(makeRegistration(checkedInAt = null).checkedInAt)
    }

    /** An unknown state must not fail the whole list and strand a worker. */
    @Test
    fun `falls back for an unknown state`() {
        assertEquals(CheckinRegistration.State.UNKNOWN, makeRegistration(state = "some_future_state").state)
    }

    /**
     * Withdrawn and rejected registrations still come back in the list; checking
     * one in would record attendance for someone who should not be admitted.
     * Unpaid is admissible — payment is not the door's problem.
     */
    @Test
    fun `knows who may be admitted`() {
        assertTrue(makeRegistration(state = "complete").isAdmissible)
        assertTrue(makeRegistration(state = "unpaid").isAdmissible)
        assertFalse(makeRegistration(state = "withdrawn").isAdmissible)
        assertFalse(makeRegistration(state = "rejected").isAdmissible)
        assertFalse(makeRegistration(state = "pending").isAdmissible)
    }
}

class CheckinMatchingTest {

    @Test
    fun `matches a member to their registration`() {
        val registrations = listOf(
            makeRegistration(id = 1, email = "other@u.nus.edu"),
            makeRegistration(id = 2, email = "member@u.nus.edu"),
        )
        assertEquals(2, CheckinSession.match("member@u.nus.edu", registrations)?.id)
    }

    /**
     * Indico lowercases addresses; authentik does not. Without this, a member
     * whose authentik address is capitalised silently fails to match.
     */
    @Test
    fun `matches regardless of case`() {
        val registrations = listOf(makeRegistration(id = 2, email = "member@u.nus.edu"))
        assertEquals(2, CheckinSession.match("Member@U.NUS.edu ", registrations)?.id)
    }

    /**
     * A member who registered under a different address is a miss, not a wrong
     * match — the worker falls back to scanning their ticket.
     */
    @Test
    fun `does not guess when no address matches`() {
        val registrations = listOf(makeRegistration(id = 1, email = "someone@u.nus.edu"))
        assertNull(CheckinSession.match("member@u.nus.edu", registrations))
    }

    /**
     * One address can hold several registrations in a form. The live one is the
     * useful answer; a withdrawn leftover is not.
     */
    @Test
    fun `prefers an admissible registration`() {
        val registrations = listOf(
            makeRegistration(id = 1, email = "member@u.nus.edu", state = "withdrawn"),
            makeRegistration(id = 2, email = "member@u.nus.edu", state = "complete"),
        )
        assertEquals(2, CheckinSession.match("member@u.nus.edu", registrations)?.id)
    }

    @Test
    fun `ignores an empty address`() {
        val registrations = listOf(makeRegistration(id = 1, email = ""))
        assertNull(CheckinSession.match("", registrations))
    }
}
