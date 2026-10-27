package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import tw.stsa.memberapp.feature.account.AttendanceStore
import java.time.LocalDate

class AttendanceStoreTest {
    /** How many events the body says were attended; null if it says nothing usable. */
    private fun attended(body: String): Int? =
        AttendanceStore.decode(body)?.let { AttendanceStore.attended(it).size }

    private fun entry(event: Int, checkedIn: Boolean, start: String = "2026-10-27T00:36:24.710Z") =
        """{"status": "upcoming", "event": {"id": $event, "title": "x", "start_dt": "$start",
            "timezone": "Asia/Singapore"},
            "registration": {"id": 1, "state": "complete", "checked_in": $checkedIn}}"""

    private fun list(vararg entries: String) = """{"registrations": [${entries.joinToString(",")}]}"""

    @Test
    fun countsCheckedInEvents() {
        assertEquals(2, attended(list(entry(1, true), entry(2, true))))
    }

    /** Registered and never came is not participation. */
    @Test
    fun skipsRegistrationsThatWereNotCheckedIn() {
        assertEquals(1, attended(list(entry(1, true), entry(2, false))))
    }

    /** Two forms for one event is one event attended. */
    @Test
    fun countsAnEventOnce() {
        assertEquals(1, attended(list(entry(5, true), entry(5, true))))
    }

    /** A member never checked in to anything is a real answer, not no answer. */
    @Test
    fun anEmptyListIsZero() {
        assertEquals(0, attended("""{"registrations": []}"""))
    }

    @Test
    fun aBodyThatIsNotARegistrationListIsNotAnAnswer() {
        assertNull(attended("{}"))
        assertNull(attended("""{"registrations": "none"}"""))
        assertNull(attended("""{"error": {"title": "Access Denied"}}"""))
        assertNull(attended("<html>login</html>"))
    }

    @Test
    fun aMalformedEntryIsNotAnAnswer() {
        assertNull(attended("""{"registrations": [{"event": {"id": "1"}, "registration": {"checked_in": true}}]}"""))
        assertNull(attended("""{"registrations": [{"event": {"id": 1}, "registration": {"checked_in": "yes"}}]}"""))
    }

    @Test
    fun aDateFromJulyOnBelongsToThatYear() {
        assertEquals("2026-07-01", AttendanceStore.academicYearStart(LocalDate.of(2026, 10, 27)))
        assertEquals("2026-07-01", AttendanceStore.academicYearStart(LocalDate.of(2026, 7, 1)))
    }

    @Test
    fun aDateBeforeJulyBelongsToTheYearBefore() {
        assertEquals("2026-07-01", AttendanceStore.academicYearStart(LocalDate.of(2027, 3, 5)))
        assertEquals("2025-07-01", AttendanceStore.academicYearStart(LocalDate.of(2026, 6, 30)))
    }

    /** Registered and not there is listed on its own — but never an event they were at. */
    @Test
    fun listsWhatWasRegisteredForButNotAttended() {
        val entries = AttendanceStore.decode(list(entry(1, true), entry(2, false), entry(1, false)))!!
        assertEquals(listOf(2), AttendanceStore.notAttended(entries).map { it.eventId })
    }

    @Test
    fun attendedAreNewestFirst() {
        val entries = AttendanceStore.decode(
            list(entry(1, true, "2026-09-01T00:00:00Z"), entry(2, true, "2026-10-01T00:00:00Z")),
        )!!
        assertEquals(listOf(2, 1), AttendanceStore.attended(entries).map { it.eventId })
    }

    @Test
    fun readsTheEventDetails() {
        val item = AttendanceStore.decode(list(entry(7, true)))!!.single()
        assertEquals("x", item.title)
        assertEquals("Asia/Singapore", item.zone.id)
        assert(item.start != null)
    }
}
