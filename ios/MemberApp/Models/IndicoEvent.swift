import Foundation

/// One event from Indico's category export.
///
/// Source: `GET https://event.stsa.tw/export/categ/0.json`, which answers
/// anonymously — reading events needs no token and no API key.
struct IndicoEvent: Identifiable, Hashable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var timeZone: TimeZone
    var location: String?
    var room: String?
    var address: String?
    var summary: String
    var url: URL?
    var type: String?

    var isUpcoming: Bool { end >= Date() }

    /// `location` is the venue name, `room` the room within it. Indico leaves
    /// either blank, so join whatever is there.
    var place: String? {
        let parts = [location, room].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Small uppercase label above the title on the detail hero.
    var kicker: String {
        switch type {
        case "conference": String(localized: "活動")
        case "meeting": String(localized: "聚會")
        case "lecture": String(localized: "講座")
        default: String(localized: "活動")
        }
    }
}

// MARK: - Title

extension String {
    /// Drops decorative emoji, and the whitespace they leave behind.
    ///
    /// Organisers type them into Indico titles freely (🧋, 🌕🔥), which reads fine
    /// on a web page with one event per screen and badly in a list of dense
    /// two-line rows, where they are the loudest thing in the column and carry no
    /// information the title does not already give.
    ///
    /// Deliberately not `isEmoji` alone: that property is true for plain digits,
    /// `#` and `*`, so a title like "2026 STSA" would lose its year. The pairing
    /// below is the standard test — a multi-scalar cluster whose base is emoji,
    /// or a single scalar that *presents* as emoji.
    var withoutEmoji: String {
        let stripped = filter { character in
            guard let first = character.unicodeScalars.first else { return true }
            let isEmoji = character.unicodeScalars.count > 1
                ? first.properties.isEmoji
                : first.properties.isEmojiPresentation
            return !isEmoji
        }

        let tidied = stripped
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([｜|·,、])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // A title that was nothing but emoji is still better than no title.
        return tidied.isEmpty ? self : tidied
    }
}

// MARK: - Decoding

extension IndicoEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, location, room, address, description, url, type
    }

    /// Indico splits a moment into date, time and tz rather than emitting ISO 8601.
    private struct IndicoMoment: Decodable {
        let date: String
        let time: String
        let tz: String

        var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

        var value: Date {
            var formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.date(from: "\(date) \(time)") ?? .distantPast
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Indico has emitted `id` as both a string and a number across versions.
        if let string = try? container.decode(String.self, forKey: .id) {
            id = string
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }

        title = try container.decode(String.self, forKey: .title).withoutEmoji

        let startMoment = try container.decode(IndicoMoment.self, forKey: .startDate)
        let endMoment = try container.decode(IndicoMoment.self, forKey: .endDate)
        start = startMoment.value
        end = endMoment.value
        timeZone = startMoment.timeZone

        location = try container.decodeIfPresent(String.self, forKey: .location)
        room = try container.decodeIfPresent(String.self, forKey: .room)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        url = try container.decodeIfPresent(String.self, forKey: .url).flatMap(URL.init(string:))

        // Descriptions are HTML with inline images and relative attachment URLs.
        // The detail screen lays out plain paragraphs, and the full rich version
        // is one tap away on Indico, so flatten rather than render.
        summary = (try container.decodeIfPresent(String.self, forKey: .description) ?? "")
            .plainTextFromHTML
    }
}

// MARK: - HTML flattening

private extension String {
    var decodingNumericEntities: String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else { return self }

        var result = ""
        var last = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let whole = Range(match.range, in: self),
                  let flagRange = Range(match.range(at: 1), in: self),
                  let digitsRange = Range(match.range(at: 2), in: self)
            else { continue }

            let radix = self[flagRange].isEmpty ? 10 : 16
            guard let value = UInt32(self[digitsRange], radix: radix),
                  let scalar = Unicode.Scalar(value)
            else { continue }

            result += self[last..<whole.lowerBound]
            result.unicodeScalars.append(scalar)
            last = whole.upperBound
        }
        return result + self[last...]
    }
}

private extension String {
    var plainTextFromHTML: String {
        var text = self
        // Block-level tags become paragraph breaks before everything else is dropped.
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</li>",
                                         with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&rsquo;": "’", "&ldquo;": "“", "&rdquo;": "”"]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }

        // Numeric entities, which Indico and the CDN in front of it both emit —
        // `&#160;` for a non-breaking space is the common one.
        text = text.decodingNumericEntities
        // &nbsp; already maps to a plain space above; its numeric spelling
        // should not behave differently just because it arrived as &#160;.
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")

        // Collapse the runs of blank lines that dropping tags leaves behind.
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
