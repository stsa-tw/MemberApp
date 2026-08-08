import SwiftUI

@main
struct MemberAppApp: App {
    @State private var session = Session()
    @State private var auth = AuthManager()
    @State private var codes = MembershipCodeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(auth)
                .environment(codes)
                .tint(Theme.Palette.brand)
                .onOpenURL { url in
                    // tw.stsa.membership://callback — hand the authorization
                    // code back to the in-flight AppAuth request.
                    auth.resume(url)
                }
        }
    }
}
