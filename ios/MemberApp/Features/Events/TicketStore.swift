import Foundation
import Observation

/// Works out whether the member holds a ticket for an event, and where to open it.
///
/// Indico has no "my registrations" endpoint, and its check-in API needs
/// `registration_checkin` on the event — an organiser permission a member does
/// not have. What a member *can* do is read any GET endpoint as themselves, so
/// asking for their own ticket is both the answer to "am I registered?" and the
/// way to the ticket, in one request:
///
/// | Indico's answer | What it means |
/// |---|---|
/// | 200 `application/pdf` | registered, complete, ticket issued |
/// | 403 | not registered — *or* registered and awaiting approval/payment, *or* the organiser has tickets switched off |
///
/// That 403 genuinely cannot be told apart from outside; every ticket format
/// runs the same four checks in `RHTicketDownload._check_access`. So the UI does
/// not try to explain it — it offers the Indico page and lets Indico do the
/// explaining.
///
/// **Why the PDF and not a Wallet pass.** Indico also serves
/// `…/ticket/apple-wallet` and `…/ticket/google-wallet`, and those would be the
/// better ticket — a pass carries the same check-in QR and lives in the phone's
/// wallet. Both currently answer **500 `RecursionError: maximum recursion depth
/// exceeded`** on this instance, for every event, in a plain browser as well as
/// from here. When that is fixed server-side, switching back is a matter of
/// changing the path and the expected content type.
///
/// Nothing is written to disk and no ticket is held in memory: a ticket QR *is*
/// the credential — whoever holds it can be checked in as that member — so the
/// app keeps only the URL and hands it to the browser, which already has the
/// member's Indico session.
@MainActor
@Observable
final class TicketStore {
    enum State: Equatable {
        case idle
        case loading
        /// The member has not authorized the app against Indico yet.
        case needsLinking
        /// Nothing to show. Deliberately does not claim to know why.
        case unavailable
        /// Where the ticket lives. Opened in the browser rather than fetched
        /// again — the session there is what authenticates it.
        case available(URL)
        case failed(String)
    }

    /// The part of the decision that depends only on the response, split out so
    /// it can be tested without a network.
    enum Outcome: Equatable {
        case available
        case unavailable
        case needsLinking
        case failed
    }

    private(set) var states: [String: State] = [:]

    /// An event's registration forms do not change under us, so they are looked
    /// up once per launch rather than on every visit to the detail screen.
    @ObservationIgnored private var formIDs: [String: [Int]] = [:]

    /// What was already learned about this member's tickets, across launches.
    ///
    /// Only the *fact* and the form it came from — never the ticket: no URL, no
    /// `checkin_secret`, nothing a scanner could accept. That is what keeps this
    /// out of the credential store and in ordinary preferences, next to the
    /// profile claims.
    ///
    /// It exists because a **past** event's answer cannot change: the event is
    /// over and the registration is history. Asking again would make Indico
    /// render a PDF per row every time someone opens 已結束. Upcoming events are
    /// still asked live every launch — those genuinely do change — and their
    /// answers land here, so by the time an event moves into the archive it is
    /// already known.
    @ObservationIgnored private var remembered: [String: Remembered] = [:]

    /// Keyed on `sub`, per the rule that local storage never keys on an email or
    /// a username. Set from the composition root once the profile is known.
    var subject: String? {
        didSet {
            guard subject != oldValue else { return }
            remembered = Self.readRemembered(subject: subject)
        }
    }

    private static let host = "https://event.stsa.tw"

    func state(for eventID: String) -> State {
        states[eventID] ?? .idle
    }

    /// Answers from what is already known, without touching the network.
    ///
    /// - Returns: `true` when the question had already been settled, so the
    ///   caller can skip asking Indico.
    @discardableResult
    func hydrate(eventID: String) -> Bool {
        if isSettled(for: eventID) { return true }
        guard let known = remembered[eventID] else { return false }

        if known.hasTicket, let formID = known.formID {
            states[eventID] = .available(Self.ticketURL(eventID: eventID, formID: formID))
        } else {
            states[eventID] = .unavailable
        }
        return true
    }

    /// Looks up the event's registration forms, then asks each for a ticket until
    /// one answers. Most events have exactly one form, so this is normally two
    /// requests.
    func load(eventID: String, using indico: IndicoAuthManager) async {
        guard indico.isLinked else {
            states[eventID] = .needsLinking
            return
        }

        states[eventID] = .loading

        do {
            let formIDs = try await registrationForms(eventID: eventID, using: indico)
            guard !formIDs.isEmpty else {
                states[eventID] = .unavailable
                return
            }

            var fallback = Outcome.unavailable
            for formID in formIDs {
                let url = Self.ticketURL(eventID: eventID, formID: formID)
                switch try await outcome(for: url, using: indico) {
                case .available:
                    states[eventID] = .available(url)
                    remember(eventID: eventID, hasTicket: true, formID: formID)
                    return
                case .needsLinking:
                    states[eventID] = .needsLinking
                    return
                case .unavailable:
                    continue
                case .failed:
                    // Keep looking — another form may still answer — but do not
                    // let a real failure be reported as "nothing here".
                    fallback = .failed
                }
            }

            if fallback == .failed {
                states[eventID] = .failed(String(localized: "無法取得票券，稍後再試。"))
            } else {
                states[eventID] = .unavailable
                remember(eventID: eventID, hasTicket: false, formID: nil)
            }
        } catch LoadError.tokenRejected {
            states[eventID] = .needsLinking
        } catch {
            states[eventID] = .failed(error.localizedDescription)
        }
    }

    /// Loads only what has not been resolved yet.
    ///
    /// The events list uses this rather than `load` so that opening the tab
    /// repeatedly does not make Indico regenerate the same PDFs. The detail
    /// screen still calls `load`, because that is where someone lands right
    /// after registering and expects the answer to have changed.
    func loadIfNeeded(eventID: String, using indico: IndicoAuthManager) async {
        guard state(for: eventID) == .idle else { return }
        await load(eventID: eventID, using: indico)
    }

    /// Whether the member is known to hold a ticket. `false` while unknown —
    /// an absent badge is a better lie than a wrong one.
    func holdsTicket(for eventID: String) -> Bool {
        if case .available = state(for: eventID) { return true }
        return false
    }

    /// Whether the answer for this event is in. Callers that *hide* rows on the
    /// answer need this: "not registered" and "not asked yet" both read as
    /// `holdsTicket == false`, and treating the second as the first empties a
    /// list that is merely still loading.
    func isSettled(for eventID: String) -> Bool {
        switch state(for: eventID) {
        case .idle, .loading: false
        default: true
        }
    }

    /// Records a failure raised outside `load` — the authorization flow — so it
    /// surfaces in the same place as the rest.
    func report(_ error: any Error, for eventID: String) {
        states[eventID] = .failed(error.localizedDescription)
    }

    /// Clears everything, including what was remembered across launches.
    ///
    /// Called from an explicit 登出 — the member asking for their traces to leave
    /// this phone. A session that merely *expired* deliberately does not call
    /// this: they did not ask to be signed out, and keeping the answers means the
    /// archive is still instant when they sign back in. The entry is keyed on
    /// `sub`, so a different member never sees it either way.
    func clear() {
        states.removeAll()
        formIDs.removeAll()
        remembered.removeAll()
        if let subject { UserDefaults.standard.removeObject(forKey: Self.rememberedKey(subject)) }
    }

    // MARK: - What is already known

    private struct Remembered: Codable {
        var hasTicket: Bool
        var formID: Int?
    }

    private func remember(eventID: String, hasTicket: Bool, formID: Int?) {
        guard let subject else { return }
        remembered[eventID] = Remembered(hasTicket: hasTicket, formID: formID)
        guard let data = try? JSONEncoder().encode(remembered) else { return }
        UserDefaults.standard.set(data, forKey: Self.rememberedKey(subject))
    }

    private static func readRemembered(subject: String?) -> [String: Remembered] {
        guard let subject,
              let data = UserDefaults.standard.data(forKey: rememberedKey(subject)),
              let decoded = try? JSONDecoder().decode([String: Remembered].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func rememberedKey(_ subject: String) -> String { "tickets.known.\(subject)" }

    // MARK: - Requests

    static func ticketURL(eventID: String, formID: Int) -> URL {
        URL(string: "\(host)/event/\(eventID)/registrations/\(formID)/ticket.pdf")!
    }

    private func registrationForms(eventID: String, using indico: IndicoAuthManager) async throws -> [Int] {
        if let cached = formIDs[eventID] { return cached }
        guard let url = URL(string: "\(Self.host)/event/\(eventID)/api/registration-forms") else { return [] }

        // Anonymous works for public events, but restricted ones need the token,
        // and sending it costs nothing.
        let request = try indico.authorizedRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // A rejected token must not look like "this event has no forms" — that
        // would report a broken link as "no ticket here" and leave the member
        // with no way to notice.
        if status == 401 { throw LoadError.tokenRejected }
        guard status == 200 else { return [] }

        let ids = try JSONDecoder().decode([RegistrationForm].self, from: data).map(\.id)
        formIDs[eventID] = ids
        return ids
    }

    private func outcome(for url: URL, using indico: IndicoAuthManager) async throws -> Outcome {
        let request = try indico.authorizedRequest(for: url)
        let (_, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        return Self.outcome(
            status: http?.statusCode ?? 0,
            contentType: http?.value(forHTTPHeaderField: "Content-Type")
        )
    }

    /// - Note: the content type is not decoration. `URLSession` follows
    ///   redirects, so a request that lost its authorization would come back as
    ///   a perfectly good 200 — carrying Indico's *login page*. Only a PDF body
    ///   is a ticket.
    static func outcome(status: Int, contentType: String?) -> Outcome {
        switch status {
        case 200:
            let isTicket = contentType?.lowercased().hasPrefix("application/pdf") ?? false
            return isTicket ? .available : .failed
        case 401:
            // The token was rejected: revoked from Indico's settings, or the
            // application was disabled.
            return .needsLinking
        case 403, 404:
            return .unavailable
        default:
            return .failed
        }
    }

    /// Raised when Indico rejects the token outright, so `load` can tell that
    /// apart from an event that simply has no registration form.
    enum LoadError: Error {
        case tokenRejected
    }

    private struct RegistrationForm: Decodable {
        let id: Int
    }
}
