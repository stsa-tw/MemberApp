import SwiftUI

/// The 我的 tab — what a member actually needs to see about their account.
///
/// For a visitor it is the place to sign in instead: the tab bar still shows
/// 我的, and an empty screen under it would read as broken.
///
/// Built from `GroupedCard` rather than `List` like the other three tabs. A
/// `List` insets its section headers to line up with the row text, which under
/// a large title leaves the header standing 16pt right of both the title and
/// the card — the one thing this screen is not free to restyle.
struct AccountView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let profile = auth.profile {
                        identitySection(profile)
                        if profile.isOfficer { officerSection }
                    } else if !auth.isLoggedIn {
                        signInSection
                    }
                }
                .padding(.top, 6)
            }
            .readableWidth()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private func identitySection(_ profile: Profile) -> some View {
        VStack(spacing: 0) {
            GroupedCardHeader("身分")
            GroupedCard {
                row("姓名") { Text(profile.displayName) }

                if let email = profile.email {
                    RowSeparator()
                    row("信箱") {
                        HStack(spacing: 6) {
                            Text(email)
                            if profile.emailVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("已驗證")
                            }
                        }
                    }
                }

                if let school = profile.school {
                    RowSeparator()
                    row("學校") { Text(school) }
                }
            }
        }
    }

    /// Joining is a link out rather than a flow in the app: accounts are created
    /// through the membership site, and the app only ever authenticates an
    /// existing one.
    private var signInSection: some View {
        VStack(spacing: 12) {
            Text("尚未登入")
                .font(.headline)
            Text("登入 STSA 帳號後，就能使用電子會員卡，並查看你的活動報名與票券。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SignInButton { Text("登入") }
                .buttonStyle(.brand)
                .padding(.top, 4)
            Link("還不是會員？加入 STSA", destination: URL(string: "https://idms.stsa.tw/membership/#/")!)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Metrics.gutter)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    /// The scanner, for the people who work the door.
    ///
    /// `isOfficer` reads a self-reported claim, so this hides a row rather than
    /// guarding anything — and `/validate_code` is open to begin with. Making it
    /// a real boundary is a MembershipAPI change, not one that can happen here.
    private var officerSection: some View {
        VStack(spacing: 0) {
            GroupedCardHeader("幹部")
            GroupedCard {
                NavigationLink {
                    ScanView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundStyle(Theme.Palette.brand)
                        Text("掃描會員卡")
                            .foregroundStyle(.primary)
                        Spacer()
                        DisclosureChevron()
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Label left, value right — what `LabeledContent` gave us inside a `List`.
    private func row<Value: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 0)
            value()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
    }
}

#Preview {
    AccountView().environment(AuthManager())
}
