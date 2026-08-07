import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session

    private let announcements = Announcement.samples

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    MemberCardBanner()

                    HStack(spacing: 10) {
                        ShortcutTile(symbol: "calendar",
                                     title: "活動報名",
                                     detail: "3 場即將舉行") {
                            session.selectedTab = .events
                        }
                        ShortcutTile(symbol: "person.2.fill",
                                     title: "Buddy 配對",
                                     detail: "新生找學長姐") {
                            session.selectedTab = .profile
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
        let name = session.member.map { String($0.name.dropFirst()) } ?? ""
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
                    if let member = session.member {
                        Text("No. \(member.memberNumber) · 有效至 \(member.validThroughLabel)")
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
    let session = Session()
    session.signIn()
    return RootView().environment(session)
}
