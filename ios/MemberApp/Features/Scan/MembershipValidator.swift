import Foundation
import Observation

/// The member a scanned code was minted for.
///
/// Mirrors `MembershipToken` in MembershipAPI — the three fields it serialises
/// into Redis and hands back from `/validate_code`.
struct ScannedMember: Decodable, Equatable {
    let name: String
    let username: String
    let email: String
}

/// Resolves a scanned `stsa$…` payload into the member holding it.
///
/// The mirror of `MembershipCodeStore`: that asks MembershipAPI to mint a code,
/// this hands one back and asks whose it is. Validating does not consume the
/// code — `/validate_code` only reads Redis — so a green tick means "this person
/// authenticated within the last 300 seconds", not "this person just checked
/// in". Nothing is recorded anywhere; the answer is for the human holding the
/// phone, exactly as on the web scanner.
@MainActor
@Observable
final class MembershipValidator {
    enum Outcome: Equatable {
        /// The code resolved to a member.
        case valid(ScannedMember)
        /// The server answered, and the answer was no — expired, already gone
        /// from Redis, or never minted.
        case invalid
        /// No answer to be had. Kept apart from `.invalid` on purpose: showing a
        /// flat "not a member" because the network dropped is how someone gets
        /// turned away from a door they belong at.
        case unreachable(String)
    }

    private(set) var outcome: Outcome?
    private(set) var isValidating = false

    /// Every payload the scanner accepts carries this. Anything else in frame is
    /// somebody's Wi-Fi QR code.
    static let prefix = "stsa$"

    private static let endpoint = URL(string: "https://idms.stsa.tw/membership/api/validate_code")!

    /// Strips the prefix and returns the bare code, or nil if `payload` is not
    /// one of ours.
    ///
    /// The code is interpolated into a URL path, so it is checked rather than
    /// trusted — a QR code is attacker-supplied input like any other, and
    /// `stsa$../me` must not be able to reach a different endpoint. MembershipAPI
    /// mints 20 characters from `[A-Za-z0-9]`; the length is bounded rather than
    /// fixed so that changing `CODE_LENGTH` there does not break scanning here.
    nonisolated static func code(from payload: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let code = payload.dropFirst(prefix.count)
        guard (1...64).contains(code.count),
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return String(code)
    }

    func validate(payload: String) async {
        guard let code = Self.code(from: payload) else {
            // Well-formed enough to carry our prefix, but not a code we minted.
            outcome = .invalid
            return
        }

        isValidating = true
        defer { isValidating = false }

        do {
            // No Authorization header: `/validate_code` does not ask for one,
            // unlike `/get_code`. That is the API's shape, not an oversight here.
            let (data, response) = try await URLSession.shared.data(from: Self.endpoint.appending(path: code))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // A rejected code comes back as 400 with `valid: false`, so the body
            // carries the answer at either status; only a body we cannot read
            // means we failed to ask.
            guard let decoded = try? JSONDecoder().decode(ValidationResponse.self, from: data) else {
                outcome = .unreachable(String(localized: "伺服器回應無法解讀(\(status))。"))
                return
            }

            if decoded.valid, let member = decoded.token {
                outcome = .valid(member)
            } else {
                outcome = .invalid
            }
        } catch {
            outcome = .unreachable(error.localizedDescription)
        }
    }

    func reset() {
        outcome = nil
    }

    private struct ValidationResponse: Decodable {
        let valid: Bool
        let token: ScannedMember?
    }
}
