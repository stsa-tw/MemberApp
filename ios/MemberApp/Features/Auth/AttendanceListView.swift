import SwiftUI

/// The events behind the 我的 tab's count: the ones the member was checked in
/// to, and — separately, so the number above it is not diluted — the ones they
/// registered for and were not.
///
/// Reads what `AttendanceStore` already holds. It asks for nothing itself, so
/// opening it is instant and it can never disagree with the count that led here.
struct AttendanceListView: View {
    @Environment(AttendanceStore.self) private var attendance

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                section("已參加", attendance.attended ?? [], empty: "這個學年還沒有報到過的活動。")
                let others = attendance.notAttended ?? []
                if !others.isEmpty {
                    section("已報名，未報到", others, empty: "")
                }
                Text("只算本學年（7 月起）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metrics.gutter)
            }
            .padding(.top, 6)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .readableWidth()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("本學年的活動")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(
        _ title: LocalizedStringKey,
        _ entries: [AttendanceStore.Entry],
        empty: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 0) {
            GroupedCardHeader(title)
            GroupedCard {
                if entries.isEmpty {
                    Text(empty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .padding(.vertical, 12)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowSeparator() }
                    row(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: AttendanceStore.Entry) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let start = entry.start {
                    Text(start, format: Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: entry.timeZone))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = Self.tag(for: entry) {
                Text(tag)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
        .contentShape(.rect)

        // Indico's own page for the event, for the member who wants the detail.
        if let url = entry.url {
            Link(destination: url) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Where an unattended registration stands. Says only what Indico says —
    /// a future event is not "missed", and a pending one is not "no show".
    private static func tag(for entry: AttendanceStore.Entry) -> LocalizedStringKey? {
        if entry.checkedIn { return nil }
        switch entry.status {
        case "no_show": return "未到場"
        case "upcoming": return "尚未開始"
        case "ongoing": return "進行中"
        case "pending": return "待確認"
        default: return nil
        }
    }
}
