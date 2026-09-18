import SwiftUI

/// What a 幹部 can do with an event, kept off the page everyone else reads.
///
/// The event screen belongs to the member: when it is on, when it is where, and
/// where their ticket is. Running the event is a different job for a different
/// handful of people, and mixing the two put a door scanner above the venue
/// address for four hundred members who will never open it.
///
/// Reached only when Indico says this account manages the event — the same
/// permission the screen's own calls run on, asked rather than assumed.
///
/// With one registration form this screen *is* that form's screen. With more
/// than one it is a chooser, because they are not one job: 報名表 and
/// 遊覽車報名表 are separate lists with separate doors and separate arrivals,
/// and a 幹部 opening this is already on their way to one of them. Stacking both
/// made them scroll past the wrong one to reach the right one, every time.
struct EventOrganiserView: View {
    let event: IndicoEvent

    @Environment(\.scenePhase) private var scenePhase
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    private var forms: [CheckinStore.Form] { checkin.forms(for: event.id) }

    var body: some View {
        Group {
            if forms.isEmpty {
                loading
            } else if forms.count == 1 {
                EventFormView(event: event, form: forms[0], title: String(localized: "幹部功能"))
            } else {
                chooser
            }
        }
    }

    private var loading: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("幹部功能")
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Choosing a form

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(forms.enumerated()), id: \.element.id) { index, form in
                    if index > 0 { RowSeparator() }
                    NavigationLink {
                        EventFormView(event: event, form: form, title: title(of: form))
                    } label: {
                        row(form)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("幹部功能")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkin.loadRoster(eventID: event.id, using: indico) }
        // Each row carries its form's arrivals, and both doors are being worked
        // by somebody else — so the counts a 幹部 is choosing between keep asking
        // Indico rather than ageing while the chooser sits open.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await checkin.autoRefresh(eventID: event.id, using: indico)
        }
        .refreshable { await checkin.refreshRoster(eventID: event.id, using: indico) }
    }

    private func row(_ form: CheckinStore.Form) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(of: form))
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(summary(of: form))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            DisclosureChevron()
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private func title(of form: CheckinStore.Form) -> String {
        form.title.isEmpty ? String(localized: "報名表") : form.title
    }

    /// The count a 幹部 is choosing between, so the choice can be made from the
    /// list rather than by opening both.
    private func summary(of form: CheckinStore.Form) -> String {
        if checkin.isLoadingRoster && checkin.entries(for: event.id).isEmpty {
            return String(localized: "正在讀取報名名單…")
        }
        let expected = checkin.expected(eventID: event.id, formID: form.id)
        let arrived = expected.filter(\.registration.checkedIn).count
        return String(localized: "\(arrived) / \(expected.count) 已報到")
    }
}
