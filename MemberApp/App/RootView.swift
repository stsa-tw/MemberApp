import SwiftUI

/// Onboarding gate plus the five-tab shell.
///
/// On iOS 26 `TabView` renders the floating Liquid Glass tab bar the prototype
/// mocks up by hand, so there is no custom bar to build — the trailing 會員卡
/// button rides alongside it as a bottom accessory.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var session = session

        Group {
            if session.isSignedIn {
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
                        ProfileView()
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
    }
}

/// The 會員卡 shortcut that sits with the tab bar.
private struct MemberCardAccessory: View {
    @Environment(Session.self) private var session

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
                Text(session.member?.memberNumber ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let session = Session()
    session.signIn()
    return RootView().environment(session)
}
