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
        /// STSA brand red — the app's tint. `#EC3013`
        static let brand = Color("AccentColor")
        /// Pressed / hover variant used on the marketing surfaces. `#AE1800`
        static let brandDeep = Color(red: 0.682, green: 0.094, blue: 0.000)
        /// Badge foreground on a 10% brand wash. `#C0290F`
        static let brandInk = Color(red: 0.753, green: 0.161, blue: 0.059)

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
    }
}

// MARK: - Primary call to action

/// The full-width red button that anchors Welcome, Sign Up, Deal Detail, etc.
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
