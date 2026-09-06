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
///
/// Inset to the same gutter as the card beneath it and the large navigation
/// title above it, so a screen has one left edge rather than three. Apple's own
/// inset-grouped lists indent the header past the card to line it up with the
/// row *text* instead; that reads as a zigzag under a large title, which is why
/// this does not copy it.
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
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, 7)
    }
}

/// A `GroupedCardHeader` that opens and closes what sits under it.
///
/// The whole row is the target, not just the chevron: a plain-styled button only
/// hit-tests its drawn content, so the `Spacer` between title and chevron would
/// otherwise swallow taps aimed at the obvious place.
struct DisclosureCardHeader: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
        } label: {
            HStack {
                GroupedCardHeader(title)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.trailing, Theme.Metrics.gutter)
                    .padding(.bottom, 7)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

/// A label on the left, its value on the right — the shape of every fact the app
/// states about something: an event's time and place, a ticket's holder.
///
/// `.top` alignment rather than centred, because the value is the half that
/// wraps: an address runs to three lines and its label should stay level with
/// the first of them.
struct FactRow: View {
    let label: LocalizedStringKey
    let value: String

    init(_ label: LocalizedStringKey, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 11)
    }
}
