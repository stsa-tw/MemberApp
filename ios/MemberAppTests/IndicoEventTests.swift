import Foundation
import Testing

@testable import MemberApp

private func makeEvent(
    id: String = "10",
    title: String = "工作坊",
    location: String? = "i2Hub",
    room: String? = "#04-32",
    description: String? = nil,
    type: String? = "conference"
) throws -> IndicoEvent {
    var fields: [String] = [
        #""id": \#(id)"#,
        #""title": "\#(title)""#,
        #""startDate": {"date": "2026-08-15", "time": "13:30:00", "tz": "Asia/Singapore"}"#,
        #""endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}"#,
    ]
    if let location { fields.append(#""location": "\#(location)""#) }
    if let room { fields.append(#""room": "\#(room)""#) }
    if let description { fields.append(#""description": "\#(description)""#) }
    if let type { fields.append(#""type": "\#(type)""#) }

    let json = "{\(fields.joined(separator: ","))}"
    return try JSONDecoder().decode(IndicoEvent.self, from: Data(json.utf8))
}

struct IndicoEventDecodingTests {
    /// Indico has emitted `id` as both a JSON string and a JSON number across
    /// versions, and the app keys on it either way.
    @Test func acceptsANumericID() throws {
        #expect(try makeEvent(id: "10").id == "10")
    }

    @Test func acceptsAStringID() throws {
        #expect(try makeEvent(id: #""10""#).id == "10")
    }

    /// Indico splits a moment into date, time and tz instead of emitting
    /// ISO 8601, so the parse is hand-rolled and worth pinning.
    @Test func buildsDatesFromIndicoSplitMomentsInTheStatedTimeZone() throws {
        let event = try makeEvent()

        var calendar = Calendar(identifier: .gregorian)
        let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
        calendar.timeZone = singapore
        let expectedStart = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 15, hour: 13, minute: 30)))

        #expect(event.start == expectedStart)
        #expect(event.end.timeIntervalSince(event.start) == 2 * 60 * 60)
        #expect(event.timeZone == singapore)
    }

    /// An unparseable moment falls back to `.distantPast` rather than throwing,
    /// so one malformed event cannot take down the whole feed.
    @Test func anUnparseableDateFallsBackInsteadOfFailingTheDecode() throws {
        let json = """
        {"id": 1, "title": "x",
         "startDate": {"date": "not-a-date", "time": "13:30:00", "tz": "Asia/Singapore"},
         "endDate": {"date": "2026-08-15", "time": "15:30:00", "tz": "Asia/Singapore"}}
        """
        let event = try JSONDecoder().decode(IndicoEvent.self, from: Data(json.utf8))

        #expect(event.start == .distantPast)
    }

    @Test func aMissingDescriptionDecodesAsEmptyRatherThanThrowing() throws {
        #expect(try makeEvent(description: nil).summary.isEmpty)
    }
}

struct IndicoEventSummaryTests {
    /// Descriptions arrive as HTML. The detail screen lays out plain
    /// paragraphs, so block tags become breaks and everything else is dropped.
    @Test func blockTagsBecomeLineBreaks() throws {
        let event = try makeEvent(description: "<p>第一段</p><p>第二段</p>")

        #expect(event.summary == "第一段\n第二段")
    }

    /// Indico and the CDN in front of it both emit numeric entities; `&#160;`
    /// lands as a non-breaking space, which is normalised so it does not read as
    /// a different character than `&nbsp;` would have.
    @Test func decodesNumericEntities() throws {
        let event = try makeEvent(description: "A&#160;B &#x4E2D;")
        #expect(event.summary == "A B 中")
    }

    @Test func inlineTagsAreStrippedWithoutLeavingAGap() throws {
        let event = try makeEvent(description: "報名<strong>截止</strong>了")

        #expect(event.summary == "報名截止了")
    }

    @Test func entitiesAreDecoded() throws {
        let event = try makeEvent(description: "Slasify &amp; SLI &ldquo;工作坊&rdquo;")

        #expect(event.summary == "Slasify & SLI “工作坊”")
    }

    /// Dropping tags leaves runs of blank lines behind; they collapse so the
    /// detail screen does not show a gap where a `<div>` used to be.
    @Test func runsOfBlankLinesCollapse() throws {
        let event = try makeEvent(description: "<div>一</div><br><br><br><div>二</div>")

        #expect(event.summary == "一\n\n二")
    }
}

struct IndicoEventPlaceTests {
    @Test func joinsVenueAndRoom() throws {
        #expect(try makeEvent().place == "i2Hub · #04-32")
    }

    /// Indico leaves either field blank, so whichever is present is used alone.
    @Test func usesWhicheverFieldIsPresent() throws {
        #expect(try makeEvent(room: nil).place == "i2Hub")
        #expect(try makeEvent(location: nil).place == "#04-32")
    }

    /// Blank is not the same as absent in Indico's export — a whitespace-only
    /// field must not render as a stray separator.
    @Test func treatsWhitespaceOnlyFieldsAsAbsent() throws {
        #expect(try makeEvent(room: "   ").place == "i2Hub")
        #expect(try makeEvent(location: "  ", room: " ").place == nil)
    }

    @Test func isNilWhenNeitherFieldIsPresent() throws {
        #expect(try makeEvent(location: nil, room: nil).place == nil)
    }
}

/// Organisers decorate Indico titles freely, and the app strips that at decode
/// time so every screen gets the same clean string.
///
/// The digit cases are the ones that matter: `Unicode.Scalar.Properties.isEmoji`
/// is true for plain digits and for `#`/`*`, so the naive test would quietly eat
/// the year out of "2026 STSA".
struct IndicoEventTitleTests {
    private func title(_ raw: String) throws -> String {
        try makeEvent(title: raw).title
    }

    @Test func dropsATrailingEmoji() throws {
        #expect(try title("2026 STSA Boba Chat｜Back to School Edition 🧋")
            == "2026 STSA Boba Chat｜Back to School Edition")
    }

    @Test func dropsARunOfThem() throws {
        #expect(try title("2026 STSA 中秋烤肉趴 🌕🔥") == "2026 STSA 中秋烤肉趴")
    }

    @Test func closesTheGapLeftInTheMiddle() throws {
        #expect(try title("STSA 🧋 Boba Chat") == "STSA Boba Chat")
    }

    @Test func doesNotEatTheYear() throws {
        #expect(try title("2026 STSA Career Talk") == "2026 STSA Career Talk")
    }

    @Test func doesNotEatHashesOrAsterisks() throws {
        #expect(try title("Room #04-32 *額滿*") == "Room #04-32 *額滿*")
    }

    @Test func dropsAJoinedSequenceWhole() throws {
        #expect(try title("家庭日 👨‍👩‍👧‍👦") == "家庭日")
    }

    @Test func dropsAFlag() throws {
        #expect(try title("台灣之夜 🇹🇼") == "台灣之夜")
    }

    /// Pinning a behaviour rather than an ideal: a title with nothing left is
    /// worse than one that kept its decoration.
    @Test func keepsATitleThatWasNothingButEmoji() throws {
        #expect(try title("🎉🎉") == "🎉🎉")
    }
}
