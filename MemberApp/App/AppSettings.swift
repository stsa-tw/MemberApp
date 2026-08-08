import SwiftUI

/// User preferences, persisted in UserDefaults.
///
/// None of this is sensitive — it is display preference, not credentials — so
/// UserDefaults is the right home. Anything token-shaped belongs in `Keychain`.
@MainActor
@Observable
final class AppSettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: Self { self }

        var label: String {
            switch self {
            case .system: "跟隨系統"
            case .light: "淺色"
            case .dark: "深色"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Requires device authentication before the member card is shown. Off by
    /// default — it protects the member's own data, so it is theirs to opt into.
    var requireBiometricsForCard: Bool {
        didSet { defaults.set(requireBiometricsForCard, forKey: Keys.biometrics) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "settings.appearance"
        static let biometrics = "settings.requireBiometricsForCard"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        requireBiometricsForCard = defaults.bool(forKey: Keys.biometrics)
    }
}
