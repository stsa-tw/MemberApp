import SwiftUI

/// What to do when the app and the event site do not agree about who is holding
/// the phone.
///
/// A page of its own, because the decision it asks for cannot be made from a
/// banner. The app knows the two identities differ; it cannot know **which one
/// is the member** — a phone that someone else signed into the event site on,
/// and a phone that someone else signed into *this app* on, produce the same
/// mismatch and need opposite fixes. Only the person can tell them apart, and
/// only if they can see who each side thinks they are.
///
/// So both identities get a name as well as an address. A member with a school
/// address, a personal one and an old one cannot recognise themselves from an
/// address alone, and "which of these two is you" is the entire question.
struct IndicoAccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var failure: String?
    @State private var hasCopied = false

    private var refused: IndicoAuthManager.RefusedAccount? { indico.refused }

    /// The same name on both sides means this is almost certainly one person
    /// whose address drifted on one system, rather than two people — which is
    /// the one shape of this problem that nobody can fix by signing in again.
    private var looksLikeSamePerson: Bool {
        guard let refused, let indicoName = refused.name?.lowercased(),
              let appName = auth.profile?.displayName.lowercased()
        else { return false }
        return indicoName == appName
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                identities
                advice
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("帳號對不上")
        .navigationBarTitleDisplayMode(.inline)
        // Nothing left to explain once the two sides agree.
        .onChange(of: indico.refused) { _, refused in
            if refused == nil { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.badge.key.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("這支手機上有兩個不同的人")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("STSA App 和活動網站登入的不是同一個帳號，所以票券和報到都停住了。**沒有連結任何東西，也沒有讀取任何資料。**")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Who each side thinks you are

    private var identities: some View {
        VStack(spacing: 12) {
            identity(
                system: "STSA App",
                name: auth.profile?.displayName,
                address: auth.profile?.email,
                action: "這不是我，重新登入 App",
                note: "會登出這支手機，下次登入時會問你是誰。",
                role: .app
            )

            identity(
                system: "活動網站",
                name: refused?.name,
                address: refused?.indico,
                action: "這不是我，重新登入活動網站",
                note: "只會重新登入活動網站，不影響 App。如果你在活動網站上還沒有帳號，它會先請你填姓名建立個人資料；完成後若沒有自動回到 App，關掉視窗再按一次就好。",
                role: .indico
            )
        }
    }

    private enum Side { case app, indico }

    private func identity(
        system: LocalizedStringKey,
        name: String?,
        address: String?,
        action: LocalizedStringKey,
        note: LocalizedStringKey,
        role: Side
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(system)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(name ?? String(localized: "未知"))
                    .font(.title3.weight(.semibold))
                Text(address ?? String(localized: "沒有地址"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button(action) {
                Task { await replace(role) }
            }
            .buttonStyle(.brandPlain)
            .disabled(isWorking)

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Metrics.gutter)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    // MARK: - What we think happened

    /// Ranked rather than listed. The app has two real signals — whether the
    /// member has already signed in themselves, and whether both sides carry the
    /// same name — and handing someone a menu of causes they have to diagnose,
    /// when we already know which is likeliest, is work we are refusing to do
    /// for them.
    @ViewBuilder
    private var advice: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedCardHeader(looksLikeSamePerson ? "看起來都是你" : "最可能是什麼")

            VStack(alignment: .leading, spacing: 10) {
                if looksLikeSamePerson {
                    Text("兩邊的名字一樣，所以這多半是**同一個人的兩個地址**：其中一邊登記的信箱是舊的。這個沒辦法靠重新登入解決，需要有人去改。")
                } else if refused?.afterSigningIn == true {
                    Text("你剛才已經自己登入過活動網站，所以不是「別人還登著」的問題。你手上那個活動網站帳號，**登記的信箱和 App 不同**。")
                } else {
                    Text("最常見的原因是**這支手機的瀏覽器還留著別人的活動網站登入**。如果上面「活動網站」那個名字你不認得，按它下面的按鈕重新登入就會恢復。")
                }

                Text("如果兩個都是你，把下面這段話傳給幹部，請他們把活動網站上的信箱改成和 App 一致：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(handoffMessage)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(.rect(cornerRadius: Theme.Radius.list))

                Button(hasCopied ? "已複製" : "複製這段話") {
                    UIPasteboard.general.string = handoffMessage
                    hasCopied = true
                }
                .buttonStyle(.brandPlain)
            }
            .font(.footnote)
            .padding(Theme.Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
    }

    /// Written to be pasted somewhere else, so it names both systems and both
    /// addresses without assuming whoever reads it has the phone in front of
    /// them.
    private var handoffMessage: String {
        let app = auth.profile?.email ?? String(localized: "（未知）")
        let site = refused?.indico ?? String(localized: "（未知）")
        return String(localized: """
        我的 STSA App 帳號是 \(app)，活動網站上的帳號是 \(site)，兩個對不上，票券和報到無法使用。請幫我把活動網站上的信箱改成 \(app)。
        """)
    }

    // MARK: - Actions

    private func replace(_ side: Side) async {
        isWorking = true
        defer { isWorking = false }
        failure = nil

        switch side {
        case .app:
            // Sets authentik's `prompt=login` for the next sign-in, so the
            // browser's own session cannot silently return the same person —
            // which is exactly how the wrong account got in here.
            auth.logout()

        case .indico:
            do {
                try await indico.link(forcingSignIn: true)
            } catch {
                guard !AuthManager.isUserCancellation(error) else { return }
                failure = error.localizedDescription
            }
        }
    }
}
