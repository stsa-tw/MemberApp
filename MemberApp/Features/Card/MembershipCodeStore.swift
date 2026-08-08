import Foundation
import Observation

/// Fetches and keeps fresh the code behind the member card's QR.
///
/// The server mints a new code per request and stores it in Redis for 300
/// seconds (`CODE_TTL` in MembershipAPI). The web card re-fetches every 250s to
/// stay inside that window; this does the same, but only while the card is on
/// screen — there is no reason to hold a live code in the user's pocket.
@MainActor
@Observable
final class MembershipCodeStore {
    /// MembershipAPI's `CODE_TTL`. After this the code is dead server-side.
    static let lifetime: TimeInterval = 300
    /// Matches the web card's cadence — comfortably inside `lifetime`.
    static let refreshInterval: TimeInterval = 250

    private(set) var payload: String?
    private(set) var issuedAt: Date?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    private var refreshTask: Task<Void, Never>?

    /// The scanner rejects anything not carrying this prefix.
    private static let prefix = "stsa$"
    private static let endpoint = URL(string: "https://idms.stsa.tw/membership/api/get_code")!

    var expiresAt: Date? {
        issuedAt?.addingTimeInterval(Self.lifetime)
    }

    /// True once the code the user is showing can no longer be validated.
    func hasExpired(at moment: Date) -> Bool {
        guard let expiresAt else { return false }
        return moment >= expiresAt
    }

    // MARK: - Lifecycle

    /// Fetches immediately, then keeps refreshing until `stop()`.
    func start(using auth: AuthManager) {
        stop()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(using: auth)
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(using auth: AuthManager) async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // Goes through performAction, so an access token older than five
            // minutes is renewed before this call rather than 401ing.
            let request = try await auth.authorizedRequest(for: Self.endpoint)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw CodeError.server(status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
            }

            let decoded = try JSONDecoder().decode(CodeResponse.self, from: data)
            payload = Self.prefix + decoded.code
            issuedAt = Date()
            errorMessage = nil
        } catch {
            // The previous code is deliberately kept: it may still be inside its
            // 300s window, and a card that blanks out on a flaky connection is
            // worse than one showing a code that might still scan.
            errorMessage = error.localizedDescription
        }
    }

    private struct CodeResponse: Decodable {
        let code: String
    }

    enum CodeError: LocalizedError {
        case server(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .server(let status, let body) where status == 401:
                "登入已失效,請重新登入。(401 \(body.prefix(120)))"
            case .server(let status, let body) where status == 403:
                "帳號缺少必要的授權範圍。(403 \(body.prefix(120)))"
            case .server(let status, let body):
                "伺服器錯誤 \(status)。\(body.prefix(120))"
            }
        }
    }
}
