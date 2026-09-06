import SwiftUI

/// Design tokens lifted from the STSA prototype (`STSA App.dc.html`).
///
/// Deliberately thin: the prototype's greys are literal transcriptions of Apple's
/// semantic colours (`rgba(60,60,67,.6)` is `.secondaryLabel`, `#f2f2f7` is
/// `systemGroupedBackground`, `rgba(118,118,128,.12)` is `tertiarySystemFill`).
/// Using the semantic colours instead of the hex values is what makes the app
/// adapt to Dark Mode and Increase Contrast for free — only the brand red is ours.
enum Theme {}

// MARK: - Colour

extension Theme {
    enum Palette {
        /// STSA brand red — the app's tint.
        ///
        /// `#8E2622`, the red the Indico ticket prints its labels in, so a member
        /// looking at the pass in Wallet and at the app is looking at one colour.
        /// It replaces the rose the prototype shipped (`#D18175`), which read as
        /// a tint of this rather than a colour of its own.
        ///
        /// Stored in **sRGB**, deliberately: the value is sampled from a rendered
        /// ticket, and sRGB is the space it was sampled in. The rose before it was
        /// held in display-P3, which meant the asset and the Android seed were two
        /// different numbers for one colour — now they are the same number.
        ///
        /// Dark mode gets `#E2635A`: the same hue, lifted. `#8E2622` reads 8.6:1
        /// against white and 2:1 against the dark scheme's near-black — a colour
        /// that works in one appearance and vanishes in the other — where the
        /// lifted one clears 4.9:1 and still reads as the same red.
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
