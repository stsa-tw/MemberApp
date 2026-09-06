import PassKit
import SwiftUI
import UIKit

/// Puts an Indico ticket into Apple Wallet.
///
/// The pass is signed by Indico, which holds the Pass Type ID certificate — the
/// app neither signs nor could sign one, since a private key shipped in a binary
/// is a private key given away. All that happens here is fetching the `.pkpass`
/// and handing it to `PKAddPassesViewController`, which is the only supported way
/// to add one.
///
/// `TicketStore` deliberately keeps no ticket in memory, because a ticket QR *is*
/// the credential. This is the one place that has to hold the bytes, and it holds
/// them for exactly as long as the sheet needs: nothing is written to disk, and
/// the pass goes to Wallet, which is where a credential belongs.
enum WalletPass {
    enum AddError: LocalizedError {
        case unavailable
        case server(status: Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .unavailable: "這台裝置無法加入 Apple Wallet。"
            case .server(let status): "Indico 回應 HTTP \(status)。"
            case .malformed: "票券格式無法讀取。"
            }
        }
    }

    /// Whether Wallet can take a pass at all. False on a device with passes
    /// restricted, where offering the button would be a dead end.
    static var isAvailable: Bool {
        PKAddPassesViewController.canAddPasses()
    }

    /// Fetches the pass and presents Wallet's own add sheet.
    @MainActor
    static func add(from url: URL, using indico: IndicoAuthManager) async throws {
        guard isAvailable else { throw AddError.unavailable }

        let request = try indico.authorizedRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AddError.server(status: http.statusCode)
        }

        // PKPass rejects anything that is not a signed pass, which is also the
        // check that a 200 carrying Indico's login page does not reach Wallet.
        let pass: PKPass
        do {
            pass = try PKPass(data: data)
        } catch {
            throw AddError.malformed
        }

        guard let controller = PKAddPassesViewController(pass: pass),
              let presenter = Self.presenter()
        else { throw AddError.unavailable }

        presenter.present(controller, animated: true)
    }

    /// The topmost view controller, which is what a modal has to be presented
    /// from. SwiftUI offers no first-party route to `PKAddPassesViewController`.
    private static func presenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

/// Apple's own control, because this is Apple's destination.
///
/// This was a hand-drawn slab for a while: brand rose, ticket notches, the app's
/// corner radius, 加入 Apple Wallet set in the app's voice. The reasoning was
/// that `PKAddPassButton` brings its own metrics and refuses our radius, which is
/// true and turns out not to matter. What matters is that the black pill is a
/// *sign*, not a sentence — someone scanning this screen for "where does this go
/// in Wallet" recognises it without reading it, and recognises a rose slab as
/// nothing in particular and reads it to find out. Dressing another app's
/// front door in our paint did not make it ours; it made it unfamiliar.
///
/// So it is Apple's again, which is also what their identity guidelines ask for.
/// The ticket notches did not go to waste — `TicketStub` now cuts the ticket
/// itself on `EventTicketView`, which is the thing that is actually a ticket.
struct AddPassButton: UIViewRepresentable {
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(action) }

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: style)
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.fire),
                         for: .touchUpInside)
        // Sized by its own label. Stretched to the gutter it draws a capsule the
        // width of the screen, which is not a shape Wallet has ever used and
        // reads as the same homemade thing this replaced.
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) {
        // The closure captures view state that changes between renders, so the
        // coordinator is handed the current one rather than the first one.
        context.coordinator.action = action
        button.addPassButtonStyle = style
    }

    /// Black on a light page, outlined in Dark Mode. `PKAddPassButton` does not
    /// adapt on its own, and a black capsule on a near-black ground is a
    /// rectangle of nothing with a label floating in it.
    private var style: PKAddPassButtonStyle {
        colorScheme == .dark ? .blackOutline : .black
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(_ action: @escaping () -> Void) { self.action = action }

        @objc func fire() { action() }
    }
}

/// A rounded card bitten into on both sides, where a ticket is torn.
///
/// The notches are the whole idea, so they are cut at the vertical middle and
/// sized against the height rather than a fixed number — they stay in
/// proportion when the label wraps at larger text sizes.
struct TicketStub: Shape {
    var radius: CGFloat = Theme.Radius.card

    func path(in rect: CGRect) -> Path {
        let notch = min(rect.height / 5, 11)

        var path = Path(roundedRect: rect, cornerRadius: radius)
        for x in [rect.minX, rect.maxX] {
            path = path.subtracting(
                Path(ellipseIn: CGRect(x: x - notch,
                                       y: rect.midY - notch,
                                       width: notch * 2,
                                       height: notch * 2))
            )
        }
        return path
    }
}
