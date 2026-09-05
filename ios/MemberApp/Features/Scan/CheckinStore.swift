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

    private(set) var access: [String: Access] = [:]
    private(set) var roster: [String: [Entry]] = [:]
    private(set) var isLoadingRoster = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var formIDs: [String: [Int]] = [:]

    private static let indicoHost = "event.stsa.tw"
    private static let host = "https://\(indicoHost)"

    func access(for eventID: String) -> Access { access[eventID] ?? .unknown }

    func entries(for eventID: String) -> [Entry] { roster[eventID] ?? [] }

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

            formIDs[eventID] = forms.compactMap { $0["id"] as? Int }
            access[eventID] = formIDs[eventID]?.isEmpty == false ? .allowed : .denied
        } catch {
            access[eventID] = .denied
        }
    }

    /// Pulls the registrant list once, so a scan is a lookup rather than a
    /// request. The list deliberately carries no answers — Indico excludes them
    /// from the list endpoint — so those are fetched per person on scan.
    func loadRoster(eventID: String, using indico: IndicoAuthManager) async {
        guard roster[eventID] == nil, let forms = formIDs[eventID] else { return }

        isLoadingRoster = true
        defer { isLoadingRoster = false }

        var entries: [Entry] = []
        for formID in forms {
            guard let url = URL(string:
                "\(Self.host)/api/checkin/event/\(eventID)/forms/\(formID)/registrations/")
            else { continue }

            do {
                let request = try indico.authorizedRequest(for: url)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                entries += CheckinDecoder.list(data).map { Entry(formID: formID, registration: $0) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        roster[eventID] = entries
    }

    /// Finds a scanned member in the roster.
    ///
    /// Matched on email, which is the only thing MembershipAPI and Indico both
    /// know about a person. Case-insensitive because the two do not agree on it;
    /// someone who registered under a different address than their STSA account
    /// will not be found, and the screen says so rather than implying they never
    /// registered.
    func entry(email: String, eventID: String) -> Entry? {
        let needle = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        return entries(for: eventID).first { $0.registration.email == needle }
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
        formIDs.removeAll()
        errorMessage = nil
    }
}
