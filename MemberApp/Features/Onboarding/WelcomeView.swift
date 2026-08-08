import SwiftUI

struct WelcomeView: View {
    @Environment(Session.self) private var session
    @State private var isSigningUp = false
    @State private var isLoggingIn = false

    private struct Highlight: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let highlights: [Highlight] = [
        .init(symbol: "creditcard",
              title: "電子會員卡",
              detail: "離線可用，活動與商家皆可出示"),
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

            Button("加入會員") { isSigningUp = true }
                .buttonStyle(.brand)

            Button("我已經是會員，登入") { isLoggingIn = true }
                .buttonStyle(.brandPlain)
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 96)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .sheet(isPresented: $isSigningUp) {
            SignUpView()
        }
        .sheet(isPresented: $isLoggingIn) {
            LoginView()
        }
    }
}

#Preview {
    WelcomeView()
        .environment(Session())
        .environment(AuthManager())
}
