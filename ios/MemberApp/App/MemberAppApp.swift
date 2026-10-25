import SwiftUI

@main
struct MemberAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = Session()
    @State private var auth = AuthManager()
    @State private var indico = IndicoAuthManager()
    @State private var codes = MembershipCodeStore()
    @State private var events = EventsStore()
    @State private var tickets = TicketStore()
    @State private var checkin = CheckinStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .launchScreen()
                .environment(session)
                .environment(auth)
                .environment(indico)
                .environment(codes)
                .environment(events)
                .environment(tickets)
                .environment(checkin)
                .environment(settings)
                .tint(Theme.Palette.brand)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onOpenURL { url in
                    // tw.stsa.membership://callback — hand the authorization
                    // code back to the in-flight AppAuth request. The Indico flow
                    // also returns through this scheme, but its browser session
                    // captures the callback itself, so only authentik needs this.
                    auth.resume(url)
                }
                // onChange does not fire for the initial value, so the launch
                // case needs its own pass.
                .task {
#if DEBUG
                    applyScreenshotFixtures()
#endif
                    await auth.refreshIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Coming back from the background is where the token has
                    // usually lapsed; renewing here keeps the first tap instant.
                    guard phase == .active else { return }
                    Task { await auth.refreshIfNeeded() }
                }
        }
    }

#if DEBUG
    /// Stands up the fictional member and opens the screen named in the launch
    /// environment. Inert unless `STSA_SCREENSHOT=1` — see `ScreenshotFixtures`.
    private func applyScreenshotFixtures() {
        guard ScreenshotFixtures.isEnabled else { return }

        auth.injectScreenshotFixture(ScreenshotFixtures.member)
        codes.injectScreenshotFixture(payload: ScreenshotFixtures.membershipCode)
        // The simulator answers `canEvaluatePolicy` with a passcode prompt no
        // one can type into from a capture script, so the card would screenshot
        // as a keyboard. The gate is not what is being photographed.
        settings.requireBiometricsForCard = false

        switch ScreenshotFixtures.screen {
        case .home: session.selectedTab = .home
        case .events: session.selectedTab = .events
        case .deals: session.selectedTab = .deals
        case .jobs: session.selectedTab = .jobs
        case .profile: session.selectedTab = .profile
        case .card: session.isShowingMemberCard = true
        // The ticket is a pushed screen, not a tab, so `RootView` raises it —
        // this only picks the tab it is raised over.
        case .ticket: session.selectedTab = .events
        }
    }
#endif
}
