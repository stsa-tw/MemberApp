import SwiftUI
import UIKit

/// The ticket, as a place rather than an action.
///
/// The event page used to offer 加入 Apple Wallet as its one loud button, which
/// put a *filing* action where the member's actual need is — the code at the
/// door, now, without a detour through Wallet or Safari. So the event page leads
/// here instead, and this screen is the ticket: the code that gets scanned, the
/// facts printed around it, and the pass for keeping it, in that order.
///
/// Wallet is still the better long-term home for a ticket — it survives losing
/// the Indico session and it is where a phone's owner looks for one — so the
/// button is here, under the code, where it reads as "keep this" rather than as
/// the only way to see it.
struct EventTicketView: View {
    let event: IndicoEvent

    /// Indico's ticket PDF, which is both the code's source and the last resort
    /// if reading it back fails.
    let ticket: URL

    @Environment(\.openURL) private var openURL
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(TicketStore.self) private var tickets

    @State private var document = TicketDocument()
    @State private var isAddingPass = false
    @State private var passError: String?

    /// Restored on the way out, so raising the screen for a scanner does not
    /// leave the phone blinding for the rest of the evening.
    @State private var previousBrightness: CGFloat?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                stub
                Button("在 Indico 開啟") { openURL(ticket) }
                    .buttonStyle(.brandPlain)
                footnote
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, Theme.Metrics.accessoryClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("票券")
        .navigationBarTitleDisplayMode(.inline)
        // Brightened before the ticket has even arrived: someone who opened this
        // is already holding the phone out, and a screen that brightens a beat
        // after the code appears is brightening after the scanner gave up.
        .task {
            raiseBrightness()
            await document.load(from: ticket, using: indico)
        }
        .onDisappear(perform: restoreBrightness)
    }

    // MARK: - The ticket

    /// Notched where a ticket tears, which is the one place in the app allowed
    /// to be shaped like the thing it is.
    private var stub: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.kicker)
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.brand)
                Text(event.title.withoutEmoji)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 16)

            Divider()

            // Wallet sits with the code rather than under the card, because it
            // is the same code — filing it away is a thing you do to *this*,
            // and a button floating below the ticket read as a separate offer.
            VStack(spacing: 18) {
                code
                wallet
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

            Divider()

            FactRow("時間", value: event.schedule)
            if let place = event.place {
                RowSeparator()
                FactRow("地點", value: place)
            }
            if let holder = auth.profile?.name {
                RowSeparator()
                FactRow("持票人", value: holder)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(TicketStub())
    }

    @ViewBuilder
    private var code: some View {
        switch document.state {
        case .loading:
            ProgressView()
                .frame(height: 240)

        case .ready(.code(let payload)):
            if let image = QRCode.image(for: payload, size: 240) {
                image
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    // Always on white, in both appearances: scanners expect dark
                    // modules on a light field, and the generator's output would
                    // otherwise sit on a dark card in Dark Mode.
                    .padding(12)
                    .background(.white, in: .rect(cornerRadius: 10))
                    .accessibilityLabel("報到 QR code")
            }

        case .ready(.page(let page)):
            // No code could be read back, so Indico's own rendering stands in.
            // It carries the same QR — it is where the QR was looked for — and
            // it scans; it is only smaller and softer than one the app drew.
            Image(uiImage: page)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .background(.white)
                .accessibilityLabel("票券")

        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重試") {
                    Task { await document.load(from: ticket, using: indico) }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .frame(height: 240)
        }
    }

    // MARK: - Wallet

    /// Only where there is a pass to add and a device that can hold one. Absent
    /// otherwise rather than disabled: a member cannot make either true, so a
    /// greyed button would only be a question they cannot answer.
    @ViewBuilder
    private var wallet: some View {
        if WalletPass.isAvailable, let pass = tickets.walletURL(for: event.id) {
            VStack(spacing: 8) {
                AddPassButton { Task { await addToWallet(pass) } }
                    .opacity(isAddingPass ? 0.5 : 1)
                    .allowsHitTesting(!isAddingPass)

                if let passError {
                    Text(passError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Metrics.gutter)
                }
            }
        }
    }

    private func addToWallet(_ url: URL) async {
        isAddingPass = true
        passError = nil
        defer { isAddingPass = false }

        do {
            try await WalletPass.add(from: url, using: indico)
        } catch {
            // Kept on this screen rather than reported to `TicketStore`, which
            // would put the event page behind into a failed state over something
            // that did not touch the ticket. Not an alert either: filing a copy
            // is not worth interrupting someone standing at a door.
            passError = error.localizedDescription
        }
    }

    private var footnote: some View {
        Text("在入場時出示此 QR code。畫面會自動調亮以便掃描。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
    }

    // MARK: - Screen brightness

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    private func raiseBrightness() {
        guard let screen, previousBrightness == nil else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        guard let screen, let previousBrightness else { return }
        screen.brightness = previousBrightness
        self.previousBrightness = nil
    }
}
