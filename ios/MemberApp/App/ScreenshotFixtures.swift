#if DEBUG
import Foundation

/// Fills the app with a fictional member so the App Store screenshots can be
/// captured without signing a real person in.
///
/// DEBUG-only, and inert unless `STSA_SCREENSHOT=1` is in the launch
/// environment, so it cannot reach a release build or an ordinary debug run.
/// The point is not convenience: a published screenshot of the member card
/// would otherwise carry somebody's real name, school email and a live QR
/// payload. This member does not exist.
enum ScreenshotFixtures {
    /// Which screen to open on. Set with `STSA_SCREENSHOT_SCREEN`.
    ///
    /// Driven by the launch environment rather than by tapping through the UI:
    /// each capture is then one `simctl launch`, and reruns land on exactly the
    /// same pixels.
    enum Screen: String {
        case home, events, deals, jobs, profile, card
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["STSA_SCREENSHOT"] == "1"
    }

    static var screen: Screen {
        Screen(rawValue: ProcessInfo.processInfo.environment["STSA_SCREENSHOT_SCREEN"] ?? "") ?? .home
    }

    /// `Profile` declares `init(from:)`, so there is no memberwise initialiser
    /// to call — the fixture goes in the way a real one does, through the
    /// decoder, which also keeps it honest about the claim names authentik
    /// actually sends.
    static let member: Profile = {
        let claims = """
        {
          "sub": "00000000-0000-4000-8000-000000000001",
          "email": "demo@u.nus.edu",
          "email_verified": true,
          "name": "王小明",
          "given_name": "小明",
          "preferred_username": "demo",
          "nickname": "Ming",
          "groups": ["STSA 會員"]
        }
        """
        return try! JSONDecoder().decode(Profile.self, from: Data(claims.utf8))
    }()

    /// Carries the scanner's `stsa$` prefix so the QR renders exactly as a real
    /// one does. The code itself is not valid server-side, which is the point.
    static let membershipCode = "stsa$SCREENSHOT-DEMO-CODE-0000"
}
#endif
