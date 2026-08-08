import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(EventsStore.self) private var events

    private let announcements = Announcement.samples

    /// Real count from Indico rather than the mock's fixed "3 場".
    private var upcomingLabel: String {
        events.upcoming.isEmpty ? "目前沒有活動" : "\(events.upcoming.count) 場即將舉行"
    }

    /// Buddy 配對 has no data source yet, so the second shortcut points at the
    /// one thing behind it that does.
    private var dealsLabel: String {
        "\(Deal.samples.filter { !$0.hasExpired() }.count) 間合作商家"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    MemberCardBanner()

                    HStack(spacing: 10) {
                        ShortcutTile(symbol: "calendar",
                                     title: "活動報名",
                                     detail: upcomingLabel) {
                            session.selectedTab = .events
                        }
                        ShortcutTile(symbol: "tag.fill",
                                     title: "會員優惠",
                                     detail: dealsLabel) {
                            session.selectedTab = .deals
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)

                    VStack(spacing: 0) {
                        GroupedCardHeader("公告") {
                            NavigationLink("頻道") { ChannelsView() }
                                .font(.subheadline)
                        }
                        GroupedCard {
                            ForEach(Array(announcements.enumerated()), id: \.element.id) { index, announcement in
                                // The mock rules edge-to-edge inside the card rather than
                                // insetting past the date column.
                                if index > 0 { RowSeparator(inset: 0) }
                                NavigationLink {
                                    AnnouncementDetailView(announcement: announcement)
                                } label: {
                                    AnnouncementRow(announcement: announcement, isLatest: index == 0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ChannelsView()
                    } label: {
                        Label("頻道", systemImage: "bubble.left")
                    }
                }
            }
        }
    }

    private var greeting: String {
        // Prefer the nickname: authentik fills given_name with the full name, and
        // trimming a surname by character count breaks on two-character ones.
        let name = auth.profile.map { $0.nickname ?? $0.givenName ?? $0.displayName } ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let time = switch hour {
        case 5..<12: "早安"
        case 12..<18: "午安"
        default: "晚安"
        }
        return "\(time)，\(name)"
    }
}

// MARK: - Rows

/// The dark banner that opens the member card.
private struct MemberCardBanner: View {
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Button {
            session.isShowingMemberCard = true
        } label: {
            HStack(spacing: 14) {
                Image(.stsaLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("會員卡")
                        .font(.headline)
                    if let profile = auth.profile {
                        Text([profile.displayName, profile.school].compactMap(\.self).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.Palette.inkCard)
            .clipShape(.rect(cornerRadius: Theme.Radius.button))
            .padding(.horizontal, Theme.Metrics.gutter)
        }
        .buttonStyle(.plain)
    }
}

/// One of the two square shortcuts under the member card.
private struct ShortcutTile: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Palette.brand)
                    .padding(.bottom, 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.button))
        }
        .buttonStyle(.plain)
    }
}

private struct AnnouncementRow: View {
    let announcement: Announcement
    let isLatest: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(announcement.day)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isLatest ? AnyShapeStyle(Theme.Palette.brand) : AnyShapeStyle(.primary))
                Text(announcement.month)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(announcement.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(announcement.channel) · \(announcement.subtitle)")
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
}

#Preview {
    RootView()
        .environment(Session())
        .environment(AuthManager())
        .environment(MembershipCodeStore())
}
