import Foundation
import Testing

@testable import MemberApp

/// Built with `Calendar.current`, matching what `hasExpired(on:)` uses, so these
/// stay stable wherever they run.
private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

/// `logo` is an asset symbol, so it is borrowed from a real sample rather than
/// constructed — nothing here depends on which logo it is.
private func makeDeal(expires: DateComponents?) -> Deal {
    Deal(logo: Deal.samples[0].logo,
         brand: "Test Brand",
         summary: "",
         terms: [],
         expires: expires)
}

struct DealExpiryTests {
    @Test func hasNotExpiredBeforeTheEndDate() {
        let deal = makeDeal(expires: DateComponents(year: 2026, month: 6, day: 30))

        #expect(deal.hasExpired(on: date(2026, 6, 29)) == false)
    }

    @Test func hasExpiredAfterTheEndDate() {
        let deal = makeDeal(expires: DateComponents(year: 2026, month: 6, day: 30))

        #expect(deal.hasExpired(on: date(2026, 7, 1)))
    }

    /// The end date resolves to midnight at its start, so the offer counts as
    /// expired during the day it names. `expiryLabel` renders that same date as
    /// "至 2026/6/30", which reads as inclusive. Pinned as current behaviour: if
    /// the intent is to keep the code usable all day, the fix is in
    /// `hasExpired(on:)` and this expectation flips.
    @Test func theEndDateItselfCountsAsExpiredFromMidnight() {
        let deal = makeDeal(expires: DateComponents(year: 2026, month: 6, day: 30))

        #expect(deal.hasExpired(on: date(2026, 6, 30, hour: 12)))
    }

    /// HSBC's offer has no stated end date, and an absent date must never read
    /// as "expired" — that would hide a live partnership.
    @Test func anOfferWithNoEndDateNeverExpires() {
        let deal = makeDeal(expires: nil)

        #expect(deal.hasExpired(on: date(2099, 1, 1)) == false)
    }
}

struct DealLabelTests {
    @Test func expiryLabelRendersTheStatedDate() {
        let deal = makeDeal(expires: DateComponents(year: 2026, month: 6, day: 30))

        #expect(deal.expiryLabel == "至 2026/6/30")
    }

    @Test func expiryLabelIsAbsentWhenThereIsNoEndDate() {
        #expect(makeDeal(expires: nil).expiryLabel == nil)
    }

    /// A partial `DateComponents` cannot be rendered honestly, so it is omitted
    /// rather than printed with a missing field.
    @Test func expiryLabelIsAbsentWhenTheDateIsIncomplete() {
        let deal = makeDeal(expires: DateComponents(year: 2026, month: 6))

        #expect(deal.expiryLabel == nil)
    }
}

struct DealSampleTests {
    /// `id` is the brand name, and the deals list is keyed on it.
    @Test func sampleBrandsAreUnique() {
        let ids = Deal.samples.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    /// HSBC is an information partnership, not a discount — it is the reason
    /// `code` and `headline` are optional, so it stands in for that whole shape.
    @Test func anInformationPartnerCarriesNoCodeOrHeadline() throws {
        let hsbc = try #require(Deal.samples.first { $0.brand.contains("HSBC") })

        #expect(hsbc.code == nil)
        #expect(hsbc.headline == nil)
        #expect(hsbc.link != nil)
        #expect(hsbc.linkTitle != nil)
    }
}
