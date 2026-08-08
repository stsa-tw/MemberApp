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
    /// Short badge text, e.g. "NUS".
    let badge: String
    let name: LocalizedStringKey
    let detail: LocalizedStringKey
    /// School channels are matched against `Profile.school` to preselect.
    let school: String?
}

extension Channel {
    static let all: [Channel] = [
        .init(id: "all", badge: "STSA",
              name: "全體公告", detail: "所有會員都會收到的公告",
              school: nil),
        .init(id: "freshmen", badge: "新生",
              name: "新生資訊", detail: "迎新、接機、住宿與開學前準備",
              school: nil),
        .init(id: "nus", badge: "NUS",
              name: "NUS 分會", detail: "National University of Singapore",
              school: "NUS"),
        .init(id: "ntu", badge: "NTU",
              name: "NTU 分會", detail: "Nanyang Technological University",
              school: "NTU"),
        .init(id: "smu", badge: "SMU",
              name: "SMU 分會", detail: "Singapore Management University",
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
