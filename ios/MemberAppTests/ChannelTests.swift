import Testing

@testable import MemberApp

struct ChannelCatalogueTests {
    /// `id` is the persistence key written to UserDefaults. A duplicate would
    /// silently merge two channels' subscription state.
    @Test func idsAreUnique() {
        let ids = Channel.all.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    /// A school channel is matched to a member by `Profile.school`, so its
    /// `school` value has to be one of the strings that property can return.
    @Test func schoolChannelsUseTheSameAbbreviationsProfileProduces() {
        let schools = Channel.all.compactMap(\.school)

        #expect(Set(schools).isSubset(of: ["NUS", "NTU", "SMU", "SUTD"]))
    }

    /// Schools are identified by their abbreviation rather than an SF Symbol —
    /// the general-purpose channels are the ones carrying symbols.
    @Test func schoolChannelsCarryABadgeInsteadOfASymbol() {
        for channel in Channel.all where channel.school != nil {
            #expect(channel.symbol == nil)
            #expect(channel.badge.isEmpty == false)
        }
    }
}

struct ChannelDefaultSubscriptionTests {
    @Test func everyoneStartsWithTheAllMembersAndFreshmenChannels() {
        #expect(Channel.defaultSubscriptions(school: nil) == ["all", "freshmen"])
    }

    @Test func aKnownSchoolAddsItsOwnChannel() {
        #expect(Channel.defaultSubscriptions(school: "NUS") == ["all", "freshmen", "nus"])
        #expect(Channel.defaultSubscriptions(school: "NTU") == ["all", "freshmen", "ntu"])
        #expect(Channel.defaultSubscriptions(school: "SMU") == ["all", "freshmen", "smu"])
    }

    /// `Profile.school` can return "SUTD", but the catalogue has no SUTD
    /// channel, so a SUTD member seeds with the two general channels only. That
    /// is the current intent — adding the channel is what changes this, and
    /// this expectation is what will tell you to update it.
    @Test func aSchoolWithNoChannelYetSeedsTheGeneralChannelsOnly() {
        #expect(Channel.defaultSubscriptions(school: "SUTD") == ["all", "freshmen"])
    }

    @Test func anUnrecognisedSchoolIsIgnoredRatherThanAddingNothingSilentlyWrong() {
        #expect(Channel.defaultSubscriptions(school: "MIT") == ["all", "freshmen"])
    }
}
