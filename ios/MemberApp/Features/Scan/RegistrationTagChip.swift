import SwiftUI

/// One of Indico's registration tags, drawn the way the organiser set it.
///
/// The colour is the tag's whole point at a door: 幹部 pick them so a row can be
/// read at a glance across a desk, and a list of identical grey chips would
/// throw that away. So the tint is Indico's, and only the *text* is ours —
/// drawn in the label colour rather than in the tag's colour, because Semantic
/// UI's palette was chosen against a white page and half of it disappears
/// against a dark one.
struct RegistrationTagChip: View {
    let tag: RegistrationTag

    var body: some View {
        Text(verbatim: tag.title)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tag.tint.opacity(0.18), in: .capsule)
            .overlay(Capsule().stroke(tag.tint.opacity(0.4), lineWidth: 0.5))
    }
}

/// Every tag on a registration, wrapped onto as many lines as it takes.
///
/// Wrapping rather than truncating because a tag nobody can see is worse than
/// one more line: 素食 is the tag that decides what the desk hands somebody.
struct RegistrationTagChips: View {
    let tags: [RegistrationTag]
    /// Centred under a banner, leading in a list row — the chips line up with
    /// whatever they are labelling.
    var isCentred = false

    var body: some View {
        if !tags.isEmpty {
            TagFlow(spacing: 4, lineSpacing: 4, isCentred: isCentred) {
                ForEach(tags) { RegistrationTagChip(tag: $0) }
            }
        }
    }
}

extension RegistrationTag {
    /// Semantic UI's own hex values for the names Indico stores.
    ///
    /// Written out because the palette is Semantic UI's and nothing else in the
    /// app knows it — `Color.red` is not `#DB2828`, and a tag that reads as a
    /// different colour here than on Indico's page is a tag the organiser has to
    /// think about twice.
    ///
    /// `black` and `grey`, and anything Indico adds later, fall back to the
    /// label grey: it is the one colour guaranteed to stay visible in both
    /// appearances, which black is not.
    var tint: Color {
        switch color {
        case "red": Color(red: 0.859, green: 0.157, blue: 0.157)
        case "orange": Color(red: 0.949, green: 0.443, blue: 0.110)
        case "yellow": Color(red: 0.984, green: 0.741, blue: 0.031)
        case "olive": Color(red: 0.710, green: 0.800, blue: 0.094)
        case "green": Color(red: 0.129, green: 0.729, blue: 0.271)
        case "teal": Color(red: 0.000, green: 0.710, blue: 0.678)
        case "blue": Color(red: 0.129, green: 0.522, blue: 0.816)
        case "violet": Color(red: 0.392, green: 0.208, blue: 0.788)
        case "purple": Color(red: 0.639, green: 0.200, blue: 0.784)
        case "pink": Color(red: 0.878, green: 0.224, blue: 0.592)
        case "brown": Color(red: 0.647, green: 0.404, blue: 0.247)
        default: Color(.secondaryLabel)
        }
    }
}

/// A row of chips that starts a new line when it runs out of width.
///
/// Hand-rolled because there is no stock wrapping stack, and the alternatives
/// are worse: an `HStack` clips the tags nobody can afford to lose, and a
/// `ScrollView` puts a second scroll gesture inside a list row.
private struct TagFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var isCentred: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = rows(within: width, subviews: subviews)
        let lines: CGFloat = rows.reduce(0) { $0 + $1.height }
        let gaps = lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: lines + gaps)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(within: bounds.width, subviews: subviews) {
            // Each line is centred on its own, so two chips under a banner sit
            // in the middle rather than hugging the left edge of a full-width
            // layout that only one of them fills.
            let slack: CGFloat = bounds.width - width(of: row, subviews: subviews)
            var x = bounds.minX + (isCentred ? slack / 2 : 0)
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func width(of row: Row, subviews: Subviews) -> CGFloat {
        let chips: CGFloat = row.indices.reduce(0) {
            $0 + subviews[$1].sizeThatFits(.unspecified).width
        }
        return chips + spacing * CGFloat(max(0, row.indices.count - 1))
    }

    private func rows(within width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            // The first chip on a line is placed however wide it is: wrapping it
            // onto a line of its own would leave an empty one above it.
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
