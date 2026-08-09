import Foundation
import Testing

@testable import MemberApp

/// Each case gets its own UserDefaults suite so nothing leaks between tests or
/// into the simulator's real preferences.
@MainActor
private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "AppSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@MainActor
struct AppSettingsBiometricsTests {
    /// The card is the member's identity credential, so the gate is on until
    /// someone turns it off.
    @Test func defaultsToOnWhenNeverChosen() {
        withDefaults { defaults in
            #expect(AppSettings(defaults: defaults).requireBiometricsForCard)
        }
    }

    /// The case the implementation comment is about: `bool(forKey:)` returns
    /// false both for "never set" and for "explicitly off", and the default is
    /// on — so an explicit off must survive a relaunch rather than being
    /// re-defaulted back to on.
    @Test func anExplicitOffIsNotResetToTheDefault() {
        withDefaults { defaults in
            defaults.set(false, forKey: "settings.requireBiometricsForCard")

            #expect(AppSettings(defaults: defaults).requireBiometricsForCard == false)
        }
    }

    @Test func changesArePersisted() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.requireBiometricsForCard = false

            #expect(AppSettings(defaults: defaults).requireBiometricsForCard == false)
        }
    }
}

@MainActor
struct AppSettingsAppearanceTests {
    @Test func defaultsToFollowingTheSystem() {
        withDefaults { defaults in
            #expect(AppSettings(defaults: defaults).appearance == .system)
        }
    }

    @Test func changesArePersisted() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.appearance = .dark

            #expect(AppSettings(defaults: defaults).appearance == .dark)
        }
    }

    /// A value written by an older build, or by hand, must not leave the app
    /// with no appearance at all.
    @Test func anUnrecognisedStoredValueFallsBackToTheSystem() {
        withDefaults { defaults in
            defaults.set("solarized", forKey: "settings.appearance")

            #expect(AppSettings(defaults: defaults).appearance == .system)
        }
    }
}

@MainActor
struct AppSettingsChannelTests {
    /// nil means "never chosen", which is what lets the first read seed from
    /// the member's school. An empty set would mean "deliberately unfollowed
    /// everything" — a different thing entirely.
    @Test func startsAsNilRatherThanEmpty() {
        withDefaults { defaults in
            #expect(AppSettings(defaults: defaults).subscribedChannels == nil)
        }
    }

    /// The first toggle applies to the seed, not to an empty set — otherwise
    /// following one channel would silently unfollow the defaults.
    @Test func theFirstChangeIsAppliedOnTopOfTheSeed() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let nus = try #require(Channel.all.first { $0.id == "nus" })

            settings.setSubscribed(true, channel: nus, defaultingTo: ["all", "freshmen"])

            #expect(settings.subscribedChannels == ["all", "freshmen", "nus"])
        }
    }

    @Test func unfollowingRemovesOnlyThatChannel() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let all = try #require(Channel.all.first { $0.id == "all" })

            settings.setSubscribed(false, channel: all, defaultingTo: ["all", "freshmen"])

            #expect(settings.subscribedChannels == ["freshmen"])
        }
    }

    /// Once a choice exists it is no longer nil, so later reads stop seeding.
    @Test func choicesArePersistedAndStopTheSeeding() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let nus = try #require(Channel.all.first { $0.id == "nus" })
            settings.setSubscribed(true, channel: nus, defaultingTo: ["all"])

            #expect(AppSettings(defaults: defaults).subscribedChannels == ["all", "nus"])
        }
    }

    /// Unfollowing everything is a real state and must not read as "never
    /// chosen" on the next launch.
    @Test func unfollowingEverythingPersistsAsAnEmptySetNotNil() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let all = try #require(Channel.all.first { $0.id == "all" })

            settings.setSubscribed(false, channel: all, defaultingTo: ["all"])

            #expect(AppSettings(defaults: defaults).subscribedChannels == [])
        }
    }
}
