import SwiftUI

struct EventsView: View {
    @Environment(EventsStore.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(TicketStore.self) private var tickets
    @Environment(\.openURL) private var openURL

    @State private var isShowingPast = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // Above the events, because it is the reason the ticket rows
                    // underneath say nothing. Absent entirely once Indico is
                    // linked and agrees — which is almost always.
                    indicoStatus
                        .padding(.horizontal, Theme.Metrics.gutter)

                    if !store.upcoming.isEmpty {
                        section("即將舉行", events: store.upcoming, highlightFirst: true)
                    }
                    if !store.past.isEmpty {
                        pastSection
                    }
                    if store.events.isEmpty {
                        emptyState
                    }
                }
                .padding(.top, 6)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("活動")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The app shows a read-only slice of Indico; the full site
                    // has registration, attachments and past material.
                    Button {
                        openURL(URL(string: "https://event.stsa.tw")!)
                    } label: {
                        Label("活動網站", systemImage: "safari")
                    }
                }
            }
            .refreshable { await store.load() }
            .task { if store.events.isEmpty { await store.load() } }
            // Only the upcoming ones, and only once each: every probe makes
            // Indico generate a ticket. "Upcoming" is a handful by nature, so
            // this is a few requests, not a sweep of the whole calendar.
            .task(id: TicketProbe(linked: indico.isLinked, eventIDs: store.upcoming.map(\.id))) {
                guard indico.isLinked else { return }
                for event in store.upcoming {
                    await tickets.loadIfNeeded(eventID: event.id, using: indico)
                }
            }
        }
    }

    @ViewBuilder
    private var indicoStatus: some View {
        if indico.refused != nil {
            IndicoStatusBanner(state: .mismatch)
        } else if !indico.isLinked {
            IndicoStatusBanner(state: .notLinked) { Task { await link() } }
        }
    }

    private func link() async {
        // Nothing to report on failure: a mismatch turns the banner above into
        // the mismatch one by itself, and a cancelled sheet is not a failure.
        try? await indico.link()
        for event in store.upcoming {
            await tickets.loadIfNeeded(eventID: event.id, using: indico)
        }
    }

    /// Collapsed by default, and once open it lists the archive a member has a
    /// reason to see: their own events, or all of them for a 幹部.
    ///
    /// Nothing is probed until it is opened. Asking Indico whether a ticket
    /// exists makes it generate one, so doing it for every past event on every
    /// launch would be a pile of work for a section most people never open.
    @ViewBuilder
    private var pastSection: some View {
        VStack(spacing: 0) {
            DisclosureCardHeader(title: "已結束", isExpanded: $isShowingPast)

            if isShowingPast {
                if archive.isEmpty && isProbingPast {
                    ProgressView()
                        .padding(.vertical, 18)
                } else if archive.isEmpty {
                    Text("沒有你報名過的活動。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .padding(.vertical, 6)
                } else {
                    GroupedCard {
                        ForEach(Array(archive.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { RowSeparator(inset: 0) }
                            NavigationLink {
                                EventDetailView(event: event)
                            } label: {
                                EventRow(
                                    event: event,
                                    isNext: false,
                                    isRegistered: tickets.holdsTicket(for: event.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: TicketProbe(linked: indico.isLinked, eventIDs: isShowingPast ? store.past.map(\.id) : [])) {
            guard isShowingPast else { return }
            for event in store.past {
                // Settled history: if the answer is already known, it is the
                // answer — opening the archive should not make Indico render a
                // PDF for every row.
                if tickets.hydrate(eventID: event.id) { continue }
                guard indico.isLinked else { continue }
                await tickets.loadIfNeeded(eventID: event.id, using: indico)
            }
        }
    }

    /// What the 已結束 section lists.
    ///
    /// A member gets the events they registered for, because the archive is long
    /// and almost none of it is theirs. A 幹部 gets all of it: they are asked
    /// about events they did not attend — someone wants last year's slides, or
    /// the attendance for a report — and the app used to answer by hiding every
    /// event they had not personally signed up for.
    ///
    /// `isOfficer` is a self-reported claim, and `EventDetailView` deliberately
    /// does *not* gate 幹部功能 on it. The difference is what the claim stands
    /// for. There it meant "Indico will let me write check-ins to this event",
    /// which Indico enforces and which is false for a 幹部 of some other event —
    /// so the honest answer came from asking it. Here it decides how much of a
    /// list to show, and the list came from an endpoint that answers anonymously:
    /// a wrong claim reveals nothing that `event.stsa.tw` does not already hand
    /// to a stranger, and everything the rows lead to is checked again when it is
    /// opened.
    private var archive: [IndicoEvent] {
        guard auth.profile?.isOfficer != true else { return store.past }
        return store.past.filter { tickets.holdsTicket(for: $0.id) }
    }

    /// Only ever shown to a member: a 幹部's archive is the whole of `store.past`
    /// and has nothing to wait for.
    private var isProbingPast: Bool {
        store.past.contains { !tickets.isSettled(for: $0.id) }
    }

    private func section(_ title: LocalizedStringKey, events: [IndicoEvent], highlightFirst: Bool) -> some View {
        VStack(spacing: 0) {
            GroupedCardHeader(title)
            GroupedCard {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { RowSeparator(inset: 0) }
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        EventRow(
                            event: event,
                            isNext: highlightFirst && index == 0,
                            isRegistered: tickets.holdsTicket(for: event.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.isLoading {
            ProgressView().padding(.top, 60)
        } else if let message = store.errorMessage {
            ContentUnavailableView {
                Label("讀不到活動", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重試") { Task { await store.load() } }
            }
            .padding(.top, 40)
        } else {
            ContentUnavailableView("目前沒有活動", systemImage: "calendar",
                                   description: Text("新的活動公布後會出現在這裡。"))
                .padding(.top, 40)
        }
    }
}

/// Re-runs the ticket probe when the link is established or the upcoming set
/// changes, and not on every redraw.
private struct TicketProbe: Equatable {
    let linked: Bool
    let eventIDs: [String]
}

private struct EventRow: View {
    let event: IndicoEvent
    let isNext: Bool
    let isRegistered: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Formatted by hand rather than with `Text(_:format:)`: SwiftUI
            // injects the environment locale into a FormatStyle, which overrides
            // the one set on the style and renders "15日 / 8月" instead of the
            // "15 / AUG" the announcement rows use.
            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isNext ? AnyShapeStyle(Theme.Palette.brand) : AnyShapeStyle(.primary))
                Text(monthAbbreviation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    // Indico titles run long ("… In Conversation with NUS
                    // Admissions"); two lines keeps the rows an even height.
                    .lineLimit(2)
                    .truncationMode(.tail)
                if isRegistered {
                    Text("已報名")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.brand)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureChevron()
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var dayNumber: String { fixedFormat("d") }
    private var monthAbbreviation: String { fixedFormat("MMM").uppercased() }

    private func fixedFormat(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = event.timeZone
        formatter.dateFormat = template
        return formatter.string(from: event.start)
    }

    /// Time stays in the reader's locale — only the date block is fixed.
    private var subtitle: String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = event.timeZone
        return [event.start.formatted(style), event.place].compactMap(\.self).joined(separator: " · ")
    }
}

#Preview {
    EventsView().environment(EventsStore())
}
