import Foundation

struct Announcement: Identifiable, Hashable {
    let id = UUID()
    var day: String
    var month: String
    var channel: String
    var title: String
    var subtitle: String
    var body: [String]
    /// Optional, both of them, for the same reason `contact` is: a notice about
    /// the app itself happens at no particular hour and in no particular room,
    /// and a row reading "—" states less than no row at all.
    var when: String?
    var place: String?
    /// Optional — omitted rather than filled with a made-up name.
    var contact: String?
    /// Indico event id this announcement is about, if any. Drives the CTA,
    /// which opens the event inside the app rather than on the web.
    var eventID: String?
    /// Fallback for when the event is not in the loaded window, or has been
    /// removed from the category the app reads.
    var eventURL: URL?
}

extension Announcement {
    /// Placeholder content until announcements have a real source. Kept to one
    /// real notice — inventing a feed of fake ones makes the app look finished
    /// when the backing service does not exist yet.
    ///
    /// No time, no place and no event behind it: this one is about the app, so
    /// the facts card and the CTA both drop away. That is the shape every notice
    /// takes once it has a source, rather than a special case for this one.
    static let samples: [Announcement] = [
        .init(day: "18", month: "SEP", channel: "全體公告",
              title: "STSA App 上線了",
              subtitle: "The STSA member app is live",
              body: [
                "STSA App 正式上線。用原本的 STSA 帳號登入，就能出示電子會員卡、查看活動與票券，以及合作商家的會員優惠。",
                "電子會員卡可以在會員活動、領取新生包或合作商家出示。活動報名仍在活動網站上完成，用的是同一個帳號；報名後，票券會出現在那場活動的頁面裡。",
              ]),
    ]
}
