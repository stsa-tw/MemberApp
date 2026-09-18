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
/// **The PDF and the Wallet pass.** Indico also serves `…/ticket/apple-wallet`,
/// which is the better ticket — the same check-in QR, kept where a ticket
/// belongs, and it outlives the Indico session. That endpoint answered **500
/// `RecursionError: maximum recursion depth exceeded`** on this instance when
/// this store was written; it no longer does, and now returns a signed pass. So
/// the app asks for one and leads with it when it arrives.
///
/// The PDF stays for the cases a pass does not cover: a device that cannot hold
/// passes, or a ticket the instance will not render one for. Ask for the pass
/// with a plain **GET** — `HEAD` looks thriftier and Indico answers it `400`.
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
        /// Indico answered as somebody else. Its own case rather than a
        /// `failed` string: this one has an address in it, a cause the member
        /// can act on, and a way out — none of which survive being flattened
        /// into a line of grey caption text.
        case wrongAccount
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

            // `nil` → someone is the profile *arriving*, not a different person.
            // `AuthManager` restores a session before the claims that name it,
            // and after a reinstall it has to go and fetch them — so a ticket
            // can be resolved, and a pass found, before there is a key to file
            // either under. That was learned about this member, so it is kept,
            // and now written down.
            //
            // Getting this wrong is not theoretical: clearing unconditionally
            // is what emptied the map out from under a resolved pass and took
            // the button off the ticket screen.
            guard oldValue != nil else {
                remembered = Self.readRemembered(subject: subject)
                    .merging(remembered) { _, learned in learned }
                persistRemembered()
                return
            }

            // One member replacing another. Nothing of theirs survives — and
            // `walletURLs` is not persisted, so it has no per-`sub` key of its
            // own to keep it apart.
            remembered = Self.readRemembered(subject: subject)
            walletURLs.removeAll()
            cancelWalletProbes()
        }
    }

    private static let host = "https://event.stsa.tw"

    /// Where this event's ticket lives as an Apple Wallet pass, once asked.
    ///
    /// Three states rather than two, and the difference is the whole point of
    /// the map: **no entry** means *not asked yet*, `.some(nil)` means Indico
    /// was asked and said no. A no is cached so a screen that redraws does not
    /// re-ask a server that answered 500; *not asked* is what a probe that
    /// never reached an answer must leave behind, so the next visit tries again.
    ///
    /// Note `walletURLs[id] = nil` **removes** the entry, which is the one the
    /// probe wants on failure; recording a no takes `URL?.none` explicitly.
    private var walletURLs: [String: URL?] = [:]

    /// The answer already on its way, per event.
    ///
    /// The event screen and the ticket screen both ask, on purpose — but an
    /// answer only reaches the map when it arrives, so in the slow case the two
    /// overlap, and the slow case is exactly the one where they do. Without this
    /// a member who taps straight through asks Indico to sign the same pass
    /// twice.
    ///
    /// It holds the **task**, not a mark, because the second asker has to *wait
    /// on* that answer rather than walk away from it. A mark made the second call
    /// return at once — and the first call was a child of the event screen's
    /// `.task`, which a push cancels. So tapping 查看我的票券 while Indico was
    /// still signing killed the only probe running, moments after the ticket
    /// screen had declined to start its own: no answer recorded, nothing in
    /// flight, and no third asker, so the button was simply missing for as long
    /// as that screen stayed up. Whether it happened came down to whether the
    /// pass arrived before the tap, which is why it came and went.
    ///
    /// Unstructured on purpose: a `Task` does not inherit its caller's
    /// cancellation, so the probe now outlives the screen that started it and
    /// lands for whoever is still looking. Cancelled only where the answer would
    /// be unwanted — a forget, a logout, a different member.
    ///
    /// Not observed: nothing is drawn from it.
    @ObservationIgnored private var walletProbes: [String: Task<Void, Never>] = [:]

    func walletURL(for eventID: String) -> URL? {
        walletURLs[eventID] ?? nil
    }

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
        // The addresses behind this live on `IndicoAuthManager`, which is
        // where they stay current — copying them per event would be one more
        // thing to keep in step.
        if case IndicoAuthManager.LinkError.wrongAccount = error {
            states[eventID] = .wrongAccount
            return
        }
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
        walletURLs.removeAll()
        cancelWalletProbes()
        if let subject { UserDefaults.standard.removeObject(forKey: Self.rememberedKey(subject)) }
    }

    /// Drops the answers still on their way, so none of them lands on a map that
    /// has just stopped being this member's.
    private func cancelWalletProbes() {
        for probe in walletProbes.values { probe.cancel() }
        walletProbes.removeAll()
    }

    // MARK: - What is already known

    private struct Remembered: Codable {
        var hasTicket: Bool
        var formID: Int?
    }

    /// Kept in memory whether or not there is a `subject` to file it under;
    /// only *writing it down* needs one.
    ///
    /// This used to return early without a subject, which lost the form the
    /// ticket came from — and `loadWalletPass`, which needs it, was left
    /// guessing at the first form of an event that may hold two. A reinstall
    /// opens that window on its own: the keychain survives app deletion and
    /// UserDefaults does not, so the session comes back before the profile that
    /// names it does.
    private func remember(eventID: String, hasTicket: Bool, formID: Int?) {
        remembered[eventID] = Remembered(hasTicket: hasTicket, formID: formID)
        persistRemembered()
    }

    /// Writes the lot down, if there is yet a member to write it down against.
    private func persistRemembered() {
        guard let subject, let data = try? JSONEncoder().encode(remembered) else { return }
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

    /// The same ticket as an Apple Wallet pass.
    ///
    /// Indico serves this itself — it is core, not a plugin, and needs no
    /// certificate of ours — so a working instance hands back a signed
    /// `.pkpass` and there is nothing for the app to sign.
    static func walletURL(eventID: String, formID: Int) -> URL {
        URL(string: "\(host)/event/\(eventID)/registrations/\(formID)/ticket/apple-wallet")!
    }

    /// Asks whether this ticket exists as a pass, and remembers either answer.
    ///
    /// Deliberately never fails the ticket: a pass is the nicer route to the
    /// same QR, not a replacement for it, so an instance that cannot produce one
    /// still leaves the PDF working.
    ///
    /// Asked for past events too. Indico's `RHTicketDownload._check_access` runs
    /// four checks — registration complete, tickets enabled, ticket visible or
    /// the user manages registration, ticket not blocked — and **none of them is
    /// about the date. A ticket outlives its event**, and a pass for one already
    /// attended is a record worth keeping rather than something to withhold.
    func loadWalletPass(eventID: String, using indico: IndicoAuthManager) async {
        guard indico.isLinked, walletURLs[eventID] == nil else { return }
        // Only a ticket that exists can become a pass — and only the form that
        // served it can: an event with a 報名表 and a 遊覽車報名表 holds two, and
        // the other one has no registration of this member's to issue against.
        // `remembered` is written wherever `.available` is set, so it is the
        // form that answered rather than the first one on the list.
        guard case .available = state(for: eventID),
              let formID = remembered[eventID]?.formID
        else { return }

        // Joined, not skipped — see `walletProbes`.
        if let inFlight = walletProbes[eventID] {
            await inFlight.value
            return
        }

        let probe = Task { [self] in
            await askIndicoForPass(eventID: eventID, formID: formID, using: indico)
        }
        walletProbes[eventID] = probe
        await probe.value

        // Cleared only if it is still ours: a `forgetWalletPass` mid-request
        // drops this entry and the next asker files a fresh probe, which this
        // line would otherwise take down on its way out.
        if walletProbes[eventID] == probe { walletProbes[eventID] = nil }
    }

    /// The request itself, awaited only through `walletProbes`.
    private func askIndicoForPass(eventID: String,
                                  formID: Int,
                                  using indico: IndicoAuthManager) async {
        let url = Self.walletURL(eventID: eventID, formID: formID)
        do {
            // A plain GET, like the PDF probe beside it. HEAD looks like the
            // thriftier choice and Indico answers it 400: its request handlers
            // are written for the methods the route declares, and the saving —
            // a pass is a few kilobytes — was never worth the divergence.
            let request = try indico.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            // A 5xx is Indico falling over, not Indico answering about this
            // ticket, so it is not an answer to keep. This endpoint has the
            // history for it — it served nothing but `RecursionError` 500s when
            // this store was written — and filing one as "no pass" retired the
            // button for the rest of the launch over a blip.
            guard !(500...599).contains(status) else {
                Self.logWalletProbe(eventID: eventID,
                                    status: status,
                                    contentType: http?.mimeType,
                                    verdict: "server error, not recorded")
                return
            }

            // Asked of the bytes, not of the `Content-Type`. `PKPass` is the
            // authority on whether Wallet will take them, and it is the same
            // parse `WalletPass.add` runs — so the button appears exactly where
            // the pass would actually add.
            let isPass = status == 200 && WalletPass.isPass(data)
            walletURLs[eventID] = isPass ? url : URL?.none
            Self.logWalletProbe(eventID: eventID,
                                status: status,
                                contentType: http?.mimeType,
                                verdict: isPass ? "pass offered" : "no pass")
        } catch {
            // Nothing recorded, deliberately: a request that never reached an
            // answer is not an answer. This ran `walletURLs[eventID] = URL?.none`
            // once, and since the probe only runs where nothing is recorded, a
            // single failure hid the button until the next launch.
            //
            // Cancellation lands here too, but now only from a caller that meant
            // it — logging out, switching member, forgetting a no — and none of
            // those wants an answer about the session that has just ended. A
            // screen going away no longer reaches this: `walletProbes` owns the
            // task, not the screen.
            Self.logWalletProbe(eventID: eventID,
                                status: nil,
                                contentType: nil,
                                verdict: "request failed, not recorded — \(error)")
        }
    }

    /// Forgets a no, so it can be asked again.
    ///
    /// For the one thing a member can actually do about one: an expired Indico
    /// session answers this probe with a login page — HTTP 200, `text/html`,
    /// correctly filed as "no pass" — and re-linking is what fixes it. Without
    /// this, the probe after `link()` would find an answer already on file and
    /// skip, leaving the button gone on the one path that repaired its cause.
    ///
    /// Drops any request still in flight as well, because it is an answer about
    /// the session being replaced: joining it would hand the caller the very
    /// login page it is trying to get past. `walletProbes` holds the task, which
    /// is the token an earlier note here wished for.
    func forgetWalletPass(eventID: String) {
        walletURLs.removeValue(forKey: eventID)
        walletProbes.removeValue(forKey: eventID)?.cancel()
    }

#if DEBUG
    /// Puts a pass on the ticket screen for an App Store capture.
    ///
    /// The probe cannot supply one there — see `ScreenshotFixtures.walletPassURL`
    /// — and this is the only door into the map, which is otherwise private for
    /// the good reason that an answer should come from Indico.
    func seedWalletPass(eventID: String, url: URL) {
        walletURLs[eventID] = url
    }
#endif

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

    /// Says why a pass was or was not offered.
    ///
    /// Without this a 500, a 404 and "this device cannot hold passes" all look
    /// the same from the outside — the button is simply absent — which is not
    /// enough to tell whether the app or the server is at fault.
    ///
    /// The verdict is handed in rather than worked out again here.
    ///
    /// It used to be re-derived from the content type, which is how a log meant
    /// to explain the map came to disagree with it. The content type is still
    /// printed — it is worth seeing when an instance answers oddly — but it no
    /// longer decides anything.
    private static func logWalletProbe(eventID: String,
                                       status: Int?,
                                       contentType: String?,
                                       verdict: String) {
        #if DEBUG
        print("[Indico] wallet pass for event \(eventID): HTTP \(status.map(String.init) ?? "?")"
            + " \(contentType ?? "no content type") — \(verdict)")
        #endif
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
