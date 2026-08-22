import SwiftUI

struct EventDetailView: View {
    let event: IndicoEvent

    @Environment(\.openURL) private var openURL
    @Environment(Session.self) private var session
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(TicketStore.self) private var tickets
    @Environment(CheckinStore.self) private var checkin

    @State private var isLinking = false
    @State private var isShowingDescription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                // First, not buried: for whoever is standing at the door this is
                // the only thing on the page they came for, and everything above
                // it is a scroll they do not have time for.
                checkinEntry
                    .padding(.horizontal, Theme.Metrics.gutter)

                infoCard
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .padding(.top, 16)

                // Inline, directly under the key facts, rather than pinned to
                // the bottom — see Theme.Metrics.accessoryClearance. This also
                // puts the action next to the time and place instead of at the
                // end of a long description.
                actions
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .padding(.top, 16)




                description
            }
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        // Deliberately not ignoring the top safe area: the hero sits below the
        // nav row, as in the mock. Extending it underneath put the title behind
        // the back button and made both unreadable.
        .navigationBarTitleDisplayMode(.inline)
        // Forced rather than `loadIfNeeded`, because this is where someone lands
        // right after registering and expects the answer to have changed. Past
        // events are skipped outright: `ticketState` will not offer a ticket for
        // one, so asking would be a PDF rendered for nothing.
        .task {
            guard event.isUpcoming else { return }
            await tickets.load(eventID: event.id, using: indico)
            await checkin.probe(eventID: event.id, using: indico)
        }
    }

    // MARK: - Description

    /// Truncated rather than collapsed away.
    ///
    /// An event description is the reason someone who has not registered opened
    /// this page at all, so hiding it behind a tap would cost the screen its main
    /// job. Four lines is enough to know what the event is; the rest is one tap.
    @ViewBuilder
    private var description: some View {
        if !event.summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.summary)
                    .font(.callout)
                    .lineSpacing(4)
                    .lineLimit(isShowingDescription ? nil : 4)

                Button(isShowingDescription ? "收合" : "顯示更多") {
                    withAnimation(.snappy(duration: 0.22)) { isShowingDescription.toggle() }
                }
                .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)
        }
    }

    // MARK: - Door

    /// Only for someone Indico says manages this event. There is no role claim
    /// behind it — the app asked the check-in API and it answered, which is the
    /// same permission the screen itself runs on.
    @ViewBuilder
    private var checkinEntry: some View {
        if checkin.access(for: event.id) == .allowed {
            NavigationLink {
                EventCheckinView(event: event)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("報到")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandPlain)
            .padding(.top, 20)
        }
    }

    // MARK: - Actions

    /// Exactly one filled button, ever.
    ///
    /// This screen used to stack 前往報名 and 查看票券 as two equally loud brand
    /// slabs, which is a wall of colour and no hierarchy — and it had them the
    /// wrong way round for the case that matters: once you hold a ticket, the
    /// registration page is the *lesser* action. So the primary is whichever
    /// action the member's state makes primary, anything else drops to plain,
    /// and there is one line of explanation rather than one per button.
    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            switch ticketState {
            case .available(let ticket):
                Button("查看票券") { openURL(ticket) }
                    .buttonStyle(.brand)

                // Opened in the browser rather than rendered here: Safari already
                // holds the member's Indico session, and the ticket never has to
                // touch the app or the disk. That is plumbing, not something the
                // member needs told — the button says what it does.
                if let url = event.url {
                    Button("活動頁") { openURL(url) }
                        .buttonStyle(.brandPlain)
                }

            case .needsLinking:
                if let url = event.url {
                    Button(primaryLabel) { openURL(url) }
                        .buttonStyle(.brand)
                }

                Button("查看我的票券") { Task { await link() } }
                    .buttonStyle(.brandPlain)
                    .disabled(isLinking)

                // Indico's application is registered as trusted, so it shows no
                // consent screen — nothing else in the flow will tell the member
                // what is being connected. So this line has to.
                caption("會連結你的 Indico 帳號，只用來讀取你自己的報名與票券。")

            case .failed(let message):
                if let url = event.url {
                    Button(primaryLabel) { openURL(url) }
                        .buttonStyle(.brand)
                }
                caption(message)

            case .idle, .loading, .unavailable:
                // "unavailable" could be "not registered", "awaiting approval" or
                // "the organiser turned tickets off" — Indico answers all three
                // with 403, so claiming any of them would be a guess. The
                // registration page knows; this button leads there.
                if let url = event.url {
                    Button(primaryLabel) { openURL(url) }
                        .buttonStyle(.brand)

                    // Indico's HTTP API is read-only, so registration cannot
                    // happen in-app. Opening Indico is not a downgrade: it signs
                    // in through the same authentik.
                    caption("報名在 Indico 上完成，使用同一個 STSA 帳號。")
                }
            }
        }
    }

    /// A past event's ticket is not worth offering, so the archive only ever
    /// sees the plain "open the page" action.
    private var ticketState: TicketStore.State {
        event.isUpcoming ? tickets.state(for: event.id) : .unavailable
    }

    private var primaryLabel: LocalizedStringKey {
        event.isUpcoming ? "前往報名" : "查看活動頁"
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
    }

    private func link() async {
        isLinking = true
        defer { isLinking = false }

        do {
            try await indico.link()
            await tickets.load(eventID: event.id, using: indico)
            await checkin.probe(eventID: event.id, using: indico)
        } catch {
            // Dismissing the sheet is not a failure worth an alert, same as the
            // authentik flow.
            guard !AuthManager.isUserCancellation(error) else { return }
            tickets.report(error, for: event.id)
        }
    }



    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            Text(event.kicker)
                .font(.footnote.weight(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            Text(event.title)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottomLeading)
        .background(heroTint)
    }

    /// The mock gives every event its own hue. There is no colour in Indico's
    /// data, so derive a stable one from the id — same event, same colour.
    private var heroTint: some ShapeStyle {
        let hue = Double(abs(event.id.hashValue) % 360) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.55, brightness: 0.42),
                     Color(hue: hue, saturation: 0.65, brightness: 0.26)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            row("時間", value: schedule)
            if let place = event.place {
                RowSeparator()
                row("地點", value: place)
            }
            if let address = event.address, !address.isEmpty {
                RowSeparator()
                row("地址", value: address)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private func row(_ label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
    }

    private var schedule: String {
        var day = Date.FormatStyle.dateTime.year().month().day().weekday(.abbreviated)
        var clock = Date.FormatStyle.dateTime.hour().minute()
        day.timeZone = event.timeZone
        clock.timeZone = event.timeZone

        let sameDay = Calendar.current.isDate(event.start, inSameDayAs: event.end)
        return sameDay
            ? "\(event.start.formatted(day)) \(event.start.formatted(clock))–\(event.end.formatted(clock))"
            : "\(event.start.formatted(day)) \(event.start.formatted(clock)) – \(event.end.formatted(day)) \(event.end.formatted(clock))"
    }
}
