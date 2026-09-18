import SwiftUI

struct AnnouncementDetailView: View {
    let announcement: Announcement

    @Environment(\.openURL) private var openURL
    @Environment(EventsStore.self) private var events
    @Environment(Session.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(announcement.channel) · \(announcement.month) \(announcement.day)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.brand)
                    .padding(.bottom, 8)

                Text(announcement.title)
                    .font(.title.weight(.bold))
                    .padding(.bottom, 6)

                Text(announcement.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)

                ForEach(announcement.body, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.callout)
                        .lineSpacing(4)
                        .padding(.bottom, 14)
                }

                facts

                // Inline rather than pinned — see Theme.Metrics.accessoryClearance.
                eventLink
                    .padding(.top, 20)
            }
            .padding(20)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemBackground))
        .navigationTitle("公告")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AnnouncementDetailView {
    /// The card of stated facts, or nothing at all.
    ///
    /// A notice that is not about a gathering — the app going live, say — has no
    /// time and no place, and an empty rounded box under the text reads as a
    /// loading failure. Built from whichever rows exist so the separators land
    /// between them rather than around a gap.
    @ViewBuilder
    var facts: some View {
        let rows: [(label: LocalizedStringKey, value: String)] =
            [("時間", announcement.when), ("地點", announcement.place), ("聯絡", announcement.contact)]
            .compactMap { label, value in value.map { (label, $0) } }

        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowSeparator() }
                    DetailRow(label: row.label, value: row.value)
                }
            }
            .background(Color(.systemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .padding(.top, 6)
        }
    }

    /// Prefers pushing the event inside the app; falls back to the web only when
    /// the event is not in the loaded window or has left the category.
    @ViewBuilder
    var eventLink: some View {
        if let id = announcement.eventID,
           let event = events.events.first(where: { $0.id == id }) {
            NavigationLink {
                EventDetailView(event: event)
            } label: {
                Text("前往活動")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.ctaHeight)
                    .foregroundStyle(.white)
                    .background(Theme.Palette.brand)
                    .clipShape(.rect(cornerRadius: Theme.Radius.button))
            }
        } else if let url = announcement.eventURL {
            VStack(spacing: 6) {
                Button("前往活動頁") { openURL(url) }
                    .buttonStyle(.brand)
                Text("將前往 Indico 活動頁。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DetailRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
    }
}

#Preview {
    NavigationStack {
        AnnouncementDetailView(announcement: Announcement.samples[0])
    }
}
