import Foundation
import Observation

/// Loads events from the STSA Indico instance.
///
/// The category export is public, so this deliberately carries no credentials —
/// events are visible on the web without signing in, and requiring a token here
/// would only make the tab fail for no gain. Registration is the part that needs
/// an account, and that happens on Indico itself.
@MainActor
@Observable
final class EventsStore {
    private(set) var events: [IndicoEvent] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Root category. Everything STSA runs lives under it today; if that changes,
    /// this is the one thing to repoint.
    private static let endpoint = URL(
        string: "https://event.stsa.tw/export/categ/0.json?from=-180d&to=730d&limit=200"
    )!

    var upcoming: [IndicoEvent] { events.filter(\.isUpcoming).sorted { $0.start < $1.start } }
    var past: [IndicoEvent] { events.filter { !$0.isUpcoming }.sorted { $0.start > $1.start } }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.endpoint)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw LoadError.server(status: http.statusCode)
            }
            events = try JSONDecoder().decode(Envelope.self, from: data).results
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Indico wraps every export in `{count, ts, url, results: [...]}`.
    private struct Envelope: Decodable {
        let results: [IndicoEvent]
    }

    enum LoadError: LocalizedError {
        case server(status: Int)

        var errorDescription: String? {
            switch self {
            case .server(let status): "Indico 回應 HTTP \(status)。"
            }
        }
    }
}
