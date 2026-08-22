import SwiftUI

/// The door for one event: scan a member card, see who they are and what they
/// asked for.
///
/// It exists because the two halves live in different systems. The card says who
/// is standing there — that is MembershipAPI, and `ScanView` already answers it.
/// What they ordered is in Indico, against a registration. Email is the only
/// thing both know about a person, so it is the join.
///
/// Nothing is written. Marking someone checked in needs a scope this app does
/// not hold — see `CheckinStore`. The screen is a better clipboard, not a
/// replacement for Indico's own check-in app.
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
            await checkin.loadRoster(eventID: event.id, using: indico)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            access = CameraAccess.current
        }
    }

    // MARK: - Scanning

    private var viewfinder: some View {
        CameraScanner { payload in
            Task { await scan(payload) }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .accessibilityLabel("相機取景框")
    }

    private var hint: some View {
        VStack(spacing: 4) {
            Text("對準會員卡上的 QR code")
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
