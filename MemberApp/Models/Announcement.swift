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
    var contact: String
}

extension Announcement {
    static let samples: [Announcement] = [
        .init(day: "24", month: "AUG", channel: "全體公告",
              title: "迎新晚會報名開跑",
              subtitle: "Freshman Night registration open",
              body: [
                "一年一度的迎新晚會回來了。今年在 Clarke Quay 的 The Pier，晚上六點入場，會有自助餐、抽獎與各校介紹。名額 220 位，額滿為止。",
                "新生免費，舊生每人 S$12，現場以會員卡核銷。報名截止 8 月 30 日。",
              ],
              when: "8月24日 (六) 18:00",
              place: "The Pier, Clarke Quay",
              contact: "活動組 · 林芷妤"),
        .init(day: "21", month: "AUG", channel: "新生 2026",
              title: "新生接機志工招募",
              subtitle: "Airport pickup volunteers",
              body: [
                "八月底是新生抵星高峰，我們在 T1 與 T3 排班接機，協助新生搭車、辦電話卡與開戶。",
                "志工可累積服務時數，並優先參加幹部培訓。一班約三小時。",
              ],
              when: "8月21日–9月2日",
              place: "Changi T1 / T3",
              contact: "生活組 · 黃彥廷"),
        .init(day: "18", month: "AUG", channel: "NUS 分會",
              title: "中秋烤肉名額釋出",
              subtitle: "Mid-Autumn BBQ extra slots",
              body: [
                "因場地調整，中秋烤肉再開放 40 個名額，地點在 East Coast Park F 區。",
                "每人 S$18，含食材與飲料，素食請於報名時註明。",
              ],
              when: "9月14日 (六) 17:00",
              place: "East Coast Park, Area F",
              contact: "NUS 分會 · 吳承翰"),
        .init(day: "12", month: "AUG", channel: "全體公告",
              title: "合作商家新增五間",
              subtitle: "Five new partner merchants",
              body: [
                "本月新增五間合作商家，涵蓋餐飲、旅遊與語言中心，折扣碼已同步到「優惠」頁。",
                "若你想推薦自家或熟識的店家合作，可從「我的 → 商家合作」提出。",
              ],
              when: "即日起",
              place: "優惠頁面",
              contact: "公關組 · 蔡宜庭"),
    ]
}
