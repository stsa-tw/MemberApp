import SwiftUI

struct DealDetailView: View {
    let deal: Deal

    @Environment(Session.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                summaryCard
                    .padding(.horizontal, Theme.Metrics.gutter)

                if let code = deal.code {
                    codeCard(code)
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .padding(.top, 14)
                }

                if !deal.terms.isEmpty {
                    GroupedCardHeader("使用條件")
                        .padding(.top, 20)
                    GroupedCard {
                        ForEach(Array(deal.terms.enumerated()), id: \.offset) { index, term in
                            if index > 0 { RowSeparator() }
                            Text(term)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Metrics.gutter)
                                .padding(.vertical, 11)
                        }
                    }
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        // The bottom safe area inside a tab does not account for the tab view's
        // accessory, so a pinned safeAreaInset lands underneath it. Hiding the
        // bar on push fixes that and keeps the primary action uncontested.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button("出示會員卡") { session.isShowingMemberCard = true }
                    .buttonStyle(.brand)
                Text("合作商家需確認 STSA 會員身分。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(deal.logo)
                .resizable()
                .scaledToFit()
                .padding(12)
                .frame(maxWidth: 220, maxHeight: 76, alignment: .leading)
                .background(.white)
                .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(deal.brand)
                    .font(.title2.weight(.bold))
                if let english = deal.brandEnglish {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let headline = deal.headline {
                Text(headline)
                    .font(.title3.weight(.bold))
            }
            Text(deal.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private func codeCard(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("折扣碼")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(deal.hasExpired() ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.Palette.brand))

            Text(code)
                .font(.title.weight(.bold).monospaced())
                .textSelection(.enabled)
                .strikethrough(deal.hasExpired())

            if deal.hasExpired(), let expiry = deal.expiryLabel {
                // Showing a dead code as if it works wastes someone's time at a
                // counter. Say so rather than rendering it normally.
                Text("此折扣碼已於 \(expiry.dropFirst()) 到期。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let expiry = deal.expiryLabel {
                Text("有效期限 \(expiry.dropFirst())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(deal.hasExpired() ? AnyShapeStyle(.tertiary)
                                                   : AnyShapeStyle(Theme.Palette.brand.opacity(0.5)))
        }
    }
}

#Preview {
    NavigationStack {
        DealDetailView(deal: Deal.samples[0]).environment(Session())
    }
}
