import SwiftUI

/// One line at the top of a screen, saying why the Indico half of it is empty.
///
/// Two states, one shape. Both used to be invisible until the member opened a
/// particular event and read to the bottom of it:
///
/// - **Not linked at all.** The app used to connect Indico by itself at launch,
///   which meant a system permission alert on 首頁 for every member, most of whom
///   never open a ticket. That is gone — so something has to say that tickets
///   exist and are one tap away, or nobody finds out.
/// - **The two accounts disagree.** Deliberately *only* a statement and a way
///   in. A banner with an action would be picking a side, and picking a side is
///   the one thing the app cannot do here: it knows the identities differ, not
///   which of them is the member. `IndicoAccountView` is where that is decided,
///   with both identities visible.
struct IndicoStatusBanner: View {
    enum State {
        case notLinked
        case mismatch
    }

    let state: State
    /// Run for `.notLinked` only. The mismatch case navigates instead.
    var onLink: () -> Void = {}

    var body: some View {
        switch state {
        case .mismatch:
            NavigationLink { IndicoAccountView() } label: { row }
                .buttonStyle(.plain)

        case .notLinked:
            Button(action: onLink) { row }
                .buttonStyle(.plain)
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)
            DisclosureChevron()
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .contentShape(.rect)
    }

    private var symbol: String {
        switch state {
        case .notLinked: "ticket"
        case .mismatch: "person.2.badge.key.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .notLinked: Theme.Palette.brand
        case .mismatch: .orange
        }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .notLinked: "查看你的票券"
        case .mismatch: "帳號對不上"
        }
    }

    private var detail: LocalizedStringKey {
        switch state {
        // The first-time sentence is not a detail. Indico creates its account
        // on first sign-in and parks the authorization behind a profile form,
        // so a member who has never used the event site meets a stranger's web
        // form asking for their name, with no way to tell whether filling it in
        // will bring them back. Said here, it is a step; discovered there, it
        // looks like the app broke.
        case .notLinked: "連結活動網站帳號，就能在這裡看到自己的報名與票券。第一次連結時，活動網站會請你建立個人資料。"
        case .mismatch: "App 和活動網站登入的不是同一個人。"
        }
    }
}
