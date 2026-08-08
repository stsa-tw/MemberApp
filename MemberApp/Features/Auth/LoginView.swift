import SwiftUI

/// Minimal harness for verifying the OIDC flow end to end.
///
/// Deliberately plain — this is not a design screen. It exposes the three
/// things worth checking by hand: that the browser round-trip completes, that
/// authentik returned a refresh token, and that `accessToken()` silently
/// renews once the 5-minute access token has expired.
struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

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
                statusSection

                if let profile = auth.profile {
                    identitySection(profile)
                    if !profile.groups.isEmpty { groupsSection(profile) }
                }

                actionsSection

                if let errorMessage {
                    Section("錯誤") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("帳號")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear { snapshot = auth.snapshot() }
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section("狀態") {
            LabeledContent("已登入", value: auth.isLoggedIn ? "是" : "否")
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
            if let scopes = snapshot.scopesGranted {
                LabeledContent("Scopes", value: scopes)
                    .font(.footnote)
            }
        }
    }

    private func identitySection(_ profile: Profile) -> some View {
        Section {
            LabeledContent("sub") {
                Text(profile.sub)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            if let name = profile.name { LabeledContent("name", value: name) }
            if let username = profile.preferredUsername {
                LabeledContent("preferred_username", value: username)
            }
            if let nickname = profile.nickname { LabeledContent("nickname", value: nickname) }
            if let email = profile.email {
                LabeledContent("email") {
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
        } header: {
            Text("身分")
        } footer: {
            Text("本機資料一律以 sub 為索引 — email 與 username 都可能變更。")
        }
    }

    private func groupsSection(_ profile: Profile) -> some View {
        Section {
            ForEach(profile.groups, id: \.self) { group in
                Text(group).font(.footnote.monospaced())
            }
        } header: {
            Text("Groups")
        } footer: {
            Text("僅供介面判斷使用。實際權限一律由後端依 token 簽章重新驗證。")
        }
    }

    private var actionsSection: some View {
        Section {
            if auth.isLoggedIn {
                Button("取得 access token（驗證 silent refresh）") {
                    run { _ = try await auth.accessToken(); lastTokenFetch = Date() }
                }
                Button("登出", role: .destructive) {
                    auth.logout()
                    snapshot = auth.snapshot()
                    lastTokenFetch = nil
                }
            } else {
                Button("使用 STSA 帳號登入") {
                    run { try await auth.login() }
                }
                .disabled(auth.isBusy)
            }
        } footer: {
            if let lastTokenFetch {
                Text("上次取得 token：\(lastTokenFetch.formatted(date: .omitted, time: .standard))。到期後再按一次，「到期」時間應自動往後跳。")
            } else {
                Text("登入會開啟 ASWebAuthenticationSession，與 Safari 共用登入狀態。")
            }
        }
    }

    // MARK: - Helpers

    private func run(_ work: @escaping () async throws -> Void) {
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            snapshot = auth.snapshot()
        }
    }

    private func remaining(until expiry: Date) -> String {
        let seconds = Int(expiry.timeIntervalSince(now))
        guard seconds > 0 else { return "已過期" }
        return "\(seconds / 60)分 \(seconds % 60)秒"
    }
}

#Preview {
    LoginView().environment(AuthManager())
}
