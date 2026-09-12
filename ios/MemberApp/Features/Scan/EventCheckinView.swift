import SwiftUI

/// The door for one event: scan a member card, see who they are and what they
/// asked for.
///
/// It exists because the two halves live in different systems. The card says who
/// is standing there — that is MembershipAPI, and `ScanView` already answers it.
/// What they ordered is in Indico, against a registration. Email is the only
/// thing both know about a person, so it is the join.
///
/// It also records attendance, which is the point: a check-in made here is the
/// same `checked_in` flag Indico's own app sets, so there is one record of who
/// turned up rather than two. Writing needs a wider grant than reading, asked
/// for here and nowhere else — see `IndicoAuthConfiguration.checkinScopes`.
///
/// Nothing is ever written without the staffer confirming the name against the
/// person in front of them. A member card is a bearer credential for its 300
/// seconds, so a photographed one would otherwise check its owner in silently.
///
/// One door is one *form*, not one event. 烤場集合 has a 報名表 and a
/// 遊覽車報名表, which are separate lists holding separate registrations with
/// separate `checked_in` flags — so the desk at the park gate and the one at the
/// coach are two doors, and this screen is opened for whichever of them the
/// staffer is standing at.
struct EventCheckinView: View {
    let event: IndicoEvent
    /// The registration form this door works. A scan is matched inside it, and
    /// the count on screen is its own.
    let form: CheckinStore.Form

    @Environment(\.scenePhase) private var scenePhase
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    @State private var validator = MembershipValidator()
    @State private var access = CameraAccess.current
    @State private var result: Result = .scanning
    @State private var isPickingByName = false

    private enum Result: Equatable {
        case scanning
        case notAMember
        case unreachable(String)
        /// A member in good standing who is not on this form's list.
        case notRegistered(ScannedMember)
        /// A member whose registration for this event is on another of its forms
        /// — the coach list rather than the one this door is working. Reads as a
        /// missing person otherwise, which is how two lists became one confusing
        /// one in the first place.
        case registeredElsewhere(ScannedMember, [CheckinStore.Form])
        case found(CheckinRegistration)
        /// Recorded in Indico just now, as opposed to already checked in.
        case recorded(CheckinRegistration)
        /// The ticket resolved, but not to this event's door.
        case ticketRefused(String)
        /// The Indico authorization is read-only and must be widened first.
        case needsAuthorization
        /// The widening was asked for and refused: the Indico application does
        /// not allow `registrants`, so no staffer can grant it.
        case needsScopeOnServer
        /// The browser authorized as somebody else entirely.
        case wrongAccount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch access {
                case .undetermined:
                    ProgressView().padding(.top, 80)
                case .denied:
                    deniedState
                case .granted:
                    if result == .scanning {
                        viewfinder
                        hint
                    } else {
                        resultPanel
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 6)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("報到")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            access = await CameraAccess.request()
            // Re-asked rather than reused: opening the door is exactly the
            // moment the list has to match what the other doors have already
            // done, and it is two requests for most events.
            await checkin.refreshRoster(eventID: event.id, using: indico)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            access = CameraAccess.current
        }
        .sheet(isPresented: $isPickingByName) {
            ManualPicker(
                entries: checkin.entries(for: event.id, formID: form.id),
                formTitle: formTitle
            ) { entry in
                Task { await present(entry) }
            }
        }
    }

    // MARK: - Scanning

    private var viewfinder: some View {
        // Both formats reach this door: a member card, and an Indico ticket,
        // which `scan` then routes. The prefix clause is what keeps a malformed
        // member card reportable rather than silently ignored.
        CameraScanner(accepts: {
            $0.hasPrefix(MembershipValidator.prefix) || ScannedCode.parse($0) != nil
        }) { payload in
            Task { await scan(payload) }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .accessibilityLabel("相機取景框")
    }

    private var hint: some View {
        VStack(spacing: 4) {
            Text("對準會員卡或 Indico 票券上的 QR code")
                .font(.headline)
            Text(rosterHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Under the hint rather than beside the scanner: scanning is what
            // this screen is for, and the fallback should be findable without
            // competing with it.
            Button("找不到 QR code？改用姓名報到") {
                isPickingByName = true
            }
            .font(.footnote)
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var rosterHint: String {
        if checkin.isLoadingRoster {
            return String(localized: "正在讀取報名名單…")
        }
        let count = checkin.expected(eventID: event.id, formID: form.id).count
        return String(localized: "「\(formTitle)」有 \(count) 人報名。")
    }

    private var formTitle: String {
        title(ofFormID: form.id)
    }

    /// Names a form the way the staffer sees it named in Indico.
    private func title(ofFormID id: Int) -> String {
        let title = checkin.forms(for: event.id).first { $0.id == id }?.title ?? ""
        return title.isEmpty ? String(localized: "報名表") : title
    }

    private func scan(_ payload: String) async {
        // A ticket names the registration outright, so it never needs the roster
        // or an email match — which is what makes it the fallback when someone
        // registered under an address that is not their STSA one.
        if case .ticket(let ticket) = ScannedCode.parse(payload) {
            await resolve(ticket)
            return
        }

        await validator.validate(payload: payload)

        switch validator.outcome {
        case .valid(let member):
            guard let entry = checkin.entry(email: member.email, eventID: event.id, formID: form.id) else {
                // Being on another of the event's forms is a different answer
                // from not having registered, and the one that tells the staffer
                // what to do next.
                let elsewhere = checkin.otherForms(
                    email: member.email, eventID: event.id, excluding: form.id
                )
                result = elsewhere.isEmpty
                    ? .notRegistered(member)
                    : .registeredElsewhere(member, elsewhere)
                return
            }
            await present(entry)

        case .invalid:
            result = .notAMember

        case .unreachable(let message):
            result = .unreachable(message)

        case nil:
            result = .scanning
        }
    }

    /// Puts a roster entry on screen as a found registration.
    ///
    /// The roster carries no answers — Indico leaves them out of the list
    /// endpoint — so they are fetched here, falling back to what the list
    /// already told us rather than showing a name with nothing under it.
    private func present(_ entry: CheckinStore.Entry) async {
        let detailed = await checkin.details(for: entry, eventID: event.id, using: indico)
        result = .found(detailed ?? entry.registration)
    }

    private func resolve(_ ticket: ScannedCode.Ticket) async {
        switch await checkin.registration(ticket: ticket, eventID: event.id, using: indico) {
        case .found(let registration):
            result = .found(registration)
        case .unknownTicket:
            result = .ticketRefused(String(localized: "Indico 沒有這張票。"))
        case .otherEvent:
            result = .ticketRefused(String(localized: "這張票屬於其他活動。"))
        case .foreignInstance(let host):
            result = .ticketRefused(String(localized: "這張票是 \(host) 發出的。"))
        case .accompanyingPerson:
            result = .ticketRefused(String(localized: "這是隨行人員的票，請用 Indico 官方 App 報到。"))
        case .notPermitted:
            result = .ticketRefused(String(localized: "你沒有這場活動的報到權限。"))
        case .unreadable:
            result = .ticketRefused(String(localized: "無法讀取這張票。"))
        case .unreachable(let message):
            result = .unreachable(message)
        }
    }

    private func record(_ registration: CheckinRegistration) async {
        switch await checkin.checkIn(registration, eventID: event.id, using: indico) {
        case .recorded(let updated):
            result = .recorded(updated)
        case .notAdmissible:
            result = .ticketRefused(String(localized: "這筆報名已取消或未通過。"))
        case .needsAuthorization:
            result = .needsAuthorization
        case .failed(let message):
            result = .unreachable(message)
        }
    }

    /// Widens the Indico grant so this staffer can write.
    ///
    /// Only the person standing at the door is re-prompted; Indico extends their
    /// existing authorization rather than replacing it, and no other member is
    /// affected.
    private func authorizeWriting() async {
        do {
            try await indico.link(scopes: IndicoAuthConfiguration.checkinScopes)
            // A grant that comes back without `registrants` means the Indico
            // application does not allow the scope, which is server config no
            // staffer can fix from here. Say so, rather than returning to the
            // viewfinder to scan into the same wall.
            guard indico.canRecordCheckin else {
                result = .needsScopeOnServer
                return
            }
            result = .scanning
        } catch {
            // Dismissing the authorization sheet is not a failure; leave the
            // prompt standing so the staffer can try again.
            guard !AuthManager.isUserCancellation(error) else { return }
            // Same situation as the event page's banner, and it matters more
            // here: a door that authorized as somebody else would write that
            // person's name against every scan.
            if case IndicoAuthManager.LinkError.wrongAccount = error {
                result = .wrongAccount
                return
            }
            result = .unreachable(error.localizedDescription)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultPanel: some View {
        VStack(spacing: 14) {
            switch result {
            case .found(let registration):
                banner(
                    symbol: registration.checkedIn ? "checkmark.seal.fill" : "checkmark.circle.fill",
                    tint: registration.checkedIn ? .orange : .green,
                    title: registration.fullName,
                    detail: registration.checkedIn
                        ? String(localized: "已經報到過")
                        : String(localized: "已報名")
                )
                // A scanned ticket names one registration outright, and it may be
                // one from another of the event's forms. That is admissible — the
                // person is here and the row is theirs — but the staffer should
                // see which list they are about to write to, because this door's
                // count will not move.
                if registration.formID != form.id {
                    note(String(localized: "這筆報名在「\(title(ofFormID: registration.formID))」，報到會記在那張表上。"))
                }
                if !registration.answers.isEmpty {
                    answers(registration.answers)
                }

                if registration.isAdmissible {
                    Button(registration.checkedIn ? "再次報到" : "確認報到") {
                        Task { await record(registration) }
                    }
                    .buttonStyle(.brand)
                    .disabled(checkin.isSubmitting)
                }

            case .recorded(let registration):
                banner(
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    title: registration.fullName,
                    detail: String(localized: "已完成報到")
                )

            case .ticketRefused(let reason):
                banner(
                    symbol: "xmark.circle.fill",
                    tint: .red,
                    title: String(localized: "無法報到"),
                    detail: reason
                )

            case .needsAuthorization:
                banner(
                    symbol: "lock.circle.fill",
                    tint: .orange,
                    title: String(localized: "需要報到權限"),
                    detail: String(localized: "這個 Indico 授權只能讀取。授權一次之後就能記錄報到。")
                )
                Button("前往授權") {
                    Task { await authorizeWriting() }
                }
                .buttonStyle(.brand)
                .disabled(indico.isBusy)

            case .needsScopeOnServer:
                banner(
                    symbol: "lock.slash.fill",
                    tint: .red,
                    title: String(localized: "Indico 沒有開放報到權限"),
                    detail: String(localized: "請管理員在 Indico 的應用程式設定中勾選「Event registrants」允許範圍，再授權一次。")
                )

            case .wrongAccount:
                banner(
                    symbol: "person.2.badge.key.fill",
                    tint: .orange,
                    title: String(localized: "帳號對不上"),
                    detail: String(localized: "App 和活動網站登入的不是同一個人，所以不能報到。")
                )
                NavigationLink { IndicoAccountView() } label: { Text("看看是怎麼回事") }
                    .buttonStyle(.brand)

            case .notRegistered(let member):
                banner(
                    symbol: "person.crop.circle.badge.questionmark",
                    tint: .orange,
                    title: member.name,
                    detail: String(localized: "是會員，但沒有報名「\(formTitle)」")
                )

            case .registeredElsewhere(let member, let forms):
                banner(
                    symbol: "arrow.triangle.branch",
                    tint: .orange,
                    title: member.name,
                    detail: String(localized: "報名的是\(list(forms))，不是「\(formTitle)」")
                )
                note(String(localized: "回上一頁選那張報名表，才能記在正確的名單上。"))

            case .notAMember:
                banner(
                    symbol: "xmark.circle.fill",
                    tint: .red,
                    title: String(localized: "無效或已過期的會員碼"),
                    detail: String(localized: "請對方重新開啟會員卡再掃一次。")
                )

            case .unreachable(let message):
                banner(
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: String(localized: "無法驗證會員碼"),
                    detail: message
                )

            case .scanning:
                EmptyView()
            }

            Button("再掃一次") {
                validator.reset()
                result = .scanning
            }
            .buttonStyle(.brand)
        }
        .padding(.top, 6)
    }

    /// A quiet line under a banner: something the staffer should know before
    /// they tap, not an outcome of its own.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Metrics.gutter)
    }

    /// 「報名表」、「遊覽車報名表」 — the forms named the way a sentence needs them.
    private func list(_ forms: [CheckinStore.Form]) -> String {
        forms.map { "「\(title(ofFormID: $0.id))」" }.joined(separator: "、")
    }

    private func banner(symbol: String, tint: Color, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private func answers(_ answers: [RegistrationAnswer]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(answers.enumerated()), id: \.element.id) { index, answer in
                if index > 0 { RowSeparator() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(answer.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(answer.value)
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.vertical, 11)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("需要相機權限才能掃描")
                .font(.headline)
            Text("在「設定」中允許 STSA 使用相機,就可以掃描會員卡。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

/// The door's fallback: find somebody on the list by name, when there is no code
/// to scan.
///
/// Deliberately not the same act as a scan, and worth being clear about. A
/// member card proves the person authenticated within the last 300 seconds and a
/// ticket proves they hold the registration; a name picked off a list proves
/// nothing at all. It is the staffer's judgement, which is exactly what Indico's
/// own check-in app asks for too.
///
/// It exists because the alternative at a real door is worse. A member with a
/// flat phone, or a ticket in an inbox they cannot reach, and a queue behind
/// them, is admitted on somebody's word either way — the only question is
/// whether the app records it or a paper list does.
///
/// Nothing is written from here: picking a name opens the same confirmation the
/// scanner does, with the same 確認報到 button and the same refusal for a
/// withdrawn registration.
private struct ManualPicker: View {
    let entries: [CheckinStore.Entry]
    let formTitle: String
    let onPick: (CheckinStore.Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(matches) { entry in
                Button {
                    dismiss()
                    onPick(entry)
                } label: {
                    row(entry.registration)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜尋姓名或 email")
            )
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle(Text(verbatim: formTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    /// Matched on name *and* email, because a staffer reading a name off a
    /// screen and one reading an address off a member's mouth are the same
    /// errand. Not checked in first — the people still to come — and anyone
    /// withdrawn last, where they cannot be tapped by accident.
    private var matches: [CheckinStore.Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return entries
            .filter {
                needle.isEmpty
                    || $0.registration.fullName.lowercased().contains(needle)
                    || $0.registration.email.contains(needle)
            }
            .sorted { left, right in
                let a = left.registration, b = right.registration
                if a.isCancelled != b.isCancelled { return b.isCancelled }
                if a.checkedIn != b.checkedIn { return b.checkedIn }
                return a.fullName.localizedCompare(b.fullName) == .orderedAscending
            }
    }

    private func row(_ registration: CheckinRegistration) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(registration.fullName)
                    .font(.callout)
                HStack(spacing: 6) {
                    Text(registration.email)
                        .lineLimit(1)
                    if let state = registration.stateDescription {
                        Text(state)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)

            if registration.checkedIn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("已報到")
            }
        }
        .opacity(registration.isCancelled ? 0.45 : 1)
        .contentShape(.rect)
    }
}
