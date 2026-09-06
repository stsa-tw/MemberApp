import SwiftUI

/// A partner's mark, or their name until they send one.
///
/// Both deal screens draw the logo on a plate that is white in either
/// appearance, because the artwork is dark-on-transparent and would vanish
/// against the grouped background in Dark Mode. The stand-in keeps that plate
/// and fills it with the brand instead, so an offer whose artwork has not
/// arrived reads as unfinished rather than as broken — which is what it is.
struct DealMark: View {
    let deal: Deal

    /// Inset from the plate's edge. The two screens draw the plate at different
    /// sizes, so they say how much room the mark gets inside it.
    var inset: CGFloat
    var font: Font

    var body: some View {
        if let logo = deal.logo {
            Image(logo)
                .resizable()
                .scaledToFit()
                .padding(inset)
        } else {
            Text(deal.brand)
                .font(font)
                .foregroundStyle(Theme.Palette.brand)
                .multilineTextAlignment(.center)
                // A long brand set on the row's 72×44 plate would otherwise
                // truncate to something that names no one.
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .padding(inset)
        }
    }
}
