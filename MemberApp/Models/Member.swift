import Foundation

struct Member: Identifiable, Hashable {
    enum University: String, CaseIterable, Identifiable {
        case nus = "NUS"
        case ntu = "NTU"
        case smu = "SMU"
        case sutd = "SUTD"

        var id: Self { self }

        var fullName: String {
            switch self {
            case .nus: "National University of Singapore"
            case .ntu: "Nanyang Technological University"
            case .smu: "Singapore Management University"
            case .sutd: "Singapore University of Technology and Design"
            }
        }
    }

    var id: String { memberNumber }

    var name: String
    var romanisedName: String
    var email: String
    var phone: String
    var university: University
    var year: String
    var memberNumber: String
    var validThrough: DateComponents
}

extension Member {
    /// The persona the prototype is drawn around.
    static let sample = Member(
        name: "陳沐辰",
        romanisedName: "Chen Mu-Chen",
        email: "muchen@u.nus.edu",
        phone: "+65 8123 4567",
        university: .nus,
        year: "大二",
        memberNumber: "2426-0188",
        validThrough: DateComponents(year: 2027, month: 6)
    )

    var validThroughLabel: String {
        guard let month = validThrough.month, let year = validThrough.year else { return "—" }
        return String(format: "%02d / %d", month, year)
    }
}
