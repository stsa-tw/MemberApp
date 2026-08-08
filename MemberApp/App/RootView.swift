import SwiftUI

/// Auth gate plus the five-tab shell.
///
/// On iOS 26 `TabView` renders the floating Liquid Glass tab bar the prototype
/// mocks up by hand, so there is no custom bar to build — the trailing 會員卡
/// button rides alongside it as a bottom accessory.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(EventsStore.self) private var events

    var body: some View {
        @Bindable var session = session
        // Read here, in body, so @Observable registers the dependency. Reading
        // it inside the accessory closure does not — the closure runs outside
        // body evaluation, and the accessory never updates.
        let showsAccessory = !session.hidesCardAccessory

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
                    if showsAccessory {
                        MemberCardAccessory()
                    }
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $session.isShowingMemberCard) {
            MemberCardView()
        }
        // Loaded here rather than in EventsView: Home shows the upcoming count
        // too, and it was reading an empty store until the events tab was first
        // opened.
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
