import SwiftUI

/// App-wide state: who is signed in, and which tab is showing.
///
/// The prototype models 21 screens as one `screen` string; natively that splits
/// into (a) an onboarding-vs-app gate and (b) per-tab `NavigationStack` paths,
/// so back gestures, large-title collapse and state restoration come for free.
@Observable
final class Session {
    enum Tab: Hashable {
        case home, events, deals, jobs, profile
    }

    /// `nil` until sign-up completes — drives the onboarding gate in `RootView`.
    var member: Member?
    var selectedTab: Tab = .home
    var isShowingMemberCard = false

    var isSignedIn: Bool { member != nil }

    func signIn(as member: Member = .sample) {
        self.member = member
    }
}
