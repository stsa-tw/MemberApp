package tw.stsa.memberapp.feature.events

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.Checkin
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.feature.checkin.CheckinStore
import tw.stsa.memberapp.feature.checkin.registrationStateLabel
import tw.stsa.memberapp.model.CheckinRegistration

/**
 * One registration form, the way a 幹部 works it: how many have arrived, the
 * door, and the list.
 *
 * A form is the unit because Indico makes it one — a registration lives inside
 * exactly one form and carries its own `checked_in`, so 報名表 and 遊覽車報名表
 * are two lists, two doors, and two sets of arrivals that never touch.
 *
 * Mirrors `ios/MemberApp/Features/Events/EventFormView.swift`. Reached from
 * `EventOrganiserScreen`, which is the chooser when an event has several forms
 * and delegates straight to [FormContent] when it has one.
 */
@Composable
fun EventFormScreen(navController: NavHostController, eventId: String, formId: Int) {
    val container = LocalAppContainer.current
    val checkin = container.checkin
    val form = checkin.forms(eventId).firstOrNull { it.id == formId }

    LaunchedEffect(eventId) {
        if (checkin.access(eventId) == CheckinStore.Access.ALLOWED) {
            checkin.loadRoster(eventId, container.indico)
        }
    }

    ScreenScaffold(
        title = form?.title?.ifBlank { stringResource(R.string.checkin_form_fallback) }
            ?: stringResource(R.string.checkin_form_fallback),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Theme.Metrics.gutter)
                .padding(top = 16.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            FormContent(
                eventId = eventId,
                formId = formId,
                onOpenDoor = { navController.navigate(Checkin(eventId, formId)) },
            )
        }
    }
}

/** The count, the door and the list — the same wherever the form is shown. */
@Composable
internal fun FormContent(eventId: String, formId: Int, onOpenDoor: () -> Unit) {
    val checkin = LocalAppContainer.current.checkin

    Progress(
        checkedIn = checkin.checkedInCount(eventId, formId),
        registered = checkin.registeredCount(eventId, formId),
    )

    BrandButton(onClick = onOpenDoor) {
        Icon(
            imageVector = Icons.Filled.QrCodeScanner,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = stringResource(R.string.checkin_title),
            modifier = Modifier.padding(start = 8.dp),
        )
    }

    Roster(
        registrations = checkin.registrations(eventId, formId),
        isLoading = checkin.isLoadingRoster,
    )
}

/**
 * The number a door actually wants, before anyone opens the scanner: how many
 * are in, out of how many are coming.
 *
 * Withdrawn and rejected registrations are in neither half. They stay on
 * Indico's list — `~is_deleted` is the only filter its API applies — but nobody
 * is waiting for them, and counting them made a denominator that could not be
 * reached. Indico's own `active_registration_count` draws the line in the same
 * place, so this number and the one on its management page agree.
 */
@Composable
private fun Progress(checkedIn: Int, registered: Int) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.card))
            .background(MaterialTheme.colorScheme.sectionContainer)
            .padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = "$checkedIn / $registered",
            style = MaterialTheme.typography.displaySmall.copy(fontSize = 44.sp),
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = stringResource(R.string.checkin_checked_in),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Roster(registrations: List<CheckinRegistration>, isLoading: Boolean) {
    when {
        isLoading && registrations.isEmpty() -> Column(
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator()
        }

        registrations.isEmpty() -> Text(
            text = stringResource(R.string.checkin_roster_empty),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
        )

        else -> Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Theme.Radius.card))
                .background(MaterialTheme.colorScheme.sectionContainer),
        ) {
            // Not checked in first, which is the list a door is working from —
            // the people still to come. Alphabetical inside each group so a name
            // can be found by eye, and anyone who withdrew at the very bottom:
            // kept visible, because "where did they go" is a question the roster
            // should answer, but they are nobody's next arrival.
            val sorted = registrations.sortedWith(
                compareBy<CheckinRegistration> { it.isCancelled }
                    .thenBy { it.checkedIn }
                    .thenBy { it.fullName },
            )
            sorted.forEachIndexed { index, registration ->
                if (index > 0) RowSeparator()
                RosterRow(registration)
            }
        }
    }
}

@Composable
private fun RosterRow(registration: CheckinRegistration) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (registration.isCancelled) 0.45f else 1f)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = registration.fullName,
                style = MaterialTheme.typography.bodyLarge,
            )
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
