import SwiftUI

/// One registrant as a list row: who they are, what state their registration is
/// in, the organiser's tags, and whether they have come through a door.
///
/// Shared by the roster on 幹部功能 and the door's name picker, which are the
/// same list read for two different reasons. They were two copies of this until
/// tags gave them a third thing to keep in step, and a row that shows a tag in
/// one list and not the other is worse than no tag at all — a 幹部 would learn
/// to trust whichever list they opened last.
///
/// Draws no horizontal inset: the roster sits in a card that owns its gutter and
/// the picker sits in a `List` that owns its own.
struct RegistrationRow: View {
    let registration: CheckinRegistration
    /// Marks the row as leading somewhere, which it does on the roster and does
    /// not in the picker — there, tapping a name is the whole sheet's purpose.
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: registration.fullName)
                    .font(.callout)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(verbatim: registration.email)
                        .lineLimit(1)
                    if let state = registration.stateDescription {
                        Text(state)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                RegistrationTagChips(tags: registration.tags)
            }
            Spacer(minLength: 8)

            if registration.checkedIn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("已報到")
            }
            if showsChevron {
                DisclosureChevron()
            }
        }
        // Withdrawn and rejected rows stay on the list and stay readable, but
        // dimmed: they are the answer to "where did they go", not a name anybody
        // should tap by accident.
        .opacity(registration.isCancelled ? 0.45 : 1)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}
