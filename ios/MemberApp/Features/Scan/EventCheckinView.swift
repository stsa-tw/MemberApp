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
struct EventCheckinView: View {
    let event: IndicoEvent

    @Environment(\.scenePhase) private var scenePhase
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    @State private var validator = MembershipValidator()
    @State private var access = CameraAccess.current
    @State private var result: Result = .scanning

    private enum Result: Equatable {
        case scanning
        case notAMember
        case unreachable(String)
        /// A member in good standing who is not on this event's list.
        case notRegistered(ScannedMember)
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
        }
        .padding(.top, 4)
    }

    private var rosterHint: String {
        if checkin.isLoadingRoster {
            return String(localized: "正在讀取報名名單…")
        }
        let count = checkin.entries(for: event.id).count
        return String(localized: "\(count) 人已報名這場活動。")
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
            guard let entry = checkin.entry(email: member.email, eventID: event.id) else {
                result = .notRegistered(member)
                return
            }
            // The roster carries no answers; fetch them, and fall back to what
            // the list already told us rather than showing nothing.
            let detailed = await checkin.details(for: entry, eventID: event.id, using: indico)
            result = .found(detailed ?? entry.registration)

        case .invalid:
            result = .notAMember

        case .unreachable(let message):
            result = .unreachable(message)

        case nil:
            result = .scanning
        }
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
                    detail: String(localized: "是會員，但沒有報名這場活動")
                )

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
