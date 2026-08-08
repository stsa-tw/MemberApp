import SwiftUI

struct AnnouncementDetailView: View {
    let announcement: Announcement

    @Environment(\.openURL) private var openURL

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

                VStack(spacing: 0) {
                    DetailRow(label: "時間", value: announcement.when)
                    RowSeparator()
                    DetailRow(label: "地點", value: announcement.place)
                    if let contact = announcement.contact {
                        RowSeparator()
                        DetailRow(label: "聯絡", value: contact)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .clipShape(.rect(cornerRadius: Theme.Radius.card))
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemBackground))
        .navigationTitle("公告")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // Only shown when the announcement is about something registrable.
            // Registration happens on Indico — the API is read-only.
            if let url = announcement.eventURL {
                VStack(spacing: 6) {
                    Button("前往報名") { openURL(url) }
                        .buttonStyle(.brand)
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
}

private struct DetailRow: View {
    let label: String
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
