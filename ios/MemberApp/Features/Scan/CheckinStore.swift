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
/// Read-only. Marking someone checked in is a `PATCH`, and Indico accepts only
/// `full:everything` or `registrants` for anything that is not a GET — this app
/// holds `read:everything`. Recording check-ins would mean widening the grant on
/// the Indico application and re-authorizing every member, which is a decision
/// rather than a detail.
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
    private(set) var errorMessage: String?

    @ObservationIgnored private var formIDs: [String: [Int]] = [:]

    private static let host = "https://event.stsa.tw"

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

    /// Called when the member signs out — a roster is other people's data.
    func clear() {
        access.removeAll()
        roster.removeAll()
        formIDs.removeAll()
        errorMessage = nil
    }
}
