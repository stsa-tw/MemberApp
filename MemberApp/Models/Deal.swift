import Foundation
import SwiftUI

/// A partner offer for STSA members.
///
/// The mock assumed one shared member code across every merchant. The real
/// offers each carry their own code, and some carry none at all — HSBC is an
/// information partnership, not a discount. So `code` is optional and belongs
/// to the deal rather than to the member.
struct Deal: Identifiable, Hashable {
    /// Partner logo, from stsa.tw's own uploads. These are horizontal lockups,
    /// so they are letterboxed rather than cropped to a square.
    let logo: ImageResource
    var brand: String
    var brandEnglish: String?
    /// Short headline, e.g. "85 折". Nil when the offer is not a discount.
    var headline: String?
    var summary: String
    var terms: [String]
    var code: String?
    /// Absent when the offer has no stated end date.
    var expires: DateComponents?
    var link: URL?

    var id: String { brand }

    /// Deals expire quietly; showing an expired code as if it works is worse
    /// than hiding it.
    func hasExpired(on date: Date = Date()) -> Bool {
        guard let expires, let end = Calendar.current.date(from: expires) else { return false }
        return date > end
    }

    var expiryLabel: String? {
        guard let expires, let year = expires.year, let month = expires.month, let day = expires.day
        else { return nil }
        return "至 \(year)/\(month)/\(day)"
    }
}

extension Deal {
    static let samples: [Deal] = [
        .init(logo: .bluebirdLogo,
              brand: "青鳥旅行",
              brandEnglish: "Bluebird Travel",
              headline: "85 折",
              summary: "實體門市出示會員證享 85 折，官網另有專屬折扣碼。",
              terms: [
                "實體門市出示會員證享 85 折，不與現場其他優惠活動共用",
                "官網折扣碼不與其他優惠活動共用",
                "實體門市暫無使用期限",
              ],
              code: "15OFF4STSA",
              expires: DateComponents(year: 2026, month: 6, day: 30)),

        .init(logo: .finetableLogo,
              brand: "良人食堂",
              brandEnglish: "Finetable",
              headline: "9 折",
              summary: "全站 9 折，最低消費 $60，可與免運折扣一起使用。",
              terms: [
                "最低消費 $60",
                "可與免運折扣一起使用",
                "每人不限使用次數",
                "除禮品卡外，其他商品皆可使用",
              ],
              code: "ONLYFORSTSA"),

        .init(logo: .hsbcLogo,
              brand: "HSBC 滙豐 Premier",
              brandEnglish: "全球留學理財好夥伴",
              summary: "為留學生與家庭提供全球金融服務，出發前即可開立海外帳戶，抵達後立即啟用。",
              terms: [
                "出發前即可開立海外帳戶，抵達當地後立即啟用",
                "全球帳戶連結，跨國轉帳快速安全，即時查詢匯率",
                "多幣種帳戶支援多達 11 種貨幣，海外提款手續費優惠",
                "多層級換匯優惠方案",
                "新加坡開戶需準備：身分證明文件（如護照）、現居地址證明",
              ]),
    ]
}
