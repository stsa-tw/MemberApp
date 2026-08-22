import SwiftUI
import UIKit

struct MemberCardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(MembershipCodeStore.self) private var codes
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var previousBrightness: CGFloat?
    @State private var isUnlocked = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isUnlocked {
                        card
                        footnote
                    } else {
                        lockedState
                    }
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.top, 6)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("會員卡")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await unlock() }
        .onDisappear {
            codes.stop()
            restoreBrightness()
        }
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Lock

    private var lockedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("需要驗證才能出示會員卡")
                .font(.headline)
            Button("使用 \(BiometricGate.biometryName) 解鎖") {
                Task { await unlock() }
            }
            .buttonStyle(.brandPlain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Authenticates and mints the code *at the same time*.
    ///
    /// These used to run in sequence, so the network round-trip started only
    /// once Face ID had succeeded — a wait right at the moment the member is
    /// holding the phone up to a scanner. Minting alongside the prompt is safe
    /// because the code is only ever drawn behind `isUnlocked`; a failed gate
    /// throws the code away instead of showing it.
    private func unlock() async {
        let prefetch = Task { await codes.prefetch(using: auth) }
        let unlocked = await authenticate()

        isUnlocked = unlocked
        if unlocked {
            codes.start(using: auth)
            raiseBrightness()
        } else {
            await prefetch.value
            codes.clear()
        }
    }

    private func authenticate() async -> Bool {
        guard settings.requireBiometricsForCard else { return true }
        return await BiometricGate.authenticate(reason: String(localized: "出示 STSA 電子會員卡"))
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "STSA MEMBER")
                        .font(.caption.weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(Theme.Palette.brand)
                        .padding(.bottom, 6)

                    Text(auth.profile?.name ?? "—")
                        .font(.title.weight(.bold))

                    if let subtitle = auth.profile?.nickname ?? auth.profile?.preferredUsername {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                }

                Spacer(minLength: 8)

                Image(.stsaLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
            }
            .padding(.bottom, 18)

            Divider()

            qrPanel
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            Divider()

            HStack(alignment: .top) {
                if let school = auth.profile?.school {
                    field("School", school)
                }
                Spacer()
                if auth.profile?.isOfficer == true {
                    field("Role", String(localized: "幹部"))
                }
                Spacer()
                field("Code", codeFreshness)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Theme.Radius.memberCard))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 6)
    }

    @ViewBuilder
    private var qrPanel: some View {
        if let payload = codes.payload, let image = QRCode.image(for: payload, size: 152) {
            VStack(spacing: 10) {
                image
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 152, height: 152)
                    // Always on white, in both appearances: scanners expect
                    // dark modules on a light field, and the generator's output
                    // would otherwise sit on a dark card in Dark Mode.
                    .background(.white)
                    // An expired code still renders; dimming it says so without
                    // yanking the card away mid-scan.
                    .opacity(codes.hasExpired(at: now) ? 0.25 : 1)
                    .overlay {
                        if codes.hasExpired(at: now) {
                            Text("已過期")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("會員卡 QR code")

                if let message = codes.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        } else if let message = codes.errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重試") {
                    Task { await codes.refresh(using: auth) }
                }
                .font(.subheadline)
            }
            .frame(height: 152)
        } else {
            ProgressView()
                .frame(height: 152)
        }
    }

    private func field(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var codeFreshness: String {
        guard let expiresAt = codes.expiresAt else { return "—" }
        let seconds = Int(expiresAt.timeIntervalSince(now))
        guard seconds > 0 else { return String(localized: "已過期") }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var footnote: some View {
        Text("出示此卡以參加會員活動、領取新生包,或在合作商家享有折扣。畫面會自動調亮以便掃描。")
            .font(.footnote)
            .foregroundStyle(.secondary)
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
