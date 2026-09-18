package tw.stsa.memberapp.feature.events

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.Checkin
import tw.stsa.memberapp.app.EventForm
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.SectionCard
import tw.stsa.memberapp.designsystem.SectionRow
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.feature.checkin.CheckinStore
import tw.stsa.memberapp.model.CheckinRegForm

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
 *
 * With one registration form this screen *is* that form's screen. With more than
 * one it is a chooser, because they are not one job: 報名表 and 遊覽車報名表 are
 * separate lists with separate doors and separate arrivals, and a 幹部 opening
 * this is already on their way to one of them. Stacking both made them scroll
 * past the wrong one to reach the right one, every time.
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
    val forms = if (isAllowed) checkin.forms(eventId) else emptyList()

    // One form: this screen is that form, and a list of one to tap through would
    // be a step that asks nothing.
    if (isAllowed && forms.size == 1) {
        EventFormScreen(navController, eventId, forms[0].id)
        return
    }

    // Below the delegation on purpose: EventFormScreen runs its own poll, and
    // two loops on one event would only ask the same question twice as often.
    //
    // Each row carries its form's arrivals, and both doors are being worked by
    // somebody else — so the counts a 幹部 is choosing between keep asking Indico
    // rather than ageing while the chooser sits open.
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(eventId, lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            checkin.autoRefresh(eventId, container.indico)
        }
    }

    ScreenScaffold(
        title = stringResource(R.string.checkin_organiser_title),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(top = 16.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (!isAllowed) {
                Text(
                    text = stringResource(R.string.checkin_denied),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = Theme.Metrics.gutter)
                        .padding(top = 24.dp),
                )
                return@Column
            }

            SectionCard {
                forms.forEachIndexed { index, form ->
                    if (index > 0) RowSeparator()
                    SectionRow(
                        label = form.title.ifBlank {
                            stringResource(R.string.checkin_form_fallback)
                        },
                        supporting = summary(eventId, form),
                        onClick = { navController.navigate(EventForm(eventId, form.id)) },
                        trailing = {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                    )
                }
            }
        }
    }
}

/**
 * The count a 幹部 is choosing between, so the choice can be made from the list
 * rather than by opening both.
 */
@Composable
private fun summary(eventId: String, form: CheckinRegForm): String {
    val checkin = LocalAppContainer.current.checkin
    if (checkin.isLoadingRoster && checkin.registrations(eventId).isEmpty()) {
        return stringResource(R.string.checkin_roster_loading)
    }
    return stringResource(
        R.string.checkin_progress,
        checkin.checkedInCount(eventId, form.id),
        checkin.registeredCount(eventId, form.id),
    )
}
