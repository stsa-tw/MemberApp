import Foundation
import Testing

@testable import MemberApp

/// Transcribed from `CheckinRegistrationSchema` — `registration_data` is a list
/// of sections, each holding fields whose `data` is the *stored* value with the
/// captions alongside in `choices`.
private let payload = """
{
  "id": 42,
  "full_name": "楊晨諺",
  "email": "Kimi@example.com",
  "state": "complete",
  "checked_in": false,
  "tags": [
    {"id": 7, "title": "素食", "color": "green"},
    {"id": 9, "title": "講者", "color": "violet"},
    {"id": 11, "title": "   ", "color": "red"}
  ],
  "registration_data": [
    {
      "id": 1, "position": 1, "title": "個人資料", "description": "",
      "fields": [
        {"id": 10, "position": 1, "title": "中文姓名", "input_type": "text", "data": "楊晨諺"},
        {"id": 11, "position": 2, "title": "科系", "input_type": "text", "data": "CS"}
      ]
    },
    {
      "id": 2, "position": 2, "title": "飲料", "description": "",
      "fields": [
        {"id": 20, "position": 1, "title": "要喝什麼飲料？", "input_type": "single_choice",
         "data": {"c2": 1},
         "choices": [{"id": "c1", "caption": "烏龍鮮奶"}, {"id": "c2", "caption": "招牌珍奶"}]},
        {"id": 21, "position": 2, "title": "加料", "input_type": "multi_choice",
         "data": {"t2": 1, "t1": 1},
         "choices": [{"id": "t1", "caption": "珍珠"}, {"id": "t2", "caption": "椰果"},
                     {"id": "t3", "caption": "布丁"}]},
        {"id": 22, "position": 3, "title": "素食", "input_type": "bool", "data": true},
        {"id": 23, "position": 4, "title": "沒填的欄位", "input_type": "text", "data": ""}
      ]
    }
  ]
}
"""

struct CheckinDecoderTests {
    private func decoded() throws -> CheckinRegistration {
        try #require(CheckinDecoder.one(Data(payload.utf8)))
    }

    @Test func readsWhoTheyAre() throws {
        let registration = try decoded()
        #expect(registration.id == 42)
        #expect(registration.fullName == "楊晨諺")
        #expect(registration.isComplete)
        #expect(registration.checkedIn == false)
    }

    /// The email is the join between a scanned member card and this
    /// registration, so it is lowercased on the way in — Indico and MembershipAPI
    /// do not agree on case.
    @Test func lowercasesTheEmail() throws {
        #expect(try decoded().email == "kimi@example.com")
    }

    @Test func resolvesASingleChoiceToItsCaption() throws {
        let answers = try decoded().answers
        #expect(answers.first { $0.label == "要喝什麼飲料？" }?.value == "招牌珍奶")
    }

    /// Stored as a dictionary, so the order it iterates in is not the order the
    /// organiser wrote the options — the captions come back in the form's order.
    @Test func keepsMultiChoiceInTheOrderTheFormLists() throws {
        let answers = try decoded().answers
        #expect(answers.first { $0.label == "加料" }?.value == "珍珠\n椰果")
    }

    @Test func rendersABooleanAsAWord() throws {
        let answers = try decoded().answers
        #expect(answers.first { $0.label == "素食" }?.value == "是")
    }

    @Test func dropsAFieldWithNoAnswer() throws {
        let answers = try decoded().answers
        #expect(answers.contains { $0.label == "沒填的欄位" } == false)
    }

    @Test func attachesEachFieldToItsSection() throws {
        let answers = try decoded().answers
        #expect(answers.first { $0.label == "科系" }?.section == "個人資料")
        #expect(answers.first { $0.label == "素食" }?.section == "飲料")
    }

    /// A field type nobody anticipated still shows something rather than
    /// vanishing — a staffer reading a raw value beats a row that is not there.
    @Test func fallsBackRatherThanDroppingAnUnknownShape() {
        #expect(CheckinDecoder.display(inputType: "sessions", data: ["早上", "下午"], choices: []) == "早上\n下午")
    }

    /// Tags are the organiser's own marks on a registration, and the door reads
    /// them out loud — 素食 decides what somebody is handed at the desk.
    @Test func readsTheOrganisersTags() throws {
        let tags = try decoded().tags
        #expect(tags.map(\.title) == ["素食", "講者"])
        #expect(tags.first?.color == "green")
    }

    /// An untitled tag would draw as an empty chip, which reads as a rendering
    /// bug rather than as the empty tag it is.
    @Test func dropsATagWithNoTitle() throws {
        #expect(try decoded().tags.contains { $0.id == 11 } == false)
    }

    /// The search behind 手動報到: a 幹部 types a name, an address, or the tag
    /// the organiser sorted people by.
    @Test func searchesNameEmailAndTags() throws {
        let registration = try decoded()
        #expect(registration.matches("楊"))
        #expect(registration.matches("KIMI@example"))
        #expect(registration.matches("素食"))
        #expect(registration.matches("蛋奶素") == false)
        // An empty field hides nobody.
        #expect(registration.matches("  "))
    }

    @Test func readsAList() {
        let json = "[\(payload)]"
        #expect(CheckinDecoder.list(Data(json.utf8)).count == 1)
    }
}
