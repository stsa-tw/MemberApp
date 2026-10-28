import AppAuth
import AuthenticationServices
import UIKit

/// AppAuth's browser leg, with one change: the page that opens is
/// `AuthConfiguration.signInFlowURL`, carrying AppAuth's authorize request as
/// its `next`, instead of the authorize URL itself.
///
/// Everything else is AppAuth's — it still derives the PKCE verifier, builds the
/// authorize request, recognises the redirect and exchanges the code. This only
/// decides which page the browser sheet starts on, which is why it does what
/// `OIDExternalUserAgentIOS` does and nothing more: `ASWebAuthenticationSession`
/// so the page shares Safari's session, and the same cancellation error so
/// `AuthManager.isUserCancellation` keeps recognising a dismissed sheet.
///
/// `next` is the authorize URL as a *relative* reference. authentik follows a
/// relative `next` after the flow, and not necessarily an absolute one.
final class SignInFlowUserAgent: NSObject, OIDExternalUserAgent, ASWebAuthenticationPresentationContextProviding {
    private let presenter: UIViewController
    private let ephemeral: Bool
    private var webSession: ASWebAuthenticationSession?
    private weak var flow: OIDExternalUserAgentSession?

    init(presenting presenter: UIViewController, prefersEphemeralSession: Bool) {
        self.presenter = presenter
        self.ephemeral = prefersEphemeralSession
    }

    /// The flow's address with the authorize request attached, or nil if the
    /// authorize URL has no path to follow.
    static func flowURL(forAuthorize authorize: URL) -> URL? {
        guard let parts = URLComponents(url: authorize, resolvingAgainstBaseURL: false) else { return nil }
        var next = parts.percentEncodedPath
        if let query = parts.percentEncodedQuery { next += "?" + query }
        guard next.hasPrefix("/") else { return nil }

        var flow = URLComponents(url: AuthConfiguration.signInFlowURL, resolvingAgainstBaseURL: false)
        // Encoded by hand: `URLQueryItem` leaves `?`, `&` and `=` alone, which
        // would split the authorize request's own parameters off as the flow's.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        flow?.percentEncodedQuery = "next=" + (next.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        return flow?.url
    }

    func present(_ request: any OIDExternalUserAgentRequest, session: any OIDExternalUserAgentSession) -> Bool {
        guard webSession == nil,
              let authorize = request.externalUserAgentRequestURL(),
              let url = Self.flowURL(forAuthorize: authorize)
        else { return false }

        flow = session
        let web = ASWebAuthenticationSession(url: url, callbackURLScheme: request.redirectScheme()) { [weak self] callback, error in
            guard let self else { return }
            self.webSession = nil
            if let callback {
                self.flow?.resumeExternalUserAgentFlow(with: callback)
            } else {
                self.flow?.failExternalUserAgentFlowWithError(
                    OIDErrorUtilities.error(
                        with: .userCanceledAuthorizationFlow,
                        underlyingError: error,
                        description: nil
                    )
                )
            }
        }
        web.presentationContextProvider = self
        web.prefersEphemeralWebBrowserSession = ephemeral
        webSession = web

        if web.start() { return true }
        webSession = nil
        return false
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        webSession?.cancel()
        webSession = nil
        completion()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presenter.view.window ?? ASPresentationAnchor()
    }
}
