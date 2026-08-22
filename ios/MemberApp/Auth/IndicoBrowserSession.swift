import AuthenticationServices
import Foundation
import UIKit

/// Runs the Indico authorization page in `ASWebAuthenticationSession` and hands
/// back the callback URL.
///
/// AppAuth cannot drive this flow itself, and the reason is one line in
/// `OIDAuthorizationService`:
///
/// ```objc
/// - (BOOL)shouldHandleURL:(NSURL *)URL {
///   return [[self class] URL:URL matchesRedirectionURL:_request.redirectURL];
/// }
/// ```
///
/// The same `redirectURL` is used both to build the authorize request and to
/// recognise the response. Ours cannot be one value: Indico only accepts an
/// `http(s)` redirect, so the request must carry the bridge URL, while what
/// comes back is `tw.stsa.membership://callback` after the bridge's 302. AppAuth
/// rejects that as unrelated and the flow never resumes — no error, no callback,
/// the sheet just closes and nothing happens.
///
/// So the browser leg is ours and everything else stays AppAuth's: it still
/// derives the PKCE verifier, builds the authorize URL, and performs the token
/// exchange. AppAuth-Android has no equivalent check, so that side uses AppAuth
/// end to end — the asymmetry is the libraries', not ours.
enum IndicoBrowserSession {

    enum SessionError: LocalizedError {
        case noPresenter
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .noPresenter:
                "No foreground window to present the authorization page from."
            case .couldNotStart:
                "The authorization page could not be opened."
            }
        }
    }

    @MainActor
    static func authorize(url: URL) async throws -> URL {
        guard let anchor = keyWindow() else { throw SessionError.noPresenter }
        let provider = AnchorProvider(anchor: anchor)

        return try await withCheckedThrowingContinuation { continuation in
            // `start()` returning false does not mean the completion handler will
            // not *also* fire — when the session cannot be presented, both happen.
            // Resuming a checked continuation twice is a hard crash rather than a
            // warning, and that is exactly what shipped: on a phone that had never
            // linked Indico, the attempt ran before there was a window to present
            // from, took both paths, and killed the app before it drew a frame.
            let once = OneShot(continuation)

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: IndicoAuthConfiguration.callbackScheme
            ) { callbackURL, error in
                provider.retain = nil
                if let callbackURL {
                    once.resume(returning: callbackURL)
                } else {
                    once.resume(throwing: error ?? SessionError.couldNotStart)
                }
            }

            session.presentationContextProvider = provider
            // Deliberately *not* ephemeral. The browser already carries an
            // authentik session from signing in, and Indico delegates
            // authentication to authentik — sharing it is what turns this into a
            // silent redirect rather than a second login.
            session.prefersEphemeralWebBrowserSession = false

            provider.retain = session
            if !session.start() {
                provider.retain = nil
                once.resume(throwing: SessionError.couldNotStart)
            }
        }
    }

    /// Deliberately strict: only a scene that is actually foreground-active can
    /// present a browser session. Falling back to "any window we can find" is how
    /// the launch-time attempt ended up trying to present from a scene that was
    /// still coming up.
    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }

    /// A continuation may be resumed exactly once; this makes that structural
    /// rather than something every call site has to remember.
    private final class OneShot {
        private var continuation: CheckedContinuation<URL, any Error>?

        init(_ continuation: CheckedContinuation<URL, any Error>) {
            self.continuation = continuation
        }

        func resume(returning url: URL) {
            continuation?.resume(returning: url)
            continuation = nil
        }

        func resume(throwing error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    /// `ASWebAuthenticationSession` keeps only a weak reference to its context
    /// provider, and nothing else here outlives the `await`.
    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        private let anchor: ASPresentationAnchor
        var retain: ASWebAuthenticationSession?

        init(anchor: ASPresentationAnchor) {
            self.anchor = anchor
            super.init()
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }
}
