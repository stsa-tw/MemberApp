import Foundation

/// The claims returned by authentik's userinfo endpoint.
///
/// `sub` is the only stable identifier: authentik lets users change their email
/// and username, and `groups` is recomputed on every login. Anything stored
/// locally against a user must be keyed on `sub`.
struct Profile: Codable, Hashable, Identifiable {
    let sub: String
    var email: String?
    var emailVerified: Bool?
    var name: String?
    var givenName: String?
    var preferredUsername: String?
    var nickname: String?

    /// Group memberships. Fine for driving UI — hiding a tab, showing a badge —
    /// but never a security boundary: it is a self-reported claim from a token
    /// this app does not verify. Real authorisation is re-checked server-side
    /// against the token signature.
    var groups: [String]

    /// Stable local storage key. Never use `email` or `preferredUsername`.
    var id: String { sub }

    enum CodingKeys: String, CodingKey {
        case sub, email, name, nickname, groups
        case emailVerified = "email_verified"
        case givenName = "given_name"
        case preferredUsername = "preferred_username"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sub = try container.decode(String.self, forKey: .sub)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        preferredUsername = try container.decodeIfPresent(String.self, forKey: .preferredUsername)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        groups = try container.decodeIfPresent([String].self, forKey: .groups) ?? []
    }

    /// Best available human-readable name, in the order authentik populates them.
    var displayName: String {
        name ?? nickname ?? givenName ?? preferredUsername ?? email ?? sub
    }
}
