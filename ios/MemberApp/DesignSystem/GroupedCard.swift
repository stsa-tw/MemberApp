import SwiftUI

/// The white rounded container the prototype uses for every grouped list
/// (`background:#fff;border-radius:10px`), inset by the standard gutter.
///
/// Hand-rolled rather than `List` because Home mixes list rows with a hero
/// banner and a two-up grid, and a `ScrollView` keeps that in one scroll view.
struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.list))
        .padding(.horizontal, Theme.Metrics.gutter)
    }
}

/// Section label above a `GroupedCard` — uppercase, tracked, secondary.
struct GroupedCardHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 7)
    }
}

/// Hairline that starts inside the row, matching the prototype's inset rules.
struct RowSeparator: View {
    var inset: CGFloat = 16

    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
}

/// The grey chevron that marks a row as tappable.
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
