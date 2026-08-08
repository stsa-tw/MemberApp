import Foundation

struct Announcement: Identifiable, Hashable {
    let id = UUID()
    var day: String
    var month: String
    var channel: String
    var title: String
    var subtitle: String
    var body: [String]
    var when: String
    var place: String
    /// Optional — omitted rather than filled with a made-up name.
    var contact: String?
    /// Indico event this announcement is about, if any. Drives the CTA.
    var eventURL: URL?
}

extension Announcement {
    /// Placeholder content until announcements have a real source. Kept to the
    /// one real thing that is actually happening, drawn from Indico event 10 —
    /// inventing a feed of fake notices makes the app look finished when the
    /// backing service does not exist yet.
    static let samples: [Announcement] = [
        .init(day: "08", month: "AUG", channel: "全體公告",
              title: "國際商務人才培訓工作坊報名開跑",
              subtitle: "Slasify x SLI x STSA workshop registration open",
              body: [
                "Slasify x SLI x STSA 國際商務人才培訓工作坊開放報名。免費限量 20 席，並有機會優先媒合實習計畫。",
                "報名截止 8 月 12 日（三）23:59，額滿為止。報名於 Indico 完成，使用同一個 STSA 帳號登入即可。",
              ],
              when: "8月15日（六）13:30–15:30",
              place: "i2Hub, 60A Orchard Road #04-32",
              eventURL: URL(string: "https://event.stsa.tw/event/10/")),
    ]
}
