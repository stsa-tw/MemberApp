import Foundation
import Testing

@testable import MemberApp

/// Base64 of the 16 raw bytes of 3F2504E0-4F89-11D3-9A0C-0305E82C3301, which is
/// how Indico writes a ticket UUID into a QR.
private let ticketSecret = "PyUE4E+JEdOaDAMF6CwzAQ=="
private let ticketUUID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
private let personSecret = "C34PShwtTl+KmwwdLj9KWw=="

private func ticketQR(version: Int = 2,
                      host: String = "event.stsa.tw",
                      secret: String = ticketSecret,
                      person: String? = nil) -> String {
    var fields = ["\(version)", "\"\(host)\"", "\"\(secret)\""]
    if let person { fields.append("\"\(person)\"") }
    return "{\"i\":[\(fields.joined(separator: ","))]}"
}

struct ScannedCodeTests {

    // MARK: - Member cards

    @Test func readsAMemberCard() {
        #expect(ScannedCode.parse("stsa$abcdefghij0123456789") == .memberCard("abcdefghij0123456789"))
    }

    /// Scanners and clipboards add trailing newlines.
    @Test func ignoresSurroundingWhitespace() {
        #expect(ScannedCode.parse(" stsa$abcdefghij0123456789\n") == .memberCard("abcdefghij0123456789"))
    }

    /// The code is interpolated into a URL path, so a payload carrying our
    /// prefix and something else is refused rather than sent.
    @Test func rejectsAMemberCodeThatIsNotAlphanumeric() {
        #expect(ScannedCode.parse("stsa$../me") == nil)
        #expect(ScannedCode.parse("stsa$abc-def") == nil)
        #expect(ScannedCode.parse("stsa$") == nil)
    }

    // MARK: - Indico tickets

    @Test func readsATicket() {
        guard case .ticket(let ticket) = ScannedCode.parse(ticketQR()) else {
            Issue.record("expected a ticket")
            return
        }
        #expect(ticket.checkinSecret == ticketUUID)
        #expect(ticket.host == "event.stsa.tw")
        #expect(ticket.accompanyingPersonID == nil)
    }

    /// Indico strips `https://` to save bytes but leaves `http://` alone, and
    /// the host is compared against ours before any request is made.
    @Test func normalisesTheIssuerHost() {
        for issuer in ["event.stsa.tw", "https://event.stsa.tw", "http://event.stsa.tw", "event.stsa.tw/"] {
            guard case .ticket(let ticket) = ScannedCode.parse(ticketQR(host: issuer)) else {
                Issue.record("expected a ticket for \(issuer)")
                return
            }
            #expect(ticket.host == "event.stsa.tw")
        }
    }

    /// A fourth element means the ticket belongs to an accompanying person, who
    /// has no registration of their own.
    @Test func readsAnAccompanyingPersonTicket() {
        guard case .ticket(let ticket) = ScannedCode.parse(ticketQR(person: personSecret)) else {
            Issue.record("expected a ticket")
            return
        }
        #expect(ticket.accompanyingPersonID == UUID(uuidString: "0B7E0F4A-1C2D-4E5F-8A9B-0C1D2E3F4A5B"))
    }

    /// Indico bumps the version when the field layout changes. Parsing a future
    /// one hopefully would put the wrong bytes in the UUID slot, and that
    /// surfaces as the wrong person rather than as an error.
    @Test func refusesAnUnknownTicketVersion() {
        #expect(ScannedCode.parse(ticketQR(version: 3)) == nil)
        #expect(ScannedCode.parse(ticketQR(version: 1)) == nil)
    }

    /// The site-access plugin adds its own key alongside `i`. Ignoring unknown
    /// keys is what keeps that from looking like a corrupt ticket.
    @Test func ignoresExtraKeysFromPlugins() {
        let qr = "{\"i\":[2,\"event.stsa.tw\",\"\(ticketSecret)\"],\"adams\":\"https://adams.example\"}"
        #expect(ScannedCode.parse(qr) != nil)
    }

    @Test func rejectsASecretThatIsNotSixteenBytes() {
        #expect(ScannedCode.parse(ticketQR(secret: "PyUE4E+JEdM=")) == nil)
        #expect(ScannedCode.parse(ticketQR(secret: "not base64 at all")) == nil)
    }

    // MARK: - Everything else

    @Test func rejectsCodesThatAreNeither() {
        #expect(ScannedCode.parse("https://event.stsa.tw/event/12/") == nil)
        #expect(ScannedCode.parse("") == nil)
        #expect(ScannedCode.parse("{\"i\":[2]}") == nil)
        #expect(ScannedCode.parse("{}") == nil)
    }
}

struct CheckinAdmissibilityTests {
    private func registration(state: String) -> CheckinRegistration? {
        CheckinDecoder.registration(from: [
            "id": 1, "event_id": 12, "regform_id": 3,
            "full_name": "陳小明", "email": "member@u.nus.edu",
            "state": state, "checked_in": false,
        ])
    }

    /// Withdrawn and rejected registrations still come back in the roster;
    /// recording attendance for one would put someone in the room the organiser
    /// removed. Unpaid is admissible — payment is not the door's problem.
    @Test func knowsWhoMayBeAdmitted() {
        #expect(registration(state: "complete")?.isAdmissible == true)
        #expect(registration(state: "unpaid")?.isAdmissible == true)
        #expect(registration(state: "withdrawn")?.isAdmissible == false)
        #expect(registration(state: "rejected")?.isAdmissible == false)
        #expect(registration(state: "pending")?.isAdmissible == false)
    }

    /// The PATCH is addressed with these, and a ticket scanned at the wrong door
    /// is caught by comparing the event — so a decode that quietly dropped them
    /// would break both.
    @Test func carriesTheIdsTheWritePathNeeds() {
        let registration = registration(state: "complete")
        #expect(registration?.eventID == 12)
        #expect(registration?.formID == 3)
    }
}


/// The event runs 13:30–15:30 on 2026-08-15 in the fixture below.
struct CheckinWindowTests {
    private func event() throws -> IndicoEvent {
        let json = """
        {"id": 10, "title": "工作坊",
         "startDate": {"date": "2026-08-15", "time": "13:30:00", "tz": "Asia/Singapore"},
         "endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}}
        """
        return try JSONDecoder().decode(IndicoEvent.self, from: Data(json.utf8))
    }

    private func moment(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    @Test func isOpenWhileTheEventRuns() throws {
        #expect(try event().isWithinCheckinWindow(at: moment("2026-08-15T14:00:00+08:00")))
    }

    /// The whole point of not using `isUpcoming`: events overrun, and the door
    /// must not close on a staffer who is still working it.
    @Test func staysOpenAfterTheScheduledEnd() throws {
        let event = try event()
        #expect(event.isWithinCheckinWindow(at: moment("2026-08-15T15:35:00+08:00")))
        #expect(event.isWithinCheckinWindow(at: moment("2026-08-16T09:00:00+08:00")))
    }

    /// Someone missed at the door is reconciled the same day or the next one,
    /// not a week later.
    @Test func closesOnceTheGraceHasPassed() throws {
        #expect(try !event().isWithinCheckinWindow(at: moment("2026-08-17T09:00:00+08:00")))
    }

    /// Staff arrive before the first attendee, but a door on an event months
    /// away is only clutter — and a pointless request to Indico.
    @Test func opensShortlyBeforeTheStart() throws {
        let event = try event()
        #expect(event.isWithinCheckinWindow(at: moment("2026-08-15T12:00:00+08:00")))
        #expect(!event.isWithinCheckinWindow(at: moment("2026-08-15T10:00:00+08:00")))
        #expect(!event.isWithinCheckinWindow(at: moment("2026-06-01T12:00:00+08:00")))
    }
}
