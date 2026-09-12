import Foundation
import Observation

/// The organiser side of an event: who registered, and what they answered.
///
/// Everything here is read with the *staff member's own* Indico authorization —
/// there is no shared credential and no server of ours in the middle. Indico
/// decides who may see it: the check-in API is `RHManageEventBase`, so a member
/// without management rights on the event gets a 403 and never sees the door.
/// That 403 is the permission model; the app only asks.
///
/// Reading needs only `read:everything`. Recording a check-in is a `PATCH`, and
/// Indico accepts only `registrants` or `full:everything` for anything that is
/// not a GET — so [checkIn] needs the wider grant, and asks for it on the door
/// screen alone. Members are never re-authorized for it: Indico extends an
/// existing authorization in place, so only the staffer who opens the door
/// consents, and only once. See `IndicoAuthConfiguration.checkinScopes`.
@MainActor
@Observable
final class CheckinStore {
    enum Access: Equatable {
        case unknown
        case checking
        /// This member manages the event and may read its registrations.
        case allowed
        case denied
    }

    /// A registrant, plus the form they belong to — the detail lookup needs both.
    struct Entry: Equatable, Identifiable {
        let formID: Int
        let registration: CheckinRegistration
        var id: Int { registration.id }
    }

    /// One registration form on an event.
    ///
    /// An event can carry several, and Indico keeps them genuinely apart: a
    /// registration lives inside exactly one form, and `checked_in` is a column
    /// on the registration. 烤場集合 runs a 報名表 and a 遊覽車報名表, so a member
    /// who booked the coach as well holds two registrations, two tickets, and
    /// two check-ins to be made at two different desks.
    ///
    /// Which is why a door is opened per form rather than per event. Pouring
    /// them into one list gave a roster where the same person appeared twice, a
    /// denominator no door could ever reach, and a scan that recorded
    /// attendance against whichever of the two Indico happened to return first.
    struct Form: Identifiable, Equatable {
        let id: Int
        let title: String
    }

    private(set) var access: [String: Access] = [:]
    private(set) var roster: [String: [Entry]] = [:]
    /// The event's forms, learned from the same probe that answers whether this
    /// member may read the event at all. Observed rather than private because
    /// the organiser screen shows one section per form and names each one.
    private(set) var forms: [String: [Form]] = [:]
    private(set) var isLoadingRoster = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    /// How many check-ins this app has written for an event, used only to tell
    /// a refetch that started earlier that it is now out of date.
    @ObservationIgnored private var writes: [String: Int] = [:]

    private static let indicoHost = "event.stsa.tw"
    private static let host = "https://\(indicoHost)"

    func access(for eventID: String) -> Access { access[eventID] ?? .unknown }

    func forms(for eventID: String) -> [Form] { forms[eventID] ?? [] }

    func entries(for eventID: String) -> [Entry] { roster[eventID] ?? [] }

    /// One form's registrants — the list a door actually works from.
    func entries(for eventID: String, formID: Int) -> [Entry] {
        entries(for: eventID).filter { $0.formID == formID }
    }

    /// That list minus the cancelled rows — the people a door is waiting for.
    ///
    /// Withdrawn and rejected registrations stay on Indico's list, because
    /// `~is_deleted` is the only filter its API applies, and out of every count
    /// the app shows, because nobody is expecting them. Indico's own
    /// `active_registration_count` draws the line in the same place, which is
    /// what keeps these numbers comparable with its management page.
    func expected(eventID: String, formID: Int) -> [Entry] {
        entries(for: eventID, formID: formID).filter { !$0.registration.isCancelled }
    }

    /// Asks Indico whether this member manages the event, which is the same
    /// request that fetches the form ids the roster needs.
    func probe(eventID: String, using indico: IndicoAuthManager) async {
        guard access(for: eventID) == .unknown, indico.isLinked else { return }
        access[eventID] = .checking

        guard let url = URL(string: "\(Self.host)/api/checkin/event/\(eventID)/forms/") else {
            access[eventID] = .denied
            return
        }

        do {
            let request = try indico.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let forms = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                access[eventID] = .denied
                return
            }

            self.forms[eventID] = forms.compactMap { raw -> Form? in
                guard let id = raw["id"] as? Int else { return nil }
                let title = (raw["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                return Form(id: id, title: title)
            }
            access[eventID] = self.forms[eventID]?.isEmpty == false ? .allowed : .denied
        } catch {
            access[eventID] = .denied
        }
    }

    /// Pulls the registrant list once, so a scan is a lookup rather than a
    /// request. The list deliberately carries no answers — Indico excludes them
    /// from the list endpoint — so those are fetched per person on scan.
    func loadRoster(eventID: String, using indico: IndicoAuthManager) async {
        guard roster[eventID] == nil else { return }
        await fetchRoster(eventID: eventID, using: indico)
    }

    /// Asks Indico again, for the door that is not the only one.
    ///
    /// The count on this phone moves when *this* phone records a check-in, and
    /// that is all it knew: a second 幹部 on a second phone, or anyone using
    /// Indico's own app, moved a number this one never saw. So the list is
    /// re-asked when the door screen opens and whenever the roster is pulled
    /// down, rather than being fetched once and believed for the rest of the
    /// event.
    func refreshRoster(eventID: String, using indico: IndicoAuthManager) async {
        await fetchRoster(eventID: eventID, using: indico)
    }

    private func fetchRoster(eventID: String, using indico: IndicoAuthManager) async {
        let eventForms = forms(for: eventID)
        guard !eventForms.isEmpty else { return }

        isLoadingRoster = true
        defer { isLoadingRoster = false }

        // Read before the requests go out and compared after they come back: a
        // check-in recorded while this was in flight is newer than anything the
        // response can contain, and letting a stale list land on top of it would
        // take the person back off the screen they were just admitted on.
        let generation = writes[eventID, default: 0]

        var entries: [Entry] = []
        var isComplete = true
        for form in eventForms {
            guard let url = URL(string:
                "\(Self.host)/api/checkin/event/\(eventID)/forms/\(form.id)/registrations/")
            else { isComplete = false; continue }

            do {
                let request = try indico.authorizedRequest(for: url)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    isComplete = false
                    continue
                }
                entries += CheckinDecoder.list(data).map { Entry(formID: form.id, registration: $0) }
            } catch {
                isComplete = false
                errorMessage = error.localizedDescription
            }
        }

        guard writes[eventID, default: 0] == generation else { return }

        // A refresh that could not read every form must not shorten a list the
        // door is working from — the venue's wifi dropping should cost the
        // count its freshness, not its rows.
        guard isComplete || roster[eventID] == nil else { return }

        roster[eventID] = entries
    }

    /// Finds a scanned member in the list of the form whose door is open.
    ///
    /// Matched on email, which is the only thing MembershipAPI and Indico both
    /// know about a person. Case-insensitive because the two do not agree on it;
    /// someone who registered under a different address than their STSA account
    /// will not be found, and the screen says so rather than implying they never
    /// registered.
    ///
    /// Scoped to one form on purpose. A member card names a person, and one
    /// person can hold a registration in several of an event's forms — matching
    /// across all of them recorded the coach passenger's arrival against the
    /// 報名表, or the other way about, depending on nothing.
    func entry(email: String, eventID: String, formID: Int) -> Entry? {
        Self.match(email: email, in: entries(for: eventID, formID: formID))
    }

    /// The event's *other* forms this address is registered in.
    ///
    /// What the door says instead of "not registered" when the member is in the
    /// event but standing at the wrong desk — the case that reads as a duplicate
    /// from the outside and is nothing of the kind.
    func otherForms(email: String, eventID: String, excluding formID: Int) -> [Form] {
        let needle = Self.normalised(email)
        guard !needle.isEmpty else { return [] }

        let found = Set(
            entries(for: eventID)
                .filter { $0.formID != formID && Self.normalised($0.registration.email) == needle }
                .map(\.formID)
        )
        return forms(for: eventID).filter { found.contains($0.id) }
    }

    /// Picks the registration a scan means, out of however many one form holds
    /// for a single address.
    ///
    /// One form can still hold two. Withdrawing and registering again leaves the
    /// old row behind — Indico allows the second one *because* the first is
    /// withdrawn — and a manager adding somebody by hand is warned about the
    /// clash rather than stopped. So the choice is made deliberately instead of
    /// by list order:
    ///
    /// - an admissible one that is already checked in, so a second scan of the
    ///   same person reads 已經報到過 rather than quietly offering to admit
    ///   their other copy and counting one arrival twice;
    /// - failing that an admissible one, since a withdrawn leftover is not the
    ///   answer to "is this person expected";
    /// - failing that the first, so the screen can explain what it found instead
    ///   of claiming they never registered.
    ///
    /// Pure and static so it can be tested without a roster to fetch. Android's
    /// `CheckinSession.match` is the same rule.
    static func match(email: String, in entries: [Entry]) -> Entry? {
        let needle = normalised(email)
        guard !needle.isEmpty else { return nil }

        let matches = entries.filter { normalised($0.registration.email) == needle }
        return matches.first { $0.registration.isAdmissible && $0.registration.checkedIn }
            ?? matches.first { $0.registration.isAdmissible }
            ?? matches.first
    }

    private static func normalised(_ email: String) -> String {
        email.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Fetches one registrant's answers, which the roster does not carry.
    func details(for entry: Entry, eventID: String, using indico: IndicoAuthManager) async -> CheckinRegistration? {
        guard let url = URL(string:
            "\(Self.host)/api/checkin/event/\(eventID)/forms/\(entry.formID)/registrations/\(entry.registration.id)")
        else { return nil }

        do {
            let request = try indico.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return CheckinDecoder.one(data)
        } catch {
            return nil
        }
    }

    /// Resolves a scanned ticket to its registration.
    ///
    /// Unlike a member card, this needs no roster and no email match, so it
    /// works for someone whose Indico address is not their STSA one.
    ///
    /// Indico looks the ticket up globally — `/api/checkin/ticket/<uuid>` carries
    /// no event — and applies the permission check to whatever event it belongs
    /// to. A staffer who manages two events would otherwise resolve, and check
    /// in, a ticket for the wrong one, so the event is compared here.
    func registration(
        ticket: ScannedCode.Ticket,
        eventID: String,
        using indico: IndicoAuthManager
    ) async -> TicketOutcome {
        guard ticket.host == Self.indicoHost else { return .foreignInstance(ticket.host) }
        guard ticket.accompanyingPersonID == nil else { return .accompanyingPerson }

        let uuid = ticket.checkinSecret.uuidString.lowercased()
        guard let url = URL(string: "\(Self.host)/api/checkin/ticket/\(uuid)") else {
            return .unreadable
        }

        do {
            let request = try indico.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard status == 200, let registration = CheckinDecoder.one(data) else {
                return status == 403 ? .notPermitted : .unknownTicket
            }
            guard String(registration.eventID) == eventID else { return .otherEvent }
            return .found(registration)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// What a scanned ticket turned out to be.
    enum TicketOutcome: Equatable {
        case found(CheckinRegistration)
        /// A ticket this Indico has never issued.
        case unknownTicket
        /// A real ticket, for an event this door is not.
        case otherEvent
        /// Issued by a different Indico instance entirely.
        case foreignInstance(String)
        /// An accompanying person's ticket, which has no registration.
        case accompanyingPerson
        /// The staffer does not manage the event the ticket belongs to.
        case notPermitted
        case unreadable
        case unreachable(String)
    }

    /// Records attendance, and folds Indico's answer back into the roster so the
    /// count and any later scan of the same person are right without refetching.
    ///
    /// Idempotent: PATCHing `checked_in` that is already true is accepted and
    /// keeps the original `checked_in_dt`, so a double scan costs nothing.
    func checkIn(
        _ registration: CheckinRegistration,
        eventID: String,
        using indico: IndicoAuthManager
    ) async -> CheckinResult {
        guard registration.isAdmissible else { return .notAdmissible }
        guard indico.canRecordCheckin else { return .needsAuthorization }

        guard let url = URL(string:
            "\(Self.host)/api/checkin/event/\(registration.eventID)"
            + "/forms/\(registration.formID)/registrations/\(registration.id)")
        else { return .failed(String(localized: "無法組出報到網址。")) }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            var request = try indico.authorizedRequest(for: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["checked_in": true])

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // 403 here, after a roster loaded fine, means the grant is too narrow
            // rather than the event being someone else's — reading worked.
            if status == 403 { return .needsAuthorization }
            guard status == 200, let updated = CheckinDecoder.one(data) else {
                return .failed(String(localized: "Indico 回應 HTTP \(status)。"))
            }

            replace(updated, eventID: eventID)
            return .recorded(updated)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    enum CheckinResult: Equatable {
        case recorded(CheckinRegistration)
        /// Withdrawn or rejected — not someone to admit.
        case notAdmissible
        /// The Indico authorization is read-only; the staffer must grant
        /// `registrants` before anything can be written.
        case needsAuthorization
        case failed(String)
    }

    private func replace(_ registration: CheckinRegistration, eventID: String) {
        writes[eventID, default: 0] += 1

        guard var entries = roster[eventID],
              let index = entries.firstIndex(where: { $0.registration.id == registration.id })
        else { return }
        entries[index] = Entry(formID: entries[index].formID, registration: registration)
        roster[eventID] = entries
    }

    /// Called when the member signs out — a roster is other people's data.
    func clear() {
        access.removeAll()
        roster.removeAll()
        forms.removeAll()
        writes.removeAll()
        errorMessage = nil
    }
}
