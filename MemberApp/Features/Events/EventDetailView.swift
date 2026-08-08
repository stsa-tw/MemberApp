import SwiftUI

struct EventDetailView: View {
    let event: IndicoEvent

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                infoCard
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .padding(.top, 16)

                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.callout)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        // Deliberately not ignoring the top safe area: the hero sits below the
        // nav row, as in the mock. Extending it underneath put the title behind
        // the back button and made both unreadable.
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let url = event.url {
                VStack(spacing: 6) {
                    Button(event.isUpcoming ? "前往報名" : "查看活動頁") {
                        openURL(url)
                    }
                    .buttonStyle(.brand)

                    // Indico's HTTP API is read-only, so registration cannot happen
                    // in-app. Opening Indico is not a downgrade: it signs in through
                    // the same authentik, so the session usually carries over.
                    Text("報名在 Indico 上完成，使用同一個 STSA 帳號。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.vertical, 10)
                .background(.bar)
            }
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

    private func row(_ label: String, value: String) -> some View {
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
