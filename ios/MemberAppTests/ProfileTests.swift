import Foundation
import Testing

@testable import MemberApp

/// `Profile` has no memberwise initialiser — the custom `init(from:)` replaces
/// it — so every case here goes through decoding, which is how the app builds
/// one anyway.
private func makeProfile(_ json: String) throws -> Profile {
    try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
}

struct ProfileDecodingTests {
    @Test func mapsAuthentikSnakeCaseClaims() throws {
        let profile = try makeProfile("""
        {
          "sub": "abc-123",
          "email": "kimi@u.nus.edu",
          "email_verified": true,
          "given_name": "Kimi",
          "preferred_username": "kimiyang"
        }
        """)

        #expect(profile.sub == "abc-123")
        #expect(profile.emailVerified == true)
        #expect(profile.givenName == "Kimi")
        #expect(profile.preferredUsername == "kimiyang")
    }

    /// authentik omits `groups` entirely when a user is in none. That has to
    /// decode as "no groups" rather than throwing, or sign-in fails outright.
    @Test func treatsAbsentGroupsAsEmptyRatherThanFailing() throws {
        let profile = try makeProfile(#"{"sub": "abc-123"}"#)

        #expect(profile.groups.isEmpty)
        #expect(profile.isOfficer == false)
    }

    /// `sub` is the one claim the app cannot work without.
    @Test func requiresSub() {
        #expect(throws: (any Error).self) {
            try makeProfile(#"{"email": "kimi@u.nus.edu"}"#)
        }
    }
}

struct ProfileDisplayNameTests {
    /// The fallback chain is ordered by how authentik populates the claims.
    @Test func prefersNameOverEverythingElse() throws {
        let profile = try makeProfile("""
        {"sub": "abc", "name": "楊", "nickname": "Kimi", "preferred_username": "kimiyang"}
        """)

        #expect(profile.displayName == "楊")
    }

    @Test func fallsThroughToUsernameWhenNamesAreAbsent() throws {
        let profile = try makeProfile(#"{"sub": "abc", "preferred_username": "kimiyang"}"#)

        #expect(profile.displayName == "kimiyang")
    }

    /// Worst case the UI still shows something rather than an empty label.
    @Test func fallsBackToSubWhenNothingIsPopulated() throws {
        let profile = try makeProfile(#"{"sub": "abc-123"}"#)

        #expect(profile.displayName == "abc-123")
    }
}

struct ProfileSchoolTests {
    @Test("Recognised school domains map to their abbreviation", arguments: [
        ("kimi@u.nus.edu", "NUS"),
        ("kimi@nus.edu.sg", "NUS"),
        ("kimi@e.ntu.edu.sg", "NTU"),
        ("kimi@ntu.edu.sg", "NTU"),
        ("kimi@smu.edu.sg", "SMU"),
        ("kimi@sutd.edu.sg", "SUTD"),
    ])
    func mapsKnownDomains(email: String, expected: String) throws {
        let profile = try makeProfile(#"{"sub": "abc", "email": "\#(email)"}"#)

        #expect(profile.school == expected)
    }

    /// The domain is lowercased before matching, so a capitalised address from
    /// authentik still resolves.
    @Test func matchesRegardlessOfCase() throws {
        let profile = try makeProfile(#"{"sub": "abc", "email": "KIMI@U.NUS.EDU"}"#)

        #expect(profile.school == "NUS")
    }

    /// This is inference from an email domain, not an authoritative claim — an
    /// unknown domain must produce nil rather than a plausible guess.
    @Test("Unknown domains return nil rather than guessing", arguments: [
        "kimi@gmail.com",
        "kimi@mit.edu",
        "kimi@stsa.tw",
    ])
    func doesNotGuessUnknownDomains(email: String) throws {
        let profile = try makeProfile(#"{"sub": "abc", "email": "\#(email)"}"#)

        #expect(profile.school == nil)
    }

    @Test func returnsNilWhenThereIsNoEmailAtAll() throws {
        let profile = try makeProfile(#"{"sub": "abc"}"#)

        #expect(profile.school == nil)
    }

    /// Matching is by suffix, so a domain that merely *ends* with a school's
    /// domain is accepted. `bonus.edu.sg` is not a real registrar entry, and the
    /// claim is UI-only, so this is recorded rather than treated as a defect —
    /// if the match ever tightens to a dot boundary, this expectation flips.
    @Test func suffixMatchingAcceptsDomainsThatMerelyEndWithASchoolDomain() throws {
        let profile = try makeProfile(#"{"sub": "abc", "email": "kimi@bonus.edu.sg"}"#)

        #expect(profile.school == "NUS")
    }
}

struct ProfileOfficerTests {
    /// Drives UI only — never a security boundary. The test pins the exact
    /// group name, which is the part a rename would silently break.
    @Test func officerGroupIsMatchedExactly() throws {
        let officer = try makeProfile(#"{"sub": "abc", "groups": ["STSA 幹部"]}"#)
        let member = try makeProfile(#"{"sub": "abc", "groups": ["STSA 會員"]}"#)

        #expect(officer.isOfficer)
        #expect(member.isOfficer == false)
    }
}
