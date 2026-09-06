import CoreImage
import PDFKit
import SwiftUI

/// The member's own ticket, read once so the app can show the code itself.
///
/// Indico hands a member their ticket as a PDF and nothing else. The check-in
/// payload does exist as data — `/api/checkin/…` is made of it — but that API is
/// `RHManageEventBase`, an organiser reading a roster, so a member asking for
/// their own gets a 403. The PDF is what they are allowed to have, and the QR is
/// printed on it. So the page is rendered and the code read back off it.
///
/// `ScannedCode.parse` is the filter, and it is the door scanner's own parser
/// rather than a lookalike: a ticket template can carry other codes — a link to
/// the event page, an organiser's logo — and only one of them is an Indico
/// ticket. When one is found the app draws it itself, large and square-edged, at
/// the size a phone screen is actually scanned from. When none is, the rendered
/// page is shown as Indico drew it, which still scans and still says everything
/// the ticket says.
///
/// Nothing is written to disk and nothing outlives the screen: a ticket QR *is*
/// the credential — whoever holds it can be checked in as that member, which is
/// why `TicketStore` keeps only URLs — so this lives for as long as the view
/// does and no longer.
@Observable
final class TicketDocument {
    enum State {
        case loading
        case ready(Ticket)
        case failed(String)
    }

    enum Ticket {
        /// The check-in payload, verbatim, for the app to draw.
        case code(String)
        /// The ticket as Indico drew it, for when no code could be read back.
        case page(UIImage)
    }

    private(set) var state = State.loading

    func load(from url: URL, using indico: IndicoAuthManager) async {
        state = .loading

        do {
            let request = try indico.authorizedRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            // The same test the probe that found this ticket runs, and for the
            // same reason: `URLSession` follows redirects, so a request that
            // lost its authorization comes back a perfectly good 200 carrying
            // Indico's login page. Only a PDF body is a ticket.
            let outcome = TicketStore.outcome(
                status: http?.statusCode ?? 0,
                contentType: http?.value(forHTTPHeaderField: "Content-Type")
            )
            guard outcome == .available else { throw LoadError.unavailable }
            guard let ticket = await Self.read(data) else { throw LoadError.unreadable }

            state = .ready(ticket)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    enum LoadError: LocalizedError {
        case unavailable
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "無法取得票券，稍後再試。")
            case .unreadable: String(localized: "票券格式無法讀取。")
            }
        }
    }

    // MARK: - Reading the page

    /// Rendering a page and searching it for a QR is real work, and it happens
    /// while the screen is pushing in, so it goes off the main actor rather than
    /// stalling the animation it arrives behind.
    @concurrent
    private nonisolated static func read(_ data: Data) async -> Ticket? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }

        // Indico's ticket templates are badge-sized, so the page is small in
        // points and at its own scale the QR is barely wider than its own
        // modules — enough to print, not enough to find again. 3× is enough for
        // the detector and cheap enough to do while the screen animates.
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let rendered = page.thumbnail(
            of: CGSize(width: bounds.width * 3, height: bounds.height * 3),
            for: .mediaBox
        )

        if let code = code(in: rendered) { return .code(code) }
        return .page(rendered)
    }

    private nonisolated static func code(in image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: CIContext(),
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: cgImage)) ?? []

        for feature in features {
            guard let message = (feature as? CIQRCodeFeature)?.messageString else { continue }
            if case .ticket = ScannedCode.parse(message) { return message }
        }
        return nil
    }
}
