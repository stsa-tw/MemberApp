import SwiftUI

@main
struct MemberAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = Session()
    @State private var auth = AuthManager()
    @State private var codes = MembershipCodeStore()
    @State private var events = EventsStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(auth)
                .environment(codes)
                .environment(events)
                .environment(settings)
                .tint(Theme.Palette.brand)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onOpenURL { url in
                    // tw.stsa.membership://callback — hand the authorization
                    // code back to the in-flight AppAuth request.
                    auth.resume(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Coming back from the background is where the token has
                    // usually lapsed; renewing here keeps the first tap instant.
                    guard phase == .active else { return }
                    Task { await auth.refreshIfNeeded() }
                }
        }
    }
}
