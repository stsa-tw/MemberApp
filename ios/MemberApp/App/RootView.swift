import SwiftUI

/// Auth gate plus the five-tab shell.
///
/// On iOS 26 `TabView` renders the floating Liquid Glass tab bar the prototype
/// mocks up by hand, so there is no custom bar to build — the trailing 會員卡
/// button rides alongside it as a bottom accessory.
struct RootView: View {
    /// Re-evaluates the link attempt when the session or the scene changes, and
    /// not on every redraw.
    private struct LinkMoment: Equatable {
        let isLoggedIn: Bool
        let phase: ScenePhase
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(EventsStore.self) private var events
    @Environment(TicketStore.self) private var tickets

    @State private var hasTriedLinking = false

    var body: some View {
        @Bindable var session = session

        Group {
            if auth.isLoggedIn {
                TabView(selection: $session.selectedTab) {
                    Tab("首頁", systemImage: "house.fill", value: Session.Tab.home) {
                        HomeView()
                    }
                    Tab("活動", systemImage: "calendar", value: Session.Tab.events) {
                        EventsView()
                    }
                    Tab("優惠", systemImage: "tag.fill", value: Session.Tab.deals) {
                        DealsView()
                    }
                    Tab("職缺", systemImage: "briefcase.fill", value: Session.Tab.jobs) {
                        JobsView()
                    }
                    Tab("我的", systemImage: "person.fill", value: Session.Tab.profile) {
                        AccountView()
                    }
                }
                .tabViewBottomAccessory {
                    MemberCardAccessory()
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $session.isShowingMemberCard) {
            MemberCardView()
        }
        // An expired session drops the app back to Welcome; a card sheet left
        // standing over it would be a dead credential on top of a sign-in screen.
        .onChange(of: auth.isLoggedIn) { _, isLoggedIn in
            if !isLoggedIn { session.isShowingMemberCard = false }
        }
        // Loaded here rather than in EventsView: Home shows the upcoming count
        // too, and it was reading an empty store until the events tab was first
        // opened.
        // Link Indico as soon as there is a session, rather than making the
        // member find a button for it. It lives here rather than in WelcomeView
        // because signing in swaps that view away the moment it succeeds, and a
        // browser round-trip started there would be torn down mid-flight.
        //
        // Gated on `.active`, not merely on being signed in: a browser session
        // cannot be presented from a scene that is still coming up, and trying
        // anyway is what crashed the first device build. Once per launch, so
        // dismissing it does not mean meeting it again on every return to the app.
        //
        // Deliberately `try?`: nothing here may break the signed-in shell. When it
        // does not complete, the events screen still offers to link.
        .task(id: LinkMoment(isLoggedIn: auth.isLoggedIn, phase: scenePhase)) {
            guard scenePhase == .active, auth.isLoggedIn,
                  !indico.isLinked, !hasTriedLinking
            else { return }

            hasTriedLinking = true
            try? await indico.link()
        }
        .task(id: auth.profile?.sub) {
            tickets.subject = auth.profile?.sub
        }
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn, events.events.isEmpty else { return }
            await events.load()
        }
    }
}

/// The 會員卡 shortcut that sits with the tab bar.
private struct MemberCardAccessory: View {
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico

    var body: some View {
        Button {
            session.isShowingMemberCard = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(Theme.Palette.brand)
                Text("會員卡")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let name = auth.profile?.displayName {
                    Text(name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
