import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(IndicoAuthManager.self) private var indico
    @Environment(TicketStore.self) private var tickets
    @Environment(CheckinStore.self) private var checkin
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = settings

        List {
            Section("外觀") {
                Picker("主題", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if BiometricGate.isAvailable {
                Section {
                    Toggle("開啟會員卡需驗證", isOn: $settings.requireBiometricsForCard)
                } header: {
                    Text("安全性")
                } footer: {
                    Text("開啟後，出示會員卡前需通過 \(BiometricGate.biometryName)。會員卡是身分憑證，這可以避免手機在解鎖狀態下被他人取用。")
                }
            }

            Section {
                // iOS owns per-app language once the bundle ships more than one
                // localisation. A custom picker would need an app restart to take
                // effect and would fight the system setting, so this defers to it.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    LabeledContent("語言", value: currentLanguage)
                }
                .tint(.primary)
            } footer: {
                Text("跟隨 iOS 的語言設定。點一下前往「設定 → STSA」切換。")
            }

            Section("關於") {
                NavigationLink {
                    AboutView()
                } label: {
                    Text("關於總會")
                }
                LabeledContent("版本", value: Self.version)
                Link("STSA 官網", destination: URL(string: "https://stsa.tw")!)
                Link("活動系統", destination: URL(string: "https://event.stsa.tw")!)
            }

            Section {
                // The Indico link and any pass held in memory belong to
                // whoever was signed in, so they go with the session.
                Button("登出", role: .destructive) {
                    auth.logout()
                    indico.unlink()
                    tickets.clear()
                    checkin.clear()
                }
            } footer: {
                Text("登出只會清除這支手機上的憑證。因為登入與 Safari 共用工作階段，下次登入可能不需要重新輸入密碼。")
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The localisation actually in use, not the device language — they differ
    /// once someone overrides it in Settings → STSA.
    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hant"
        return Locale(identifier: code).localizedString(forIdentifier: code)?
            .capitalized(with: Locale(identifier: code)) ?? code
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppSettings())
            .environment(AuthManager())
    }
}
