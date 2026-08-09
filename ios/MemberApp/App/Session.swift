import SwiftUI

/// Navigation state that outlives any one screen.
///
/// Identity deliberately does not live here — `AuthManager` owns whether there
/// is a session and who it belongs to. Keeping a second copy is what previously
/// let a successful OIDC login leave the app sitting on the welcome screen.
@Observable
final class Session {
    enum Tab: Hashable {
        case home, events, deals, jobs, profile
    }

    var selectedTab: Tab = .home
    var isShowingMemberCard = false

}
