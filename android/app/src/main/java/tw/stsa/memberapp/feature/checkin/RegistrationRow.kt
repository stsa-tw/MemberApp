package tw.stsa.memberapp.feature.checkin

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import tw.stsa.memberapp.R
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.model.CheckinRegistration

/**
 * One registrant as a list row: who they are, what state their registration is
 * in, the organiser's tags, and whether they have come through a door.
 *
 * Mirrors `ios/MemberApp/Features/Scan/RegistrationRow.swift`. Shared by the
 * roster on 幹部功能 and the door's name picker, which are the same list read for
 * two different reasons. They were two copies of this until tags gave them a
 * third thing to keep in step, and a row showing a tag in one list and not the
 * other is worse than no tag at all — a 幹部 would learn to trust whichever list
 * they opened last.
 */
@Composable
fun RegistrationRow(
    registration: CheckinRegistration,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) {
                    Modifier.clickable(role = Role.Button, onClick = onClick)
                } else {
                    Modifier
                }
            )
            // Withdrawn and rejected rows stay on the list and stay readable,
            // but dimmed: they answer "where did they go", and are not a name
            // anybody should tap by accident.
            .alpha(if (registration.isCancelled) 0.45f else 1f)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(text = registration.fullName, style = MaterialTheme.typography.bodyLarge)

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = registration.email,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
                registrationStateLabel(registration)?.let { label ->
                    Text(
                        text = label,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            RegistrationTagChips(registration.tags)
        }
        Spacer(Modifier.size(8.dp))

        if (registration.checkedIn) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = stringResource(R.string.checkin_checked_in),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/**
 * The state, said out loud, when it is worth saying. `complete` is the ordinary
 * case and a row that announced it would only be noise.
 */
@Composable
internal fun registrationStateLabel(registration: CheckinRegistration): String? =
    when (registration.state) {
        CheckinRegistration.State.UNPAID -> stringResource(R.string.registration_state_unpaid)
        CheckinRegistration.State.PENDING -> stringResource(R.string.registration_state_pending)
        CheckinRegistration.State.WITHDRAWN -> stringResource(R.string.registration_state_withdrawn)
        CheckinRegistration.State.REJECTED -> stringResource(R.string.registration_state_rejected)
        else -> null
    }
