import SwiftUI

/// Signs in from wherever a visitor runs into something that needs an account —
/// the member card, a ticket, the 我的 tab.
///
/// The same `AuthManager.login()` as `WelcomeView`, with the same rule that a
/// dismissed sheet is not an error. Styling is left to the caller, because the
/// places this sits range from a brand slab to the dark card banner on 首頁.
struct SignInButton<Label: View>: View {
    @Environment(AuthManager.self) private var auth
    @State private var errorMessage: String?

    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            signIn()
        } label: {
            label()
        }
        .disabled(auth.isBusy)
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
                guard !AuthManager.isUserCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
