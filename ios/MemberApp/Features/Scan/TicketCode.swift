import Foundation

/// What the door scanner found in frame.
///
/// Two unrelated formats reach the same registration by different routes. A
/// member card names a *person*, so it has to be matched against the roster on
/// email — that is `MembershipValidator` plus `CheckinStore.entry(email:)`. An
/// Indico ticket carries the registration's *own* secret, so it resolves
/// directly and works for someone whose Indico address is not their STSA one.
///
/// Recognising a code is deliberately separate from resolving one: nothing here
/// touches the network, which is what makes it the part worth pinning in tests.
enum ScannedCode: Equatable {
    /// A member card, with `stsa$` already stripped.
    case memberCard(String)

    /// An Indico ticket. Format per `get_ticket_qr_code_data` in
    /// `indico/modules/events/registration/util.py`, confirmed on v3.3.13.
    case ticket(Ticket)

    struct Ticket: Equatable {
        /// Indico's `ticket_uuid`, named `checkin_secret` on the wire.
        var checkinSecret: UUID

        /// The instance that issued the ticket, without a scheme. Checked before
        /// use: a ticket from another Indico is not ours to check in.
        var host: String

        /// Set only on a ticket issued to an accompanying person, who has no
        /// registration of their own. Indico's own app can check those in; this
        /// one cannot, and checking in the registrant who brought them would be
        /// a quiet lie.
        var accompanyingPersonID: UUID?
    }

    /// Returns nil for anything else in frame — a Wi-Fi QR, a boarding pass, a
    /// ticket from a format version this app does not know.
    static func parse(_ raw: String) -> ScannedCode? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = MembershipValidator.code(from: text) { return .memberCard(code) }
        if let ticket = ticket(from: text) { return .ticket(ticket) }
        return nil
    }

    /// Bumped by Indico whenever the QR layout changes. An unknown version is
    /// refused rather than parsed hopefully: the fields would be in the wrong
    /// places, and that surfaces as the wrong person rather than as an error.
    private static let supportedVersion = 2

    private static func ticket(from text: String) -> Ticket? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              // Plugins add sibling keys — CERN's site-access plugin adds an
              // ADaMS URL — so read `i` and ignore whatever else is there.
              let fields = object["i"] as? [Any],
              fields.count >= 3,
              let version = fields[0] as? Int, version == supportedVersion,
              let issuer = fields[1] as? String,
              let secret = fields[2] as? String,
              let checkinSecret = uuid(fromBase64: secret)
        else { return nil }

        let person = fields.count >= 4 ? (fields[3] as? String).flatMap(uuid(fromBase64:)) : nil

        return Ticket(checkinSecret: checkinSecret,
                      host: host(from: issuer),
                      accompanyingPersonID: person)
    }

    /// Indico base64-encodes the UUID's 16 raw bytes rather than its hyphenated
    /// text, to keep the QR small enough to scan off a phone screen.
    private static func uuid(fromBase64 encoded: String) -> UUID? {
        guard let bytes = Data(base64Encoded: encoded), bytes.count == 16 else { return nil }
        var raw = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &raw) { bytes.copyBytes(to: $0) }
        return UUID(uuid: raw)
    }

    /// Indico strips `https://` from the URL it writes into the QR to save
    /// bytes, but leaves `http://` in place, so handle both.
    private static func host(from url: String) -> String {
        var value = url
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) {
            value = String(value.dropFirst(scheme.count))
        }
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        return value
    }
}
