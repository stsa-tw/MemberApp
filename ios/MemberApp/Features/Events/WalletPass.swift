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
