import SwiftUI

/// Auth gate plus the five-tab shell.
///
/// On iOS 26 `TabView` renders the floating Liquid Glass tab bar the prototype
/// mocks up by hand, so there is no custom bar to build — the trailing 會員卡
/// button rides alongside it as a bottom accessory.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(EventsStore.self) private var events
    @Environment(TicketStore.self) private var tickets
    @Environment(MembershipCodeStore.self) private var codes
    @Environment(CheckinStore.self) private var checkin


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
        // A token that turns out to be somebody else's did not only fail to be
        // theirs — it had already been believed. Every answer it gave was filed
        // under *this* member: which events they hold a ticket for, and the door
        // roster. `TicketStore` keeps its answers across launches on purpose, so
        // without this the officer's tickets stayed cached under the member's
        // own key, and the event page went on showing 查看票券 for an event they
        // had never registered for — with no 連結 button anywhere, because as
        // far as the app knew the question was already settled.
        .onChange(of: indico.refused) { _, refused in
            guard refused != nil else { return }
            tickets.clear()
            checkin.clear()
        }
        // Loaded here rather than in EventsView: Home shows the upcoming count
        // too, and it was reading an empty store until the events tab was first
        // opened.
        // Indico is deliberately *not* linked here.
        //
        // It used to be, so nobody had to find a button for it. But that flow
        // opens `ASWebAuthenticationSession`, and iOS puts its own
        // "…Wants to Use event.stsa.tw to Sign In" alert in front of every
        // non-ephemeral one — so a member who had just signed in met a system
        // permission dialog on 首頁, naming a site they had not asked about,
        // before touching anything. Most members never open a ticket at all.
        //
        // So it happens where it means something instead: 活動 → the event's
        // 查看我的票券, which says what is being connected and why, and which is
        // also allowed to re-authenticate when the browser is signed in as
        // somebody else.
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
    private func endSession() {
        session.isShowingMemberCard = false
        indico.unlink()
        codes.clear()
        tickets.clear()
        checkin.clear()
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
