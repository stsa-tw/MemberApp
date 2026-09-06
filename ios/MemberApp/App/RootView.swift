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
        /// Part of the identity of the moment, so the task re-runs once the
        /// profile arrives rather than having already given up without it.
        let email: String?
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(EventsStore.self) private var events
    @Environment(TicketStore.self) private var tickets
    @Environment(MembershipCodeStore.self) private var codes
    @Environment(CheckinStore.self) private var checkin

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
            if !isLoggedIn { endSession() }
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
        //
        // Waits for the profile, and not only because the link is nicer with one:
        // `IndicoAuthManager.verifyOwner` checks the token it gets against this
        // member's address, and with no address to check against it has nothing
        // to refuse. Linking before the profile lands would skip the one test
        // that catches a browser still signed in as somebody else.
        .task(id: LinkMoment(isLoggedIn: auth.isLoggedIn,
                             phase: scenePhase,
                             email: auth.profile?.email)) {
            guard scenePhase == .active, auth.isLoggedIn,
                  auth.profile?.email != nil,
                  !indico.isLinked, !hasTriedLinking
            else { return }

            hasTriedLinking = true
            try? await indico.link()
        }
        .task(id: auth.profile?.sub) {
            tickets.subject = auth.profile?.sub
            // What an Indico token is checked against — see `verifyOwner`.
            indico.expectedEmail = auth.profile?.email
        }
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn, events.events.isEmpty else { return }
            await events.load()
        }
    }

    /// Drops everything that belonged to whoever was signed in.
    ///
    /// Here, on the session ending, rather than in the 登出 button — because a
    /// session also ends on its own. `AuthManager` signs out by itself when
    /// authentik refuses a refresh token, and that path went through no button:
    /// it left the Indico link, the roster and the door's `.allowed` verdict
    /// standing in memory. The next person to sign in on that device inherited
    /// them — the event page offered them 幹部功能, and every Indico request went
    /// out under the previous member's token, which is Indico's answer to who
    /// may open the door.
    ///
    /// `hasTriedLinking` resets with them, so the next member links their own
    /// Indico account instead of riding on one that is no longer theirs.
    private func endSession() {
        session.isShowingMemberCard = false
        indico.unlink()
        codes.clear()
        tickets.clear()
        checkin.clear()
        hasTriedLinking = false
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
