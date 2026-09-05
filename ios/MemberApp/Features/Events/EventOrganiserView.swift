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
struct EventOrganiserView: View {
    let event: IndicoEvent

    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    private var entries: [CheckinStore.Entry] { checkin.entries(for: event.id) }
    private var checkedIn: Int { entries.filter(\.registration.checkedIn).count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                progress

                NavigationLink {
                    EventCheckinView(event: event)
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
        .navigationTitle("幹部功能")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkin.loadRoster(eventID: event.id, using: indico) }
    }

    /// The number a door actually wants, before anyone opens the scanner: how
    /// many are in, out of how many are coming.
    private var progress: some View {
        VStack(spacing: 6) {
            Text("\(checkedIn) / \(entries.count)")
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

    @ViewBuilder
    private var roster: some View {
        if checkin.isLoadingRoster && entries.isEmpty {
            ProgressView().padding(.top, 24)
        } else if entries.isEmpty {
            Text("這場活動還沒有人報名。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowSeparator() }
                    row(entry)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
    }

    /// Not checked in first, which is the list a door is working from — the
    /// people still to come. Alphabetical inside each half so a name can be
    /// found by eye.
    private var sorted: [CheckinStore.Entry] {
        entries.sorted {
            $0.registration.checkedIn == $1.registration.checkedIn
                ? $0.registration.fullName.localizedCompare($1.registration.fullName) == .orderedAscending
                : !$0.registration.checkedIn
        }
    }

    private func row(_ entry: CheckinStore.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.registration.fullName)
                    .font(.callout)
                Text(entry.registration.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if entry.registration.checkedIn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("已報到")
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
    }
}
