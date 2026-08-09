import SwiftUI

struct EventsView: View {
    @Environment(EventsStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if !store.upcoming.isEmpty {
                        section("即將舉行", events: store.upcoming, highlightFirst: true)
                    }
                    if !store.past.isEmpty {
                        section("已結束", events: store.past, highlightFirst: false)
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
        }
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
                        EventRow(event: event, isNext: highlightFirst && index == 0)
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

private struct EventRow: View {
    let event: IndicoEvent
    let isNext: Bool

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
