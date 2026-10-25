import SwiftUI

extension Theme.Metrics {
    /// The widest a column of content gets before it stops growing and centres.
    ///
    /// Every screen here was drawn for a phone held upright. On a wider one — an
    /// iPhone Duo open, a Pro Max on its side — they stretched to the edges, and
    /// a card, a button or a line of text twice its intended width reads as a
    /// layout that went wrong rather than one with room to breathe.
    static let readableWidth: CGFloat = 600
}

extension View {
    /// Keeps a scroll view's content within `Theme.Metrics.readableWidth`,
    /// centred, on screens wider than that.
    ///
    /// Done with content margins rather than a frame on the content, so the
    /// background and the scroll indicator still run to the screen's edges and
    /// the whole width still scrolls.
    func readableWidth() -> some View {
        modifier(ReadableWidth())
    }
}

private struct ReadableWidth: ViewModifier {
    /// Nil until the screen is wide enough to need it. `contentMargins` takes
    /// nil as "the default", which matters for a `List`: its inset-grouped rows
    /// carry a margin of their own that an explicit zero would take away.
    @State private var margin: CGFloat?

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                let spare = (width - Theme.Metrics.readableWidth) / 2
                margin = spare > Theme.Metrics.gutter ? spare : nil
            }
    }
}
