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
import tw.stsa.memberapp.model.CheckinRegistration

/**
 * What a 幹部 can do with an event, kept off the page everyone else reads.
 *
 * Mirrors `ios/MemberApp/Features/Events/EventOrganiserView.swift`. The event
 * screen belongs to the member: when it is on, where it is, and where their
 * ticket is. Running the event is a different job for a different handful of
 * people, and putting a door scanner above the venue address served neither.
 *
 * Reached only when Indico says this account manages the event — the same
 * permission the screen's own calls run on, asked rather than assumed.
 */
@Composable
fun EventOrganiserScreen(navController: NavHostController, eventId: String) {
    val container = LocalAppContainer.current
    val event = container.events.events.firstOrNull { it.id == eventId } ?: return
    val checkin = container.checkin

    // Reached from a row that only exists when Indico said yes — and this screen
    // does not take that on trust. What it draws is forty-odd people's names and
    // email addresses, so the screen that shows them is the one that asks. The
    // probe is cached, so on the ordinary path this costs nothing.
    LaunchedEffect(eventId) {
        checkin.probe(eventId, container.indico)
        if (checkin.access(eventId) == CheckinStore.Access.ALLOWED) {
            checkin.loadRoster(eventId, container.indico)
        }
    }

    val isAllowed = checkin.access(eventId) == CheckinStore.Access.ALLOWED
    val registrations = if (isAllowed) checkin.registrations(eventId) else emptyList()

    ScreenScaffold(
        title = stringResource(R.string.checkin_organiser_title),
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
            if (!isAllowed) {
                Text(
                    text = stringResource(R.string.checkin_denied),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                )
                return@Column
            }

            Progress(
                checkedIn = checkin.checkedInCount(eventId),
                registered = checkin.registeredCount(eventId),
            )

            BrandButton(onClick = { navController.navigate(Checkin(event.id)) }) {
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

            Roster(registrations, isLoading = checkin.isLoadingRoster)
        }
    }
}

/**
 * The number a door actually wants, before anyone opens the scanner: how many
 * are in, out of how many are coming.
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
            // the people still to come. Alphabetical inside each half so a name
            // can be found by eye.
            val sorted = registrations.sortedWith(
                compareBy<CheckinRegistration> { it.checkedIn }.thenBy { it.fullName }
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
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = registration.fullName,
                style = MaterialTheme.typography.bodyLarge,
            )
            Text(
                text = registration.email,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
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
