import SwiftUI

@main
struct MemberAppApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.Palette.brand)
        }
    }
}
