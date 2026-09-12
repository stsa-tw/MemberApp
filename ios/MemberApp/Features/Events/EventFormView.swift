import SwiftUI

/// One registration form, the way a 幹部 works it: how many have arrived, the
/// door, and the list.
///
/// A form is the unit because Indico makes it one — a registration lives inside
/// exactly one form and carries its own `checked_in`, so 報名表 and 遊覽車報名表
/// are two lists, two doors, and two sets of arrivals that never touch.
///
/// Shown as the whole of 幹部功能 when the event has one form, and pushed from
/// the chooser when it has several.
struct EventFormView: View {
    let event: IndicoEvent
    let form: CheckinStore.Form
    /// 幹部功能 when this is the event's only form and this screen *is* that
    /// screen; the form's own name when it was chosen from a list.
    let title: String

    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                progress

                NavigationLink {
                    EventCheckinView(event: event, form: form)
                } label: {
                    Label("報到", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.brand)

                roster
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkin.loadRoster(eventID: event.id, using: indico) }
        // The number here is the one an organiser trusts, and this is not the
        // only door: another 幹部 on another phone moves it too. Pulling asks
        // Indico rather than redrawing what this phone happens to remember.
        .refreshable { await checkin.refreshRoster(eventID: event.id, using: indico) }
    }

    // MARK: - The number

    /// How many are in, out of how many are coming.
    ///
    /// Withdrawn and rejected registrations are in neither half. They stay on
    /// Indico's list — `~is_deleted` is the only filter the API applies — but
    /// nobody is waiting for them at a door, and counting them made a
    /// denominator that could not be reached. Indico's own
    /// `active_registration_count` draws the line in the same place, so this
    /// number and the one on the management page mean the same thing.
    private var progress: some View {
        let expected = checkin.expected(eventID: event.id, formID: form.id)
        let arrived = expected.filter(\.registration.checkedIn).count

        return VStack(spacing: 6) {
            Text("\(arrived) / \(expected.count)")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text("已報到")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    // MARK: - The list

    @ViewBuilder
    private var roster: some View {
        let entries = sorted(checkin.entries(for: event.id, formID: form.id))

        if checkin.isLoadingRoster && entries.isEmpty {
            ProgressView().padding(.top, 24)
        } else if entries.isEmpty {
            Text("這張報名表還沒有人報名。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowSeparator() }
                    row(entry)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
    }

    /// Not checked in first, which is the list a door is working from — the
    /// people still to come. Alphabetical inside each group so a name can be
    /// found by eye, and anyone who withdrew at the very bottom: they are kept
    /// visible, because "where did they go" is a question the roster should
    /// answer, but they are nobody's next arrival.
    private func sorted(_ entries: [CheckinStore.Entry]) -> [CheckinStore.Entry] {
        entries.sorted { left, right in
            let a = left.registration, b = right.registration
            if a.isCancelled != b.isCancelled { return b.isCancelled }
            if a.checkedIn != b.checkedIn { return b.checkedIn }
            return a.fullName.localizedCompare(b.fullName) == .orderedAscending
        }
    }

    private func row(_ entry: CheckinStore.Entry) -> some View {
        let registration = entry.registration

        return HStack(spacing: 12) {
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
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
    }
}
