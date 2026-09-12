import Foundation
import Testing

@testable import MemberApp

/// The rule that turns a scanned member card into exactly one registration.
///
/// The mirror of Android's `CheckinMatchingTest`: two doors that disagree about
/// which row a scan means would record the same event twice over.
@MainActor
struct CheckinMatchingTests {
    private func entry(
        id: Int,
        formID: Int = 17,
        email: String = "member@u.nus.edu",
        state: String = "complete",
        checkedIn: Bool = false
    ) -> CheckinStore.Entry {
        CheckinStore.Entry(
            formID: formID,
            registration: CheckinRegistration(
                id: id,
                eventID: 12,
                formID: formID,
                fullName: "陳小明",
                email: email,
                state: state,
                checkedIn: checkedIn,
                answers: []
            )
        )
    }

    @Test func findsTheRegistrationForAnAddress() {
        let entries = [entry(id: 1, email: "other@u.nus.edu"), entry(id: 2)]
        #expect(CheckinStore.match(email: "member@u.nus.edu", in: entries)?.id == 2)
    }

    /// Indico lowercases addresses and authentik does not, so a member whose
    /// account address is capitalised would otherwise silently fail to match.
    @Test func ignoresCaseAndSurroundingSpace() {
        let entries = [entry(id: 2)]
        #expect(CheckinStore.match(email: " Member@U.NUS.edu ", in: entries)?.id == 2)
    }

    /// Someone who registered under a different address is a miss, not a wrong
    /// match — the screen says so and the staffer scans their ticket instead.
    @Test func doesNotGuessWhenNothingMatches() {
        let entries = [entry(id: 1, email: "someone@u.nus.edu")]
        #expect(CheckinStore.match(email: "member@u.nus.edu", in: entries) == nil)
    }

    @Test func ignoresAnEmptyAddress() {
        #expect(CheckinStore.match(email: "", in: [entry(id: 1, email: "")]) == nil)
    }

    /// Withdrawing and registering again leaves the old row on the list, and
    /// Indico allows the second registration *because* the first is withdrawn.
    /// The live one is the useful answer.
    @Test func prefersAnAdmissibleRegistration() {
        let entries = [entry(id: 1, state: "withdrawn"), entry(id: 2)]
        #expect(CheckinStore.match(email: "member@u.nus.edu", in: entries)?.id == 2)
    }

    /// Two live rows for one address — a manager adding somebody who had already
    /// registered is warned, not stopped. Whichever one was used to admit them
    /// is the one a second scan must find, or the door offers to check the same
    /// person in again and counts one arrival twice.
    @Test func prefersTheCopyAlreadyCheckedIn() {
        let entries = [entry(id: 1), entry(id: 2, checkedIn: true)]
        #expect(CheckinStore.match(email: "member@u.nus.edu", in: entries)?.id == 2)
    }

    /// A withdrawn row that happens to be checked in is still withdrawn.
    @Test func doesNotPreferACheckedInCancellation() {
        let entries = [entry(id: 1, state: "withdrawn", checkedIn: true), entry(id: 2)]
        #expect(CheckinStore.match(email: "member@u.nus.edu", in: entries)?.id == 2)
    }
}

/// What each of Indico's registration states means at a door.
struct CheckinRegistrationStateTests {
    private func registration(state: String) -> CheckinRegistration {
        CheckinRegistration(
            id: 1, eventID: 12, formID: 17, fullName: "陳小明",
            email: "member@u.nus.edu", state: state, checkedIn: false, answers: []
        )
    }

    /// `unpaid` is admissible on purpose — payment is not the door's problem,
    /// and Indico's own app admits them too.
    @Test func admitsCompleteAndUnpaid() {
        #expect(registration(state: "complete").isAdmissible)
        #expect(registration(state: "unpaid").isAdmissible)
        #expect(!registration(state: "pending").isAdmissible)
        #expect(!registration(state: "withdrawn").isAdmissible)
    }

    /// Cancelled is the narrower word: `pending` is not admissible either, but
    /// that person may yet be approved, so they stay in the count.
    @Test func countsOnlyWithdrawnAndRejectedAsCancelled() {
        #expect(registration(state: "withdrawn").isCancelled)
        #expect(registration(state: "rejected").isCancelled)
        #expect(!registration(state: "pending").isCancelled)
        #expect(!registration(state: "complete").isCancelled)
    }

    /// The ordinary case says nothing; a row that announced "已完成" on every
    /// line would be noise.
    @Test func namesOnlyTheStatesWorthSaying() {
        #expect(registration(state: "complete").stateDescription == nil)
        #expect(registration(state: "withdrawn").stateDescription != nil)
        #expect(registration(state: "unpaid").stateDescription != nil)
    }
}
