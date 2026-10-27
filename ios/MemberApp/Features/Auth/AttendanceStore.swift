import Foundation
import Observation

/// How many events the signed-in member has been checked in to.
///
/// Read from the STSA plugin's `GET /api/stsa/registered-events` on Indico,
/// which answers for the caller alone — a member's own token sees their own
/// registrations and their `checked_in` flag, which the organiser-only
/// check-in API would not have let them read.
///
/// Deliberately **not** filtered with `status=checked_in`. That is the event's
/// status for this member, and an event that is still upcoming or ongoing keeps
/// that status even once they have been checked in — so the filter dropped
/// someone who had just been to an event that had not finished. The flag on
/// each registration is what says whether they were there.
///
/// Only this academic year's events are counted, so the number means "how
/// involved were you lately" rather than a total that only ever grows. The year
/// turns over on 1 July, and the window is
/// handed to Indico as `from` so it does the filtering.
///
/// Counts **events**, not registrations: two forms for one event, or two
/// check-ins, are still one event attended. Registered-but-absent does not
/// count — padding the number with them would be the wrong kind of generous.
///
/// Needs the Indico link. Without one there is nothing to ask, so nothing is
/// shown rather than a zero that claims to know.
@MainActor
@Observable
final class AttendanceStore {
    /// What Indico last said, one entry per registration. Nil until it has
    /// answered, and again after sign-out. Never a stand-in empty list: "we
    /// have not been told" and "none yet" are different things, and only the
    /// second belongs on the screen.
    private(set) var entries: [Entry]?

    /// Events the member was checked in to, newest first, each once.
    var attended: [Entry]? {
        entries.map { Self.attended(in: $0) }
    }

    /// Events they registered for and were not checked in to — yet to happen,
    /// under way, or missed — soonest first. An event they *were* checked in to
    /// never appears here, even if a second registration for it was not.
    var notAttended: [Entry]? {
        entries.map { Self.notAttended(in: $0) }
    }

    var count: Int? {
        attended?.count
    }

    private static let endpoint = "https://event.stsa.tw/api/stsa/registered-events"

    /// The first day of the academic year that `date` falls in, as the plain
    /// date Indico takes for `from` — "a date alone is the start of that day".
    /// Read in Singapore's calendar, which is also what Indico's own timezone
    /// is here, so the day does not shift with wherever the phone happens to be.
    static func academicYearStart(containing date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.month! >= 7 ? parts.year! : parts.year! - 1
        return String(format: "%04d-07-01", year)
    }

    /// Leaves the previous answer alone on any failure. A flaky connection should
    /// not take a number off the screen that was right a minute ago, and a
    /// token Indico will not accept for this endpoint simply never shows one.
    func load(using indico: IndicoAuthManager) async {
        guard indico.isLinked else { return }
        do {
            let from = Self.academicYearStart(containing: .now)
            guard let url = URL(string: "\(Self.endpoint)?from=\(from)") else { return }
            let request = try indico.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = Self.decode(data)
            else { return }
            entries = decoded
        } catch {
            // Nothing to report: the row stays as it was.
        }
    }

    /// The previous member's number must not greet the next one.
    func clear() {
        entries = nil
    }

    /// One registration, as much of it as the screen shows.
    struct Entry: Identifiable, Equatable {
        /// Indico's event id. Two registrations for one event share it.
        let eventID: Int
        let title: String
        let start: Date?
        let timeZone: TimeZone
        let url: URL?
        /// Indico's own word for where the event stands for this member:
        /// `upcoming`, `ongoing`, `checked_in`, `no_show`, `pending`.
        let status: String
        let checkedIn: Bool

        var id: Int { eventID }
    }

    /// The registrations in the body, or nil if it is not a registration list at
    /// all. An entry without an integer event id or a boolean `checked_in` makes
    /// the whole answer unusable rather than quietly uncounted.
    static func decode(_ data: Data) -> [Entry]? {
        guard let list = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return list.registrations.map { item in
            Entry(
                eventID: item.event.id,
                title: item.event.title ?? "",
                start: item.event.startDt.flatMap(Self.date(from:)),
                timeZone: item.event.timezone.flatMap(TimeZone.init(identifier:))
                    ?? TimeZone(identifier: "Asia/Singapore")!,
                url: item.event.url.flatMap(URL.init(string:)),
                status: item.status ?? "",
                checkedIn: item.registration.checkedIn
            )
        }
    }

    static func attended(in entries: [Entry]) -> [Entry] {
        newestFirst(once(entries.filter(\.checkedIn)))
    }

    static func notAttended(in entries: [Entry]) -> [Entry] {
        let attendedIDs = Set(entries.filter(\.checkedIn).map(\.eventID))
        return once(entries.filter { !attendedIDs.contains($0.eventID) })
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// Two forms for one event, or two check-ins, are one event.
    private static func once(_ entries: [Entry]) -> [Entry] {
        var seen = Set<Int>()
        return entries.filter { seen.insert($0.eventID).inserted }
    }

    private static func newestFirst(_ entries: [Entry]) -> [Entry] {
        entries.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    /// Indico writes `2026-10-27T00:36:24.710Z`; tolerate the form without
    /// fractional seconds too.
    private static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private struct Response: Decodable {
        let registrations: [Item]
    }

    private struct Item: Decodable {
        let status: String?
        let event: Event
        let registration: Registration
    }

    private struct Event: Decodable {
        let id: Int
        let title: String?
        let url: String?
        let startDt: String?
        let timezone: String?

        enum CodingKeys: String, CodingKey {
            case id, title, url, timezone
            case startDt = "start_dt"
        }
    }

    private struct Registration: Decodable {
        let checkedIn: Bool

        enum CodingKeys: String, CodingKey {
            case checkedIn = "checked_in"
        }
    }
}
