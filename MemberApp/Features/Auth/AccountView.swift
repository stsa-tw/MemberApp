import SwiftUI

/// The 我的 tab: who is signed in, and the controls for verifying the session.
///
/// Only reachable behind the auth gate, so there is no sign-in branch — that
/// lives on `WelcomeView`. The token section is here because silent refresh is
/// otherwise invisible: it exposes the one thing worth checking by hand, that
/// `accessToken()` renews without a browser once the 5-minute token lapses.
struct AccountView: View {
    @Environment(AuthManager.self) private var auth

    @State private var snapshot = AuthManager.TokenSnapshot(
        hasRefreshToken: false, accessTokenExpiry: nil, scopesGranted: nil
    )
    @State private var lastTokenFetch: Date?
    @State private var errorMessage: String?
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                if let profile = auth.profile {
                    identitySection(profile)
                    if !profile.groups.isEmpty { groupsSection(profile) }
                }

                tokenSection
                actionsSection

                if let errorMessage {
                    Section("錯誤") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("我的")
        }
        .onAppear { snapshot = auth.snapshot() }
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Sections

    private func identitySection(_ profile: Profile) -> some View {
        Section {
            LabeledContent("姓名", value: profile.displayName)
            if let username = profile.preferredUsername {
                LabeledContent("帳號", value: username)
            }
            if let email = profile.email {
                LabeledContent("信箱") {
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
                LabeledContent("學校", value: school)
            }
            LabeledContent("sub") {
                Text(profile.sub)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } header: {
            Text("身分")
        } footer: {
            Text("本機資料一律以 sub 為索引 — email 與帳號都可能變更。")
        }
    }

    private func groupsSection(_ profile: Profile) -> some View {
        Section {
            ForEach(profile.groups, id: \.self) { group in
                Text(group).font(.footnote)
            }
        } header: {
            Text("群組")
        } footer: {
            Text("僅供介面判斷使用。實際權限一律由後端依 token 簽章重新驗證。")
        }
    }

    private var tokenSection: some View {
        Section("連線狀態") {
            LabeledContent("Refresh token", value: snapshot.hasRefreshToken ? "已取得" : "無")
            LabeledContent("Access token 到期") {
                if let expiry = snapshot.accessTokenExpiry {
                    Text(expiry, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                } else {
                    Text("—")
                }
            }
            if let expiry = snapshot.accessTokenExpiry {
                LabeledContent("剩餘") {
                    Text(remaining(until: expiry))
                        .monospacedDigit()
                        .foregroundStyle(expiry <= now ? .red : .secondary)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("取得 access token（驗證 silent refresh）") {
                errorMessage = nil
                Task {
                    do {
                        _ = try await auth.accessToken()
                        lastTokenFetch = Date()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    snapshot = auth.snapshot()
                }
            }
            Button("登出", role: .destructive) {
                auth.logout()
                snapshot = auth.snapshot()
                lastTokenFetch = nil
            }
        } footer: {
            if let lastTokenFetch {
                Text("上次取得：\(lastTokenFetch.formatted(date: .omitted, time: .standard))。到期後再按一次,「到期」時間應自動往後跳,且不會跳出瀏覽器。")
            } else {
                Text("登出只會清除這支手機上的憑證。因為登入走的是 Safari 共用工作階段,authentik 的登入狀態仍會保留。")
            }
        }
    }

    private func remaining(until expiry: Date) -> String {
        let seconds = Int(expiry.timeIntervalSince(now))
        guard seconds > 0 else { return "已過期" }
        return "\(seconds / 60)分 \(seconds % 60)秒"
    }
}

#Preview {
    AccountView().environment(AuthManager())
}
