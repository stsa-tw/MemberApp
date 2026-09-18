import SwiftUI

/// One person on the roster, opened from the list rather than through a camera.
///
/// The door is still the ordinary way in: a scan proves the person authenticated
/// within the last 300 seconds, or holds the ticket. This screen proves nothing
/// of the kind, and it is here because a real desk needs it anyway — a flat
/// phone, a ticket in an inbox nobody can reach, a queue, someone checked in by
/// mistake a minute ago. Indico's own check-in app makes the same call: its
/// registrant list checks people in and takes it back.
///
/// So the difference is kept where it belongs. This writes exactly what the door
/// writes, to the same flag, and the only thing standing behind it is a 幹部's
/// judgement — which is the honest description of a paper list too.
struct RegistrationDetailView: View {
    let event: IndicoEvent
    let form: CheckinStore.Form
    /// Named by id rather than passed whole: the roster behind this keeps
    /// refreshing, and another 幹部 may admit this person while the screen is
    /// open. The row it was opened with is only the fallback.
    let registrationID: Int
    let opened: CheckinRegistration

    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    /// What they filled in. Not in the roster — Indico leaves
    /// `registration_data` out of the list endpoint — so it is fetched once, on
    /// the way in.
    @State private var answers: [RegistrationAnswer] = []
    @State private var isConfirmingUndo = false
    @State private var error: String?
    @State private var needsAuthorization = false

    /// The row as the store now holds it, so a check-in made at a door two
    /// minutes ago is on screen here without this view knowing anything about it.
    private var registration: CheckinRegistration {
        checkin.entries(for: event.id, formID: form.id)
            .first { $0.id == registrationID }?.registration ?? opened
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                facts
                if !answers.isEmpty { answerCard }
                actions
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("報名資料")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let entry = CheckinStore.Entry(formID: form.id, registration: registration)
            answers = await checkin.details(for: entry, eventID: event.id, using: indico)?.answers
                ?? registration.answers
        }
        .confirmationDialog(
            "取消這筆報到？",
            isPresented: $isConfirmingUndo,
            titleVisibility: .visible
        ) {
            Button("取消報到", role: .destructive) {
                Task { await write(checkedIn: false) }
            }
            Button("返回", role: .cancel) {}
        } message: {
            Text("Indico 上的報到紀錄會被移除，這個人會回到未報到。")
        }
    }

    // MARK: - Who they are

    private var header: some View {
        VStack(spacing: 8) {
            Text(verbatim: registration.fullName)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(verbatim: registration.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            RegistrationTagChips(tags: registration.tags, isCentred: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, Theme.Metrics.gutter)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private var facts: some View {
        VStack(spacing: 0) {
            FactRow("報到狀態", value: status)
            if let state = registration.stateDescription {
                RowSeparator()
                FactRow("報名狀態", value: state)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    /// When Indico knows the moment, say it: whether somebody came through an
    /// hour ago or ten seconds ago is the difference between a queue-jumper and
    /// a double-tap, and it is also what tells a 幹部 they are about to undo the
    /// right arrival.
    private var status: String {
        guard registration.checkedIn else { return String(localized: "尚未報到") }
        guard let moment = registration.checkedInAt else { return String(localized: "已報到") }
        return String(localized: "已於 \(moment.formatted(date: .omitted, time: .shortened)) 報到")
    }

    private var answerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(answers.enumerated()), id: \.element.id) { index, answer in
                if index > 0 { RowSeparator() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: answer.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(verbatim: answer.value)
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

    // MARK: - Writing

    @ViewBuilder
    private var actions: some View {
        if needsAuthorization {
            // The roster reads on `read:everything`; the flag is a PATCH, which
            // Indico will not take on that grant. A 幹部 who only ever opened the
            // list has never been asked for the wider one.
            Text("這個 Indico 授權只能讀取。授權一次之後就能記錄報到。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("前往授權") { Task { await authorize() } }
                .buttonStyle(.brand)
                .disabled(indico.isBusy)
        } else if registration.checkedIn {
            Button("取消報到") { isConfirmingUndo = true }
                .buttonStyle(.brandPlain)
                .disabled(checkin.isSubmitting)
        } else if registration.isAdmissible {
            Button("確認報到") { Task { await write(checkedIn: true) } }
                .buttonStyle(.brand)
                .disabled(checkin.isSubmitting)
        } else {
            // Withdrawn or rejected, and not checked in: there is nothing to
            // undo and nobody to admit. Said plainly rather than drawn as a
            // disabled button nobody can explain.
            Text("這筆報名已取消或未通過，不能報到。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }

        if let error {
            Text(verbatim: error)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func write(checkedIn: Bool) async {
        error = nil
        switch await checkin.checkIn(
            registration, checkedIn: checkedIn, eventID: event.id, using: indico
        ) {
        case .recorded:
            // Nothing to set: the store folded Indico's answer into the roster,
            // and this screen reads the roster.
            needsAuthorization = false
        case .needsAuthorization:
            needsAuthorization = true
        case .notAdmissible:
            error = String(localized: "這筆報名已取消或未通過。")
        case .failed(let message):
            error = message
        }
    }

    private func authorize() async {
        do {
            try await indico.link(scopes: IndicoAuthConfiguration.checkinScopes)
            guard indico.canRecordCheckin else {
                error = String(localized: "請管理員在 Indico 的應用程式設定中勾選「Event registrants」允許範圍，再授權一次。")
                return
            }
            needsAuthorization = false
        } catch {
            // Dismissing the sheet is not a failure; leave the prompt standing.
            guard !AuthManager.isUserCancellation(error) else { return }
            if case IndicoAuthManager.LinkError.wrongAccount = error {
                self.error = String(localized: "App 和活動網站登入的不是同一個人，所以不能報到。")
                return
            }
            self.error = error.localizedDescription
        }
    }
}
