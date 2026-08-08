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
            case .system: String(localized: "跟隨系統")
            case .light: String(localized: "淺色")
            case .dark: String(localized: "深色")
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

    /// Requires device authentication before the member card is shown.
    ///
    /// On by default: the card is the member's identity credential, and a phone
    /// handed to someone while unlocked is exactly the case the lock screen does
    /// not cover. Devices with no passcode fall through in `BiometricGate`
    /// rather than being locked out.
    var requireBiometricsForCard: Bool {
        didSet { defaults.set(requireBiometricsForCard, forKey: Keys.biometrics) }
    }

    /// Channels the member follows, by `Channel.id`. `nil` means never chosen,
    /// which lets the first read seed from their school rather than assuming
    /// they deliberately unfollowed everything.
    private(set) var subscribedChannels: Set<String>?

    func setSubscribed(_ subscribed: Bool, channel: Channel, defaultingTo seed: Set<String>) {
        var ids = subscribedChannels ?? seed
        if subscribed { ids.insert(channel.id) } else { ids.remove(channel.id) }
        subscribedChannels = ids
        defaults.set(Array(ids), forKey: Keys.channels)
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "settings.appearance"
        static let biometrics = "settings.requireBiometricsForCard"
        static let channels = "settings.subscribedChannels"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        // `bool(forKey:)` cannot tell "never set" from "explicitly off", and the
        // default is on — so check for the key before falling back.
        requireBiometricsForCard = defaults.object(forKey: Keys.biometrics) == nil
            ? true
            : defaults.bool(forKey: Keys.biometrics)
        subscribedChannels = (defaults.array(forKey: Keys.channels) as? [String]).map(Set.init)
    }
}
