import SwiftUI

/// A verdict mark that arrives like a payment app's and then never holds still,
/// so a photograph of this screen cannot pass for the screen itself.
///
/// The scanner's answer is the part worth faking. A member turned away at one
/// door only needs a picture of somebody else's 有效會員碼 to try the next
/// staffer, who did not watch the scan happen — and a screenshot of a static
/// tick is a perfect forgery of a static tick. So the mark sweeps: a still frame
/// is always caught mid-rotation, at an angle the live view is only ever passing
/// through.
///
/// That is also why the entrance is only an entrance. The obvious thing to reach
/// for here is one of the ready-made success animations — the ring snaps closed,
/// the tick springs in, everything settles. Settling is exactly the failure this
/// exists to close: a second after it lands, the screen is a still image again
/// and the forgery works. So the three beats run
///
///   1. **draw-in** — the ring closes and the mark pops (the borrowed part),
///   2. **chase** — the ring's tail catches up, leaving a gap,
///   3. **sweep** — that gap orbits, forever, with a breath under the mark.
///
/// Beats 1 and 2 are the celebration; beat 3 is the security. Cutting beat 3 to
/// make it feel more like the reference would quietly undo the whole point.
///
/// Phase comes from the clock via `TimelineView(.animation)` rather than from
/// view state, so there is no rest position to photograph and nothing to restart
/// when the view redraws.
///
/// This is a liveness cue, not a capture block — iOS cannot prevent a
/// screenshot. What it buys is that a staffer looking at the screen can tell a
/// live verdict from a picture of one, which only works if the motion is big
/// enough to notice.
struct LiveCheckmark: View {
    /// SF Symbol for the verdict — the caller keeps ownership of which mark is
    /// right, so `checkmark.seal.fill` and `checkmark.circle.fill` both work.
    let symbol: String
    let tint: Color
    /// Point size of the symbol. The ring scales off this.
    var size: CGFloat

    /// Seconds the ring takes to close, then to pull its tail in behind it.
    private let drawIn: TimeInterval = 0.50
    private let chase: TimeInterval = 0.40
    /// Seconds per orbit once it is sweeping.
    private let period: TimeInterval = 2.4
    /// How much of the circle stays unpainted, so there is something to watch go
    /// round. 0.22 is wide enough to read at the 34pt the check-in banner uses.
    private let gap: CGFloat = 0.78

    /// Reduce Motion cannot simply switch this off: the animation *is* the
    /// check. It loses the overshoot and the breath and orbits well under half
    /// speed — still plainly alive, without the snap that provokes symptoms.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed at first draw so the entrance plays once and the sweep that follows
    /// stays continuous across redraws.
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let age = context.date.timeIntervalSince(start)

            ZStack {
                // The track the sweep runs on, drawn first so the arc stays at
                // full strength where the two overlap. It fades in with the
                // ring rather than sitting there waiting for it.
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: strokeWidth)
                    .frame(width: diameter, height: diameter)
                    .opacity(min(1, age / drawIn))

                arc(age: age)
                mark(age: age)
            }
            // Decoration; the banner's own text carries the verdict.
            .accessibilityHidden(true)
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Beats

    private func arc(age: TimeInterval) -> some View {
        let from: CGFloat
        let to: CGFloat
        let turn: Double

        if age < drawIn {
            // Beat 1: the head runs round from twelve o'clock.
            from = 0
            to = CGFloat(easeOut(age / drawIn))
            turn = 0
        } else if age < drawIn + chase {
            // Beat 2: the tail follows it in, opening the gap.
            from = gap * CGFloat(easeInOut((age - drawIn) / chase))
            to = 1
            turn = 0
        } else {
            // Beat 3: that gap orbits. Starting the rotation at zero here is
            // what keeps the hand-off from beat 2 invisible — the arc is in
            // exactly the place beat 2 left it.
            from = gap
            to = 1
            turn = (age - drawIn - chase) / orbitPeriod
        }

        return Circle()
            .trim(from: from, to: to)
            .stroke(
                tint.opacity(0.85),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90 + turn * 360))
            .frame(width: diameter, height: diameter)
    }

    private func mark(age: TimeInterval) -> some View {
        let scale: Double
        if reduceMotion {
            scale = 1
        } else if age < drawIn {
            // Lands a little ahead of the ring, so the tick reads as the point
            // and the ring as the frame around it.
            scale = backOut(min(1, age / drawIn * 1.25))
        } else {
            scale = 1 + 0.025 * sin((age - drawIn) / period * 2 * .pi)
        }

        return Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(tint)
            .scaleEffect(scale)
    }

    // MARK: - Geometry and easing

    private var strokeWidth: CGFloat { max(2, size * 0.055) }
    private var diameter: CGFloat { size * 1.5 }
    private var orbitPeriod: TimeInterval { reduceMotion ? period * 2.5 : period }

    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Overshoots past 1 and comes back — the pop the reference animations open
    /// with.
    private func backOut(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

#Preview("Valid") {
    LiveCheckmark(symbol: "checkmark.circle.fill", tint: .green, size: 72)
}

#Preview("Already checked in") {
    LiveCheckmark(symbol: "checkmark.seal.fill", tint: .orange, size: 34)
}
