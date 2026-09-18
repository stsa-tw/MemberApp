import Foundation

/// One answer a registrant gave on an event's registration form.
struct RegistrationAnswer: Identifiable, Equatable {
    /// Position in the form, which is the order Indico rendered them in.
    let id: Int
    /// The form section it sits under, when the form has more than one.
    let section: String?
    let label: String
    let value: String
}

/// A tag a manager has put on a registration, as Indico's `RegistrationTag`.
///
/// Read here and never written: the check-in API hands tags over with the
/// registration and has no endpoint that changes them, which is the right way
/// round. A tag is the organiser's note to the door — 素食, 講者, 待補款 — and
/// the desk is who needs to read it, not who decides it.
struct RegistrationTag: Identifiable, Equatable {
    let id: Int
    let title: String
    /// A Semantic UI colour *name* — `red`, `teal`, `grey` — not a hex value,
    /// whatever Indico's own column comment says: the field behind it is a
    /// `SUIColorPickerField`, whose choices are `get_sui_colors()`.
    let color: String
}

/// One registrant, as Indico's check-in API describes them.
struct CheckinRegistration: Equatable {
    let id: Int
    /// The event and form this registration belongs to. Needed to address the
    /// check-in PATCH, and to refuse a ticket scanned at the wrong door — the
    /// ticket endpoint is not scoped to an event, so Indico will happily resolve
    /// a ticket for another event the same staffer manages.
    let eventID: Int
    let formID: Int
    let fullName: String
    let email: String
    /// Indico's own word: `complete`, `pending`, `withdrawn`, `unpaid`, `rejected`.
    let state: String
    let checkedIn: Bool
    /// Everything they filled in, flattened into the same rows the member sees
    /// on the event screen.
    let answers: [RegistrationAnswer]
    /// The organiser's own marks on this registration, in Indico's order.
    let tags: [RegistrationTag]
    /// When they came through the door, when they have.
    ///
    /// Indico keeps the original `checked_in_dt` through a repeat PATCH, so this
    /// is the first arrival rather than the last time somebody scanned them.
    let checkedInAt: Date?
    /// When the registration was made.
    ///
    /// Nothing draws it yet. It is carried because the list endpoint hands it
    /// over for free and a roster in arrival order is the obvious next use —
    /// today's sort is by name, which is a different question.
    let registrationDate: Date?

    /// Spelled out rather than left to the memberwise initialiser so the two
    /// timestamps can default: they are absent from most fixtures, and every
    /// caller that does not care should not have to say so.
    init(
        id: Int,
        eventID: Int,
        formID: Int,
        fullName: String,
        email: String,
        state: String,
        checkedIn: Bool,
        answers: [RegistrationAnswer],
        tags: [RegistrationTag] = [],
        checkedInAt: Date? = nil,
        registrationDate: Date? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.formID = formID
        self.fullName = fullName
        self.email = email
        self.state = state
        self.checkedIn = checkedIn
        self.answers = answers
        self.tags = tags
        self.checkedInAt = checkedInAt
        self.registrationDate = registrationDate
    }

    var isComplete: Bool { state == "complete" }

    /// Whether this person may be admitted at all.
    ///
    /// A withdrawn or rejected registration still comes back in the roster, and
    /// recording attendance for one would put someone in the room the organiser
    /// removed. `unpaid` is admissible — payment is not the door's problem, and
    /// Indico's own app checks those in too.
    var isAdmissible: Bool { state == "complete" || state == "unpaid" }

    /// Withdrawn or rejected: still on Indico's list, and not somebody the door
    /// is waiting for.
    ///
    /// Indico draws the same line in the same place — `active_registration_count`
    /// is every registration that is not one of these two — so leaving them out
    /// of the count here is what makes the number on the roster mean the same
    /// thing as the number on Indico's own management page.
    var isCancelled: Bool { state == "withdrawn" || state == "rejected" }

    /// Whether this registrant answers to what a 幹部 typed.
    ///
    /// Name, email *and* tags. The first two because a staffer reading a name off
    /// a screen and one reading an address back to a member are the same errand;
    /// tags because the other question a desk asks of a list is "who is on the
    /// coach", and the organiser already answered it by tagging them.
    ///
    /// An empty needle matches everyone, so a search field that has not been
    /// typed into hides nobody.
    func matches(_ needle: String) -> Bool {
        let wanted = needle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return true }
        return fullName.lowercased().contains(wanted)
            || email.lowercased().contains(wanted)
            || tags.contains { $0.title.lowercased().contains(wanted) }
    }

    /// The order a roster reads in, on every screen that draws one.
    ///
    /// Not checked in first — the people a door is still waiting for —
    /// alphabetical inside each group so a name can be found by eye, and anyone
    /// who withdrew at the very bottom: kept visible, because "where did they
    /// go" is a question the list should answer, but they are nobody's next
    /// arrival.
    static func isOrderedBefore(_ a: CheckinRegistration, _ b: CheckinRegistration) -> Bool {
        if a.isCancelled != b.isCancelled { return b.isCancelled }
        if a.checkedIn != b.checkedIn { return b.checkedIn }
        return a.fullName.localizedCompare(b.fullName) == .orderedAscending
    }

    /// The state, said out loud, when it is worth saying. `complete` is the
    /// ordinary case and a row that announced it would only be noise.
    var stateDescription: String? {
        switch state {
        case "unpaid": String(localized: "未付款")
        case "pending": String(localized: "待審核")
        case "withdrawn": String(localized: "已退出")
        case "rejected": String(localized: "未通過")
        default: nil
        }
    }
}

/// Decodes `CheckinRegistrationSchema` and renders its raw answers.
///
/// The API hands back what was *stored*, not what Indico would show: a choice
/// field's `data` is a dictionary of choice id to quantity, and the captions live
/// beside it in `choices`. So the resolving that the member-facing summary page
/// did for us has to happen here instead. That is the trade — this side is
/// structured JSON with a documented shape, and worth the mapping.
enum CheckinDecoder {
    static func list(_ data: Data) -> [CheckinRegistration] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap(registration(from:))
    }

    static func one(_ data: Data) -> CheckinRegistration? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return registration(from: raw)
    }

    static func registration(from raw: [String: Any]) -> CheckinRegistration? {
        guard let id = raw["id"] as? Int else { return nil }
        return CheckinRegistration(
            id: id,
            eventID: raw["event_id"] as? Int ?? 0,
            formID: raw["regform_id"] as? Int ?? 0,
            fullName: raw["full_name"] as? String ?? "",
            email: (raw["email"] as? String ?? "").lowercased(),
            state: raw["state"] as? String ?? "",
            checkedIn: raw["checked_in"] as? Bool ?? false,
            answers: answers(from: raw["registration_data"] as? [[String: Any]] ?? []),
            tags: tags(from: raw["tags"] as? [[String: Any]] ?? []),
            checkedInAt: date(from: raw["checked_in_dt"]),
            registrationDate: date(from: raw["registration_date"])
        )
    }

    // MARK: - Tags

    /// Indico sorts them by title before it sends them, so the order is left
    /// alone. An untitled tag is dropped rather than drawn as an empty chip.
    static func tags(from raw: [[String: Any]]) -> [RegistrationTag] {
        raw.compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            let title = (item["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return RegistrationTag(id: id, title: title, color: item["color"] as? String ?? "")
        }
    }

    // MARK: - Timestamps

    /// marshmallow writes ISO 8601 with an offset, and includes fractional
    /// seconds only when the stored value happens to have them. Both spellings
    /// have to parse or half the timestamps silently come back nil.
    static func date(from raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        return isoWithFractionalSeconds.date(from: text) ?? isoWholeSeconds.date(from: text)
    }

    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoWholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Answers

    static func answers(from sections: [[String: Any]]) -> [RegistrationAnswer] {
        var answers: [RegistrationAnswer] = []

        for section in sections {
            let sectionTitle = (section["title"] as? String)?.trimmingCharacters(in: .whitespaces)
            for field in section["fields"] as? [[String: Any]] ?? [] {
                let label = (field["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let value = display(
                    inputType: field["input_type"] as? String ?? "",
                    data: field["data"],
                    choices: field["choices"] as? [[String: Any]] ?? []
                )
                guard !label.isEmpty, !value.isEmpty else { continue }

                answers.append(
                    RegistrationAnswer(
                        id: answers.count,
                        section: sectionTitle?.isEmpty == false ? sectionTitle : nil,
                        label: label,
                        value: value
                    )
                )
            }
        }
        return answers
    }

    /// Turns a stored value into something a human at a door can read.
    ///
    /// Covers what STSA's forms actually use. Anything else falls through to a
    /// plain description rather than being dropped — a staffer seeing a value
    /// they have to interpret beats a row that silently is not there.
    static func display(inputType: String, data: Any?, choices: [[String: Any]]) -> String {
        switch data {
        case let text as String:
            return text.trimmingCharacters(in: .whitespaces)

        case let flag as Bool:
            return flag ? String(localized: "是") : String(localized: "否")

        case let number as Int:
            return String(number)

        case let number as Double:
            return number == number.rounded() ? String(Int(number)) : String(number)

        // Single- and multi-choice both store `{choice id: quantity}`; the
        // captions are in `choices` alongside.
        case let picked as [String: Any]:
            let captions = Dictionary(
                uniqueKeysWithValues: choices.compactMap { choice -> (String, String)? in
                    guard let id = choice["id"] as? String,
                          let caption = choice["caption"] as? String
                    else { return nil }
                    return (id, caption)
                }
            )

            // Kept in the order the organiser listed them, not the order the
            // dictionary happens to iterate.
            let chosen = choices.compactMap { choice -> String? in
                guard let id = choice["id"] as? String, picked[id] != nil else { return nil }
                return captions[id]
            }
            return chosen.isEmpty ? "" : chosen.joined(separator: "\n")

        case let items as [Any]:
            return items.map { String(describing: $0) }.joined(separator: "\n")

        default:
            return ""
        }
    }
}
