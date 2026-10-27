import Foundation
import Testing

@testable import MemberApp

struct AttendanceYearTests {
    private func start(_ iso: String) -> String {
        AttendanceStore.academicYearStart(containing: ISO8601DateFormatter().date(from: iso)!)
    }

    @Test func aDateFromJulyOnBelongsToThatYear() {
        #expect(start("2026-10-27T00:00:00+08:00") == "2026-07-01")
        #expect(start("2026-07-01T00:00:00+08:00") == "2026-07-01")
    }

    @Test func aDateBeforeJulyBelongsToTheYearBefore() {
        #expect(start("2027-03-05T12:00:00+08:00") == "2026-07-01")
        #expect(start("2026-06-30T23:59:00+08:00") == "2025-07-01")
    }

    /// Singapore's calendar, not the phone's: midnight on 1 July there is
    /// still 31 July in UTC.
    @Test func readsTheDateInSingapore() {
        #expect(start("2026-06-30T16:30:00Z") == "2026-07-01")
    }
}

struct AttendanceDecodingTests {
    /// How many events the body says were attended; nil if it says nothing usable.
    private func decode(_ json: String) -> Int? {
        AttendanceStore.decode(Data(json.utf8)).map { AttendanceStore.attended(in: $0).count }
    }

    private func missed(_ json: String) -> [Int]? {
        AttendanceStore.decode(Data(json.utf8)).map { AttendanceStore.notAttended(in: $0).map(\.eventID) }
    }

    private func entry(event: Int, checkedIn: Bool, start: String = "2026-10-27T00:36:24.710Z") -> String {
        """
        {"status": "upcoming", "event": {"id": \(event), "title": "x", "start_dt": "\(start)",
         "timezone": "Asia/Singapore"},
         "registration": {"id": 1, "state": "complete", "checked_in": \(checkedIn)}}
        """
    }

    @Test func countsCheckedInEvents() {
        let json = "{\"registrations\": [\(entry(event: 1, checkedIn: true)), \(entry(event: 2, checkedIn: true))]}"
        #expect(decode(json) == 2)
    }

    /// Registered and never came is not participation.
    @Test func skipsRegistrationsThatWereNotCheckedIn() {
        let json = "{\"registrations\": [\(entry(event: 1, checkedIn: true)), \(entry(event: 2, checkedIn: false))]}"
        #expect(decode(json) == 1)
    }

    /// Two forms for one event is one event attended.
    @Test func countsAnEventOnce() {
        let json = "{\"registrations\": [\(entry(event: 5, checkedIn: true)), \(entry(event: 5, checkedIn: true))]}"
        #expect(decode(json) == 1)
    }

    /// A member never checked in to anything is a real answer, not no answer.
    @Test func anEmptyListIsZero() {
        #expect(decode(#"{"registrations": []}"#) == 0)
    }

    @Test func aBodyThatIsNotARegistrationListIsNotAnAnswer() {
        #expect(decode(#"{}"#) == nil)
        #expect(decode(#"{"registrations": "none"}"#) == nil)
        #expect(decode(#"{"error": {"title": "Access Denied"}}"#) == nil)
        #expect(decode("<html>login</html>") == nil)
    }

    /// Registered and not there is listed on its own — but an event they were
    /// at is never also listed as missed, even if a second registration was not.
    @Test func listsWhatWasRegisteredForButNotAttended() {
        let json = "{\"registrations\": [\(entry(event: 1, checkedIn: true)), \(entry(event: 2, checkedIn: false)), \(entry(event: 1, checkedIn: false))]}"
        #expect(missed(json) == [2])
    }

    @Test func attendedAreNewestFirst() throws {
        let json = "{\"registrations\": [\(entry(event: 1, checkedIn: true, start: "2026-09-01T00:00:00Z")), \(entry(event: 2, checkedIn: true, start: "2026-10-01T00:00:00Z"))]}"
        let entries = try #require(AttendanceStore.decode(Data(json.utf8)))
        #expect(AttendanceStore.attended(in: entries).map(\.eventID) == [2, 1])
    }

    @Test func readsTheEventDetails() throws {
        let json = "{\"registrations\": [\(entry(event: 7, checkedIn: true))]}"
        let item = try #require(AttendanceStore.decode(Data(json.utf8))?.first)
        #expect(item.title == "x")
        #expect(item.start != nil)
        #expect(item.timeZone.identifier == "Asia/Singapore")
    }
}
