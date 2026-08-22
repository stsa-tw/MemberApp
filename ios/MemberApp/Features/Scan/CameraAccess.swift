import AVFoundation

/// `.restricted` and `.denied` are the same dead end from here — the scanner
/// cannot open, and the only way forward is Settings.
///
/// Shared by the member-card scanner and the event door, which ask the same
/// question and hit the same wall.
enum CameraAccess {
    case undetermined, granted, denied

    static var current: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    /// Asks only when there is something to ask; returns the settled answer.
    static func request() async -> CameraAccess {
        guard current == .undetermined else { return current }
        return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    }
}
