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

/// One registrant, as Indico's check-in API describes them.
struct CheckinRegistration: Equatable {
    let id: Int
    let fullName: String
    let email: String
    /// Indico's own word: `complete`, `pending`, `withdrawn`, `unpaid`, `rejected`.
    let state: String
    let checkedIn: Bool
    /// Everything they filled in, flattened into the same rows the member sees
    /// on the event screen.
    let answers: [RegistrationAnswer]

    var isComplete: Bool { state == "complete" }
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
            fullName: raw["full_name"] as? String ?? "",
            email: (raw["email"] as? String ?? "").lowercased(),
            state: raw["state"] as? String ?? "",
            checkedIn: raw["checked_in"] as? Bool ?? false,
            answers: answers(from: raw["registration_data"] as? [[String: Any]] ?? [])
        )
    }

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
