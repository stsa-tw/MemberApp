import SwiftUI

/// The hand-off from the system's launch screen to the app.
///
/// iOS will not animate a launch screen. `UILaunchScreen` is drawn by the system
/// before any of our code exists, so it is a still frame by construction, and the
/// only part of a launch that anyone can animate is the moment it gives way. This
/// is that moment: the mark that has been on screen since the tap draws a breath
/// and lifts, and the app blooms out from behind it.
///
/// **The static screen carries the mark, and that is the whole design.** The
/// tempting alternative is a blank launch screen with the mark painting itself on
/// in SwiftUI — it demos beautifully. It was built that way first, and Release
/// builds recorded off the simulator settled the question: the system's launch
/// screen was up for anywhere between a third of a second and better than two,
/// depending on nothing the member controls, and under that design every
/// millisecond of it was a blank white rectangle. An animation nobody waited
/// around to see was worth less than the dead second it cost. This way the mark
/// is there instantly and stays for the whole cold start, however long that
/// turns out to be on the day.
///
/// The seam is closed by construction rather than by tuning. `LaunchMark` is a
/// square, mostly transparent canvas with the mark centred at a fixed fraction of
/// its width, and both halves of the hand-off draw *that same asset*, aspect-fit
/// to the screen: UIKit for the static screen, this view for the animated one. So
/// there is no pair of numbers to keep in sync, and the mark cannot land half a
/// point out on some future device whose width nobody here thought about.
///
/// The asset carries a dark variant, and for the reason `Theme.Palette.brand`
/// carries one. The mark is drawn in the same deep red and navy as the brand
/// colour, which on the dark scheme's near-black is a mark you have to look for —
/// on a screen nobody looks at for more than a second. The dark variant keeps the
/// hues and lifts the brightness, so it is the same mark rather than a second one.
///
/// One seam this cannot close: the static screen is drawn by the system, which
/// follows the *system* appearance, while everything below `preferredColorScheme`
/// follows the member's 外觀 setting. A member who has pinned the app to 深色 on a
/// light phone gets one appearance change as the app takes over. The alternative
/// is to stop honouring their setting for the first second of every launch, which
/// is worse, and it is the same single change the app made before any of this
/// existed.
///
/// **This waits for nothing, on purpose.** `AuthManager.restore()` is synchronous
/// in `init`, so `RootView` already knows whether it is showing the tabs or
/// Welcome by the time the first frame is composed, and the app is live and
/// running its `task`s underneath this the entire time it is up. There is no work
/// here to cover. Gating the dismissal on `refreshIfNeeded()` would look
/// thriftier and would in fact be worse: a member on hotel wifi would be held
/// behind a logo for as long as authentik took to answer, only to be shown a
/// screen that had been ready before the animation started.
///
/// It is also not a home for `LiveCheckmark`'s sweeping ring. That ring means one
/// specific thing at a door — this verdict is live, not a screenshot of one — and
/// spending it on a splash would teach members to read it as decoration.
struct LaunchScreen: View {
    /// Called when the mark is ready to leave. The caller animates the removal,
    /// so that the mark going and the app arriving are one gesture rather than
    /// two that have to be timed against each other.
    let onHandOff: () -> Void

    /// Seconds from the first frame to the hand-off.
    private let dwell: TimeInterval = 0.44

    /// Reduce Motion keeps the hand-off and drops the travel: no anticipation,
    /// no scale, and a shorter hold, because a cross-fade has nothing to watch.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the inhale. The mark starts at exactly the size the static screen
    /// left it — anything else would be a jump on the first frame.
    @State private var isGathering = false

    var body: some View {
        ZStack {
            Color(.systemBackground)

            // Aspect-fit inside a stack that fills the screen, which is what
            // UIKit does with the same asset on the static screen. The canvas is
            // square and the screen is taller, so both fit it to the width and
            // centre it, and the mark lands in the same place twice.
            Image(.launchMark)
                .resizable()
                .scaledToFit()
                .scaleEffect(isGathering && !reduceMotion ? 0.965 : 1)
        }
        .ignoresSafeArea()
        // The mark is the app's name, not something the member is missing.
        .accessibilityHidden(true)
        // Taps are held off by the app underneath, not by this. A view being
        // removed by a transition goes on hit-testing until the removal
        // finishes, so blocking here would eat the first tap of anyone who
        // reaches for a tab as the mark is already on its way out.
        .allowsHitTesting(false)
        .task { await run() }
    }

    private func run() async {
        // Anticipation: the mark gathers a little before it goes, so the lift
        // reads as a decision rather than as the screen giving out. Skipped
        // under Reduce Motion, where it would be the only movement left and
        // would draw more attention than the hand-off it is meant to set up.
        if !reduceMotion {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                isGathering = true
            }
        }

        // `try?` rather than `try`: a cancelled sleep returns immediately, which
        // hands off early. That is the right way for this to fail — the app
        // underneath is already usable, and the alternative is a mark that never
        // leaves.
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.30 : dwell))
        onHandOff()
    }
}

extension LaunchScreen {
    /// False for App Store capture runs.
    ///
    /// `simctl launch` photographs the app as soon as it is up, and a run that
    /// opens behind a mark photographs the mark — see `ScreenshotFixtures` for
    /// why those runs are driven from the launch environment rather than by
    /// tapping through the UI.
    static var isEnabled: Bool {
#if DEBUG
        !ScreenshotFixtures.isEnabled
#else
        true
#endif
    }
}

// MARK: - Mounting

extension View {
    /// Holds the launch mark over the app until the app is on screen, then hands
    /// off. Apply to the root view.
    func launchScreen() -> some View {
        modifier(LaunchHandOff())
    }
}

private struct LaunchHandOff: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLaunching = LaunchScreen.isEnabled

    /// Seconds the mark takes to lift and the app to arrive. One number for both
    /// halves, because they are one movement.
    private var lift: TimeInterval { reduceMotion ? 0.30 : 0.42 }

    func body(content: Content) -> some View {
        content
            // The app rises into place as the mark leaves, rather than being cut
            // to underneath it. The scale is small on purpose: this is the app
            // arriving, not a zoom.
            .scaleEffect(isLaunching && !reduceMotion ? 0.965 : 1)
            .opacity(isLaunching ? 0 : 1)
            // Nothing here is visible yet, and a tab bar that cannot be seen
            // should not be able to be pressed. This lifts at the hand-off
            // rather than at the end of it, so a tap during the last fraction of
            // a second lands on the app that is arriving instead of vanishing.
            .allowsHitTesting(!isLaunching)
            // Attached after the two modifiers above so the mark is outside them
            // — it has its own exit, and must not fade on the app's curve.
            .overlay {
                if isLaunching {
                    LaunchScreen {
                        withAnimation(.easeInOut(duration: lift)) { isLaunching = false }
                    }
                    // Scaling the whole splash is safe and is the point: the
                    // background under the mark is a flat colour, so growing it
                    // shows no edge, while the mark grows away from the eye.
                    .transition(
                        reduceMotion
                            ? AnyTransition.opacity
                            : .scale(scale: 1.12).combined(with: .opacity)
                    )
                }
            }
    }
}

#Preview {
    // Stands in for RootView, so the hand-off has something to uncover.
    VStack(spacing: 12) {
        Text("首頁").font(.largeTitle.weight(.semibold))
        Text("活動 · 優惠 · 職缺").foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
    .launchScreen()
}
