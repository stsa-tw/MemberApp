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
        case home, events, deals, jobs, profile, card, ticket
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

    /// The event the fixture ticket belongs to.
    ///
    /// Through the decoder for the same reason [member] is: `IndicoEvent`
    /// declares `init(from:)`, and going in the way a real one does keeps the
    /// fixture honest about the shape Indico's category export actually emits —
    /// `startDate` split into date/time/tz, `description` as HTML.
    static let event: IndicoEvent = {
        let json = """
        {
          "id": "0",
          "title": "2026 STSA 烤場集合",
          "type": "meeting",
          "startDate": {"date": "2026-09-19", "time": "17:30:00", "tz": "Asia/Singapore"},
          "endDate":   {"date": "2026-09-19", "time": "21:00:00", "tz": "Asia/Singapore"},
          "location": "East Coast Park",
          "room": "Area E & F",
          "description": "<p>烤肉、認識新朋友，帶一個人來也可以。</p>"
        }
        """
        return try! JSONDecoder().decode(IndicoEvent.self, from: Data(json.utf8))
    }()

    /// An Indico ticket QR, in the real format — `get_ticket_qr_code_data`,
    /// version 2, issuer then the base64 of the secret's 16 raw bytes — so the
    /// code photographs at exactly the density a real one does.
    ///
    /// The secret is a UUID Indico has never issued, so the ticket resolves to
    /// 「Indico 沒有這張票」 rather than to anybody. A real member's ticket QR
    /// *is* the credential: whoever holds it can be checked in as them, which is
    /// the whole reason this file exists.
    static let ticketCode = #"{"i":[2,"event.stsa.tw","AAAAAAAAQACAAAAAAAAAAg=="]}"#

    /// Where the real screen would fetch the PDF from. Nothing requests it —
    /// `TicketDocument` short-circuits under this fixture — but the view takes a
    /// URL, and 在 Indico 開啟 should point somewhere truthful if it is tapped.
    static let ticketURL = URL(string: "https://event.stsa.tw/event/0/registrations/ticket")!

    /// Where the real screen would fetch the pass from, so that 加入 Apple Wallet
    /// is in the photograph of the screen it lives on.
    ///
    /// Seeded into `TicketStore` rather than probed for. The fixture member holds
    /// no Indico authorization, so `loadWalletPass` stops at its first guard and
    /// the button could never appear in a capture run — which is why it was
    /// missing from every ticket screenshot taken so far. Nothing requests this:
    /// a capture run is not tapped.
    static let walletPassURL =
        URL(string: "https://event.stsa.tw/event/0/registrations/0/ticket/apple-wallet")!
}
#endif
