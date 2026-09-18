import SwiftUI

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @State private var errorMessage: String?

    private struct Highlight: Identifiable {
        let id = UUID()
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let highlights: [Highlight] = [
        .init(symbol: "creditcard",
              title: "電子會員卡",
              // Not "離線可用": the QR carries a code that dies after 300s and
              // needs the network to renew, so the card cannot work offline.
              detail: "活動與合作商家皆可出示"),
        .init(symbol: "bubble.left",
              title: "公告頻道",
              detail: "各校分會與新生訊息，一次收齊"),
        .init(symbol: "tag",
              title: "會員優惠與職缺",
              detail: "合作商家折扣碼、在星實習機會"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.stsaLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .padding(.bottom, 22)

            Text("歡迎加入 STSA")
                .font(.largeTitle.weight(.semibold))
                .padding(.bottom, 8)

            Text("Singapore Taiwan Student Association")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 34)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(highlights) { highlight in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: highlight.symbol)
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.Palette.brand)
                            .frame(width: 28)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(highlight.title)
                                .font(.headline)
                            Text(highlight.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 34)

            // Straight into the browser flow — no intermediate screen. There is
            // no sign-up either: accounts are created in authentik, so the app
            // only ever authenticates an existing one.
            VStack(spacing: 8) {
                Button {
                    signIn()
                } label: {
                    if auth.isBusy || indico.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("登入")
                    }
                }
                .buttonStyle(.brand)
                .disabled(auth.isBusy || indico.isBusy)

                // Indico's application is registered as trusted, so it shows no
                // consent screen of its own. Nothing else in the flow will tell
                // the member their Indico account is being connected, so this
                // line has to — before it happens, not after.
                Text("登入會一併連結你的 Indico 帳號，用來顯示你的報名與票券。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 96)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .alert("登入失敗", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func signIn() {
        Task {
            do {
                try await auth.login()
            } catch {
                // Dismissing the sign-in sheet is a choice, not a failure.
                guard !AuthManager.isUserCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
            // The Indico link is chained on in RootView, not here: a successful
            // sign-in swaps this view away immediately.
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
        .environment(IndicoAuthManager())
}
