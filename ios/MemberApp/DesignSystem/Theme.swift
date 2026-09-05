import SwiftUI

/// Design tokens lifted from the STSA prototype (`STSA App.dc.html`).
///
/// Deliberately thin: the prototype's greys are literal transcriptions of Apple's
/// semantic colours (`rgba(60,60,67,.6)` is `.secondaryLabel`, `#f2f2f7` is
/// `systemGroupedBackground`, `rgba(118,118,128,.12)` is `tertiarySystemFill`).
/// Using the semantic colours instead of the hex values is what makes the app
/// adapt to Dark Mode and Increase Contrast for free — only the brand rose is ours.
enum Theme {}

// MARK: - Colour

extension Theme {
    enum Palette {
        /// STSA brand rose — the app's tint.
        ///
        /// `AccentColor.colorset` holds it in **display-P3** (`#C68578` read as
        /// hex), which is `#D18175` in sRGB. That sRGB value is what the Android
        /// scheme is seeded with; the prototype's `#EC3013` is a different, more
        /// saturated red that the shipped asset never used.
        static let brand = Color("AccentColor")

        /// Near-black surface behind the member card and deal marks. `#1C1C1E`
        static let inkCard = Color(red: 0.110, green: 0.110, blue: 0.118)
    }
}

// MARK: - Shape

extension Theme {
    enum Radius {
        /// Primary buttons and hero cards.
        static let button: CGFloat = 14
        /// Inset grouped list containers.
        static let list: CGFloat = 10
        /// Content cards inside a scroll view.
        static let card: CGFloat = 12
        /// The member card itself.
        static let memberCard: CGFloat = 16
    }

    enum Metrics {
        /// Height of the full-width primary CTA.
        static let ctaHeight: CGFloat = 50
        /// Horizontal inset for grouped list containers.
        static let gutter: CGFloat = 16

        /// Extra space below the last element of a scrolling detail screen.
        ///
        /// A tab's bottom safe area accounts for the tab bar but *not* for
        /// `tabViewBottomAccessory`, and there is no public API for its height.
        /// Anything pinned with `safeAreaInset` ends up underneath the 會員卡
        /// pill, so detail screens scroll their content clear of it instead.
        static let accessoryClearance: CGFloat = 72
    }
}

// MARK: - Primary call to action

/// The full-width brand button that anchors Welcome, Sign Up, Deal Detail, etc.
struct BrandButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.ctaHeight)
            .foregroundStyle(prominent ? .white : Theme.Palette.brand)
            .background(prominent ? AnyShapeStyle(Theme.Palette.brand) : AnyShapeStyle(.clear))
            .clipShape(.rect(cornerRadius: Theme.Radius.button))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
    static var brandPlain: BrandButtonStyle { BrandButtonStyle(prominent: false) }
}
