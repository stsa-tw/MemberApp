import Foundation
import Testing

@testable import MemberApp

struct SignInFlowTests {
    private let authorize = URL(string:
        "https://idms.stsa.tw/application/o/authorize/?response_type=code&client_id=abc&redirect_uri=tw.stsa.membership%3A%2F%2Fcallback&scope=openid%20profile&code_challenge=xyz&code_challenge_method=S256&state=s1"
    )!

    @Test func opensTheSignInFlow() throws {
        let url = try #require(SignInFlowUserAgent.flowURL(forAuthorize: authorize))
        #expect(url.absoluteString.hasPrefix("https://idms.stsa.tw/if/flow/ios-authentication-flow/?next="))
    }

    /// The authorize request has to come back out of `next` exactly as it went
    /// in — its `&` and `=` belong to it, not to the flow's own query.
    @Test func carriesTheAuthorizeRequestAsOneRelativeNext() throws {
        let url = try #require(SignInFlowUserAgent.flowURL(forAuthorize: authorize))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.count == 1)
        let next = try #require(items.first { $0.name == "next" }?.value)
        #expect(next.hasPrefix("/application/o/authorize/?response_type=code&client_id=abc"))
        #expect(next.hasSuffix("&state=s1"))
        #expect(!next.contains("https://"))
    }
}
