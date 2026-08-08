import SwiftUI

struct DealsView: View {
    private let deals = Deal.samples

    private var active: [Deal] { deals.filter { !$0.hasExpired() } }
    private var expired: [Deal] { deals.filter { $0.hasExpired() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    section("合作商家", deals: active,
                            footnote: "出示電子會員卡即可享有以下合作品牌的專屬禮遇。")

                    if !expired.isEmpty {
                        section("已過期", deals: expired, footnote: nil)
                    }
                }
                .padding(.top, 6)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("會員優惠")
        }
    }

    @ViewBuilder
    private func section(_ title: String, deals: [Deal], footnote: String?) -> some View {
        if !deals.isEmpty {
            VStack(spacing: 0) {
                GroupedCardHeader(title)
                GroupedCard {
                    ForEach(Array(deals.enumerated()), id: \.element.id) { index, deal in
                        if index > 0 { RowSeparator(inset: 0) }
                        NavigationLink {
                            DealDetailView(deal: deal)
                        } label: {
                            DealRow(deal: deal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DealRow: View {
    let deal: Deal

    var body: some View {
        HStack(spacing: 12) {
            // Always on white: the logos are dark-on-transparent and would
            // disappear against the grouped background in Dark Mode.
            Image(deal.logo)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 72, height: 44)
                .background(.white)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(deal.brand)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(deal.headline ?? deal.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let expiry = deal.expiryLabel {
                    Text(expiry)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureChevron()
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .opacity(deal.hasExpired() ? 0.5 : 1)
    }
}

#Preview {
    DealsView()
}
