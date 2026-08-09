import SwiftUI

/// Mirrors https://stsa.tw/about/ so members can read it without leaving the app.
///
/// The copy is STSA's own, transcribed rather than rewritten. If the website
/// changes, this is the file to update — there is no backend for it, and one
/// hardcoded page is cheaper than a content service for text that changes once
/// a year.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                section("成立宗旨") {
                    paragraph("全世界各地的大學都有台灣學生會（TSA）。在各個國家，TSA 能夠從當地台北辦事處得到第一手的資源，台灣留學生則可透過 TSA 獲得許多協助，更快熟悉陌生環境，並建立彼此互助的管道。我們希望把 TSA 的制度帶進新加坡，但因當地政策，學校無法成立以「國家」或「族群」為交流目的的學生會或社團。")
                    paragraph("因此我們成立新加坡台灣學生總會，主要目的是串聯在新加坡的異鄉遊子對家鄉的情感，舉辦各類活動增進台灣學生間的交流、凝聚台灣精神，同時在當地推廣台灣的美食與文化，並歡迎來自世界各地的學生。")
                    paragraph("Logo 以世學聯兩大主色為起點：象徵美麗海島的海洋藍台灣黑熊，承載著遊子對土地的連結；深紅的獅頭則代表新加坡，也象徵台灣留學生在海外奮鬥的精神。")
                }

                section("總會目標") {
                    GroupedCard {
                        ForEach(Array(Self.goals.enumerated()), id: \.offset) { index, goal in
                            if index > 0 { RowSeparator(inset: 0) }
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Theme.Palette.brand)
                                    .monospacedDigit()
                                Text(goal)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, Theme.Metrics.gutter)
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, -Theme.Metrics.gutter)
                }

                section("世界台灣學生會聯合總會") {
                    paragraph("STSA 隸屬世學聯（WWTSA）旗下支分會。世學聯為世界性學生組織，服務全球海外台灣留學生與各地 TSA，並為台灣社會貢獻諸多公益。以促進良性競爭、人才回流為願景，增加與世界接軌的機會。")
                    Link(destination: URL(string: "https://www.wwtsa.org.tw/")!) {
                        HStack(spacing: 4) {
                            Text("世學聯官網")
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 4)
                }

                section("大事記") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(Self.milestones.enumerated()), id: \.offset) { index, milestone in
                            milestoneRow(milestone, isFirst: index == 0)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("關於總會")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pieces

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(.stsaLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("新加坡台灣學生總會")
                    .font(.title2.weight(.bold))
                Text("Singapore Taiwan Student Association")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.brand)
                .padding(.top, 24)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A dot-and-rule timeline; the rule is dropped on the first row so it does
    /// not appear to continue above the earliest entry.
    private func milestoneRow(_ milestone: Milestone, isFirst: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary))
                    .frame(width: 1, height: 10)
                Circle()
                    .fill(Theme.Palette.brand)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.date)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(milestone.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = milestone.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Content

    struct Milestone {
        let date: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey?
    }

    private static let goals: [LocalizedStringKey] = [
        "創建並維持新加坡的台灣留學生聯絡網，促進交流、串聯家鄉情感、凝聚台灣精神。",
        "幫助準留學生適應新加坡的生活環境與文化差異。",
        "推廣台灣文化與知識，讓外國學生更加了解台灣。",
    ]

    private static let milestones: [Milestone] = [
        .init(date: "2019", title: "新加坡台灣學生總會成立", detail: "STSA 於新加坡正式成立"),
        .init(date: "2022 / 12", title: "放眼東南亞", detail: "與世學聯、馬來西亞、泰國學生會共同主辦"),
        .init(date: "2023 / 03", title: "Bloomberg 企業參訪", detail: nil),
        .init(date: "2023 / 12", title: "職涯分享會", detail: "駐新加坡台北代表處"),
        .init(date: "2024 / 01", title: "聯電 Office 參訪", detail: nil),
        .init(date: "2024 / 04·06·07", title: "職涯分享會", detail: "青商會、國泰銀行、DBS"),
        .init(date: "2025 / 04", title: "UOB 企業參訪", detail: nil),
        .init(date: "2025 / 09", title: "新生迎新", detail: nil),
        .init(date: "2026 / 03", title: "WBC Watch Party", detail: nil),
        .init(date: "2026 / 03", title: "HSBC Financial Literacy 講座", detail: nil),
    ]
}

#Preview {
    NavigationStack { AboutView() }
}
