import SwiftUI

/// An announcement channel a member can follow.
///
/// The mock modelled these as push subscriptions. There is no push
/// infrastructure and no channel backend yet, so for now a channel is a
/// *display* preference — which announcements a member wants to see. The same
/// stored set will drive notifications when there is something to send them.
/// Not Hashable: `LocalizedStringKey` is not, and identity here is `id` anyway.
struct Channel: Identifiable {
    /// Stable key for persistence. Never localised — it is stored, not shown.
    let id: String
    /// SF Symbol, where one carries the meaning. Nil for schools, whose
    /// abbreviation *is* the recognisable mark.
    let symbol: String?
    /// Fallback badge text when `symbol` is nil.
    let badge: String
    /// Distinguishes the rows at a glance. School colours approximate each
    /// institution's palette — only NTU's is taken from its own site
    /// (theme-color #D71440); the others are close, not official.
    let tint: Color
    let name: LocalizedStringKey
    let detail: LocalizedStringKey
    /// School channels are matched against `Profile.school` to preselect.
    let school: String?
}

extension Channel {
    static let all: [Channel] = [
        .init(id: "all", symbol: "megaphone.fill", badge: "STSA",
              tint: Theme.Palette.brand,
              name: "全體公告", detail: "所有會員都會收到的公告",
              school: nil),
        .init(id: "freshmen", symbol: "graduationcap.fill", badge: "新生",
              tint: Color(red: 0.05, green: 0.52, blue: 0.49),
              name: "新生資訊", detail: "迎新、接機、住宿與開學前準備",
              school: nil),
        .init(id: "nus", symbol: nil, badge: "NUS",
              tint: Color(red: 0.94, green: 0.49, blue: 0.00),
              name: "NUS 資訊", detail: "National University of Singapore",
              school: "NUS"),
        .init(id: "ntu", symbol: nil, badge: "NTU",
              tint: Color(red: 0.84, green: 0.08, blue: 0.25),
              name: "NTU 資訊", detail: "Nanyang Technological University",
              school: "NTU"),
        .init(id: "smu", symbol: nil, badge: "SMU",
              tint: Color(red: 0.02, green: 0.22, blue: 0.42),
              name: "SMU 資訊", detail: "Singapore Management University",
              school: "SMU"),
    ]

    /// Sensible starting point: everyone gets the all-members channel and the
    /// freshman feed, plus their own school if the profile knows it.
    static func defaultSubscriptions(school: String?) -> Set<String> {
        var ids: Set<String> = ["all", "freshmen"]
        if let school, let match = all.first(where: { $0.school == school }) {
            ids.insert(match.id)
        }
        return ids
    }
}
