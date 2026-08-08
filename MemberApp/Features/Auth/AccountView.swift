import SwiftUI

/// The 我的 tab — what a member actually needs to see about their account.
///
/// Only reachable behind the auth gate, so there is no sign-in branch; that
/// lives on `WelcomeView`. Token plumbing is diagnostic, not member-facing, so
/// it is confined to a debug-only section at the bottom.
struct AccountView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            List {
                if let profile = auth.profile {
                    identitySection(profile)
                    if !profile.groups.isEmpty { groupsSection(profile) }
                }

                Section {
                    Button("登出", role: .destructive) {
                        auth.logout()
                    }
                } footer: {
                    Text("登出只會清除這支手機上的憑證。因為登入與 Safari 共用工作階段，下次登入可能不需要重新輸入密碼。")
                }

                #if DEBUG
                TokenDiagnostics()
                #endif
            }
            .navigationTitle("我的")
        }
    }

    private func identitySection(_ profile: Profile) -> some View {
        Section("身分") {
            LabeledContent("姓名", value: profile.displayName)
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
        }
    }

    /// Shown because members care which departments they are in. Note that these
    /// drive display only — see the comment on `Profile.groups`.
    private func groupsSection(_ profile: Profile) -> some View {
        Section("身分組") {
            ForEach(profile.groups, id: \.self) { group in
                Text(group)
            }
        }
    }
}

// MARK: - Debug only

#if DEBUG
/// Session plumbing, for checking that silent refresh is working. Never built
/// into a release, so it is free to expose `sub` and token timings.
private struct TokenDiagnostics: View {
    @Environment(AuthManager.self) private var auth

    @State private var snapshot = AuthManager.TokenSnapshot(
        hasRefreshToken: false, accessTokenExpiry: nil, scopesGranted: nil
    )
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            LabeledContent("sub") {
                Text(auth.profile?.sub ?? "—")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent("Refresh token", value: snapshot.hasRefreshToken ? "已取得" : "無")
            LabeledContent("Access token 到期") {
                if let expiry = snapshot.accessTokenExpiry {
                    if expiry <= now {
                        Text("已過期，下次使用時自動更新")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(remaining(until: expiry))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                }
            }
            if let scopes = snapshot.scopesGranted {
                LabeledContent("Scopes", value: scopes)
                    .font(.footnote)
            }
        } header: {
            Text("連線狀態（DEBUG）")
        } footer: {
            Text("token 只在有請求時更新，不是定時更新，所以閒置時顯示已過期是正常的。")
        }
        .task {
            await auth.refreshIfNeeded()
            snapshot = auth.snapshot()
        }
        .onReceive(tick) { moment in
            now = moment
            snapshot = auth.snapshot()
        }
    }

    private func remaining(until expiry: Date) -> String {
        let seconds = Int(expiry.timeIntervalSince(now))
        return "\(seconds / 60) 分 \(seconds % 60) 秒後"
    }
}
#endif

#Preview {
    AccountView().environment(AuthManager())
}
