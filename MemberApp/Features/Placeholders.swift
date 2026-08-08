import SwiftUI

// MARK: - Screens still to be built from `STSA App.dc.html`
//
// Each stub stands in for one prototype screen so the shell compiles and runs.
// Replace them one file at a time; delete the stub from here as you go.

/// Placeholder body shared by the stubs below.
private struct Stub: View {
    let title: String
    let note: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "square.dashed", description: Text(note))
                .navigationTitle(title)
        }
    }
}

struct ChannelsView: View {
    var body: some View { Stub(title: "頻道", note: "各校分會與新生頻道的推播訂閱開關") }
}

struct EventsView: View {
    var body: some View { Stub(title: "活動", note: "活動列表、詳情與票券") }
}

struct DealsView: View {
    var body: some View { Stub(title: "會員優惠", note: "合作商家、折扣碼詳情與出示畫面") }
}

struct JobsView: View {
    var body: some View { Stub(title: "職缺與實習", note: "分段篩選、職缺列表與詳情") }
}

struct ProfileView: View {
    var body: some View { Stub(title: "我的", note: "個人資料、頻道訂閱、Buddy 配對") }
}
