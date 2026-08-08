import LocalAuthentication

/// Device-owner authentication in front of the member card.
///
/// This is not a second login — it cannot obtain a token, and the session is
/// already established. It guards against the one case the iOS lock screen does
/// not cover: someone holding the phone while it is already unlocked.
enum BiometricGate {
    /// True when the device can authenticate at all — biometrics *or* passcode.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// The biometry the device actually has, for labelling the toggle honestly.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "裝置密碼"
        }
    }

    /// Returns true when the person authenticated.
    ///
    /// Uses `.deviceOwnerAuthentication` rather than the biometrics-only policy
    /// so a failed scan — mask, sunglasses, wet hands — falls back to the
    /// passcode instead of locking someone out of their own card.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No passcode set at all: refuse to gate rather than make the card
            // unreachable.
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)) ?? false
    }
}
