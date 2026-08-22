import Testing

@testable import MemberApp

/// Indico answers a ticket request with a status code and little else, so this
/// mapping is the whole of what the app knows. The cases pin Indico's actual
/// behaviour rather than an ideal API:
///
/// - 403 covers "not registered", "registered but not yet complete" and
///   "tickets are switched off", all from `RHTicketDownload._check_access`.
///   They are deliberately collapsed, because they cannot be told apart.
/// - 404 would be a ticket format Indico cannot produce for this event.
///   Nothing to offer, same as 403.
///
/// The app asks for `ticket.pdf` rather than a Wallet pass because both of
/// Indico's Wallet endpoints currently answer 500 on this instance — see
/// `TicketStore`.
struct TicketOutcomeTests {
    private let pdf = "application/pdf"

    @Test func aPDFTicketIsAvailable() {
        #expect(TicketStore.outcome(status: 200, contentType: pdf) == .available)
    }

    @Test func contentTypeParametersDoNotBreakTheMatch() {
        #expect(TicketStore.outcome(status: 200, contentType: "\(pdf); charset=binary") == .available)
    }

    /// The important one. `URLSession` follows redirects, so a request whose
    /// authorization was rejected can come back as a 200 carrying Indico's login
    /// page. A 200 alone is not a ticket.
    @Test func htmlWithA200IsAFailureRatherThanATicket() {
        #expect(TicketStore.outcome(status: 200, contentType: "text/html; charset=utf-8") == .failed)
    }

    @Test func aMissingContentTypeIsAFailure() {
        #expect(TicketStore.outcome(status: 200, contentType: nil) == .failed)
    }

    @Test func aRejectedTokenAsksToLinkAgain() {
        #expect(TicketStore.outcome(status: 401, contentType: nil) == .needsLinking)
    }

    @Test func forbiddenMeansThereIsNothingToShow() {
        #expect(TicketStore.outcome(status: 403, contentType: nil) == .unavailable)
    }

    @Test func noTicketForThisFormMeansThereIsNothingToShow() {
        #expect(TicketStore.outcome(status: 404, contentType: nil) == .unavailable)
    }

    @Test func serverErrorsAreFailures() {
        #expect(TicketStore.outcome(status: 500, contentType: nil) == .failed)
    }

    @Test func aTransportFailureWithNoResponseIsAFailure() {
        #expect(TicketStore.outcome(status: 0, contentType: nil) == .failed)
    }
}
