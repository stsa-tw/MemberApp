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

        title = try container.decode(String.self, forKey: .title)

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

        // Collapse the runs of blank lines that dropping tags leaves behind.
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
