import Foundation
import Testing

@testable import MemberApp

/// The scanner hands whatever was in the frame to `code(from:)`, and the result
/// goes straight into a URL path, so these cases are the boundary between a QR
/// code somebody printed and a request this app makes.
struct MembershipCodeParsingTests {
    @Test func stripsThePrefix() {
        let code = String(repeating: "a", count: 20)
        #expect(MembershipValidator.code(from: "stsa$" + code) == code)
    }

    @Test func acceptsTheMixedCaseAlphanumericsTheServerMints() {
        #expect(MembershipValidator.code(from: "stsa$aB3xY9zQ1mN4pL7kR2wT") == "aB3xY9zQ1mN4pL7kR2wT")
    }

    @Test func rejectsPayloadsThatAreNotOurs() {
        #expect(MembershipValidator.code(from: "WIFI:S:cafe;T:WPA;P:hunter2;;") == nil)
        #expect(MembershipValidator.code(from: "https://stsa.tw") == nil)
        #expect(MembershipValidator.code(from: "") == nil)
        // The prefix has to lead, not merely appear.
        #expect(MembershipValidator.code(from: "xstsa$abc") == nil)
    }

    @Test func rejectsAnEmptyCode() {
        #expect(MembershipValidator.code(from: "stsa$") == nil)
    }

    /// The one that matters: `appending(path:)` would happily walk a `..` up to
    /// a different endpoint.
    @Test func rejectsPathTraversalAndSeparators() {
        #expect(MembershipValidator.code(from: "stsa$../me") == nil)
        #expect(MembershipValidator.code(from: "stsa$abc/def") == nil)
        #expect(MembershipValidator.code(from: "stsa$abc?x=1") == nil)
        #expect(MembershipValidator.code(from: "stsa$abc def") == nil)
        #expect(MembershipValidator.code(from: "stsa$abc%2f") == nil)
    }

    /// `Character.isNumber` is true for these, which is why the check also
    /// insists on ASCII.
    @Test func rejectsNonASCIIDigitsAndLetters() {
        #expect(MembershipValidator.code(from: "stsa$１２３４５") == nil)
        #expect(MembershipValidator.code(from: "stsa$會員碼") == nil)
    }

    @Test func rejectsCodesFarLongerThanTheServerMints() {
        #expect(MembershipValidator.code(from: "stsa$" + String(repeating: "a", count: 64)) != nil)
        #expect(MembershipValidator.code(from: "stsa$" + String(repeating: "a", count: 65)) == nil)
    }
}

struct ScannedMemberDecodingTests {
    @Test func decodesTheTokenMembershipAPIReturns() throws {
        let member = try JSONDecoder().decode(ScannedMember.self, from: Data("""
        {"name": "Kimi Yang", "email": "kimi@u.nus.edu", "username": "kimiyang"}
        """.utf8))

        #expect(member.name == "Kimi Yang")
        #expect(member.username == "kimiyang")
        #expect(member.email == "kimi@u.nus.edu")
    }
}
