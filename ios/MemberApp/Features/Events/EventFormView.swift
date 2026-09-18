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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(CheckinStore.self) private var checkin

    /// Searching the list is the other half of the door. The scanner is faster
    /// when there is a code to scan, and a name typed here is what a desk falls
    /// back to when there is not — a flat phone, a ticket in an unreachable
    /// inbox, or a 幹部 who just wants to know whether somebody has arrived.
    @State private var query = ""

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
        // only door: another 幹部 on another phone moves it too. So the screen
        // asks Indico on its own every few seconds rather than redrawing what
        // this phone happens to remember, and stops while the app is in the
        // background, where nobody is reading it.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await checkin.autoRefresh(eventID: event.id, using: indico)
        }
        // Pulling is the same question asked immediately, for a 幹部 who does
        // not want to wonder how old the number is.
        .refreshable { await checkin.refreshRoster(eventID: event.id, using: indico) }
        .searchable(text: $query, prompt: Text("搜尋姓名、email 或標籤"))
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
        // Answered from the probe's snapshot until the roster lands, so the
        // number is there on the first frame rather than counting up from 0 / 0.
        let arrived = checkin.checkedInCount(eventID: event.id, formID: form.id)
        let total = checkin.registeredCount(eventID: event.id, formID: form.id)

        return VStack(spacing: 6) {
            Text("\(arrived) / \(total)")
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
        let entries = checkin.entries(for: event.id, formID: form.id)
        let shown = entries
            .filter { $0.registration.matches(query) }
            .sorted { CheckinRegistration.isOrderedBefore($0.registration, $1.registration) }

        if checkin.isLoadingRoster && entries.isEmpty {
            ProgressView().padding(.top, 24)
        } else if entries.isEmpty {
            Text("這張報名表還沒有人報名。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
        } else if shown.isEmpty {
            // A search that matches nobody is not an empty form, and saying so
            // is the difference between "nobody registered" and "check the
            // spelling".
            ContentUnavailableView.search(text: query)
                .padding(.top, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowSeparator() }
                    NavigationLink {
                        RegistrationDetailView(
                            event: event,
                            form: form,
                            registrationID: entry.id,
                            opened: entry.registration
                        )
                    } label: {
                        RegistrationRow(registration: entry.registration, showsChevron: true)
                            .padding(.horizontal, Theme.Metrics.gutter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
    }
}
