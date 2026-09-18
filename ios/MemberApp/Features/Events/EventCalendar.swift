import EventKit
import EventKitUI
import SwiftUI

/// Putting an Indico event into the phone's own calendar.
///
/// Write-only access, which is genuinely all this does. `requestWriteOnlyAccess`
/// asks for permission to *create* events and none to read them, so the prompt a
/// member sees says "add events" rather than "access your calendar", and the app
/// never gains the ability to look at what else is in there. That is also
/// exactly what `EKEventEditViewController` needs, so there is no reason to ask
/// for more — and under the security rules in CONTRIBUTING, "nothing leaves the
/// device" cuts both ways: nothing comes off it either.
///
/// Deliberately not a silent `store.save(_:span:)`. Writing into somebody's
/// calendar without showing them what lands there, and into whichever calendar
/// happens to be the default, is the kind of thing that ends up in a shared work
/// calendar. The system sheet is one extra tap and it shows the whole event,
/// lets them pick the calendar and lets them cancel.
enum EventCalendar {
    /// Whether the member has let the app add events, asking if they have not
    /// been asked yet.
    ///
    /// The store is handed back rather than made fresh at the point of use: the
    /// grant belongs to *this* `EKEventStore`, and `EKEventEditViewController`
    /// must be given the same one or it has no access to the calendars it is
    /// about to offer.
    static func openStore() async -> EKEventStore? {
        let store = EKEventStore()
        // The only documented reason this throws is that the prompt could not be
        // shown, which for the member is the same story as a refusal: the app
        // cannot write to their calendar and Settings is where that changes.
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return nil }
        return store
    }
}

/// The system's own new-event sheet, filled in from an `IndicoEvent`.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let event: IndicoEvent
    let store: EKEventStore
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = draft()
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    private func draft() -> EKEvent {
        let draft = EKEvent(eventStore: store)
        draft.title = event.title
        draft.startDate = event.start
        draft.endDate = event.end
        // The event's own zone, not the reader's, for the reason
        // `IndicoEvent.schedule` prints it that way — except here it also
        // survives: a member who saves a Taipei event and then flies somewhere
        // gets a calendar entry that still names the hour the organiser
        // announced.
        draft.timeZone = event.timeZone
        // The full line, room included — Calendar geocodes this field itself to
        // offer travel time, and shows the text to whoever opens the entry,
        // which is the half that wants the floor number.
        draft.location = event.locationLine
        // The Indico page rather than the description. `summary` is a flattened
        // HTML blob that can run to several screens, and the thing a member
        // opening the calendar entry a month later actually wants is the way
        // back to the event — where the description is, in its readable form,
        // along with anything that changed since.
        draft.url = event.url
        // `defaultCalendarForNewEvents` is nil on a device with no writable
        // calendar; leaving `calendar` unset lets the sheet ask instead of
        // crashing on save.
        if let calendar = store.defaultCalendarForNewEvents {
            draft.calendar = calendar
        }
        return draft
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        /// Saved, cancelled or deleted all end the same way here. The sheet does
        /// not dismiss itself, so this is what closes it — and there is nothing
        /// to report either way: the member just watched it happen.
        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onFinish()
        }
    }
}
