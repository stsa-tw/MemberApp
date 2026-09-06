package tw.stsa.memberapp.feature.events

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.EventOrganiser
import tw.stsa.memberapp.app.EventTicket
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.BrandTextButton
import tw.stsa.memberapp.designsystem.FactRow
import tw.stsa.memberapp.feature.checkin.CheckinStore
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.auth.AuthManager
import tw.stsa.memberapp.model.IndicoEvent
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs

@Composable
fun EventDetailScreen(navController: NavHostController, eventId: String) {
    val container = LocalAppContainer.current
    val event = container.events.events.firstOrNull { it.id == eventId } ?: return
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()

    val indico = container.indico
    val tickets = container.tickets
    val checkin = container.checkin

    // Nothing here is gated on the date, because Indico gates none of it.
    // `RHTicketDownload._check_access` runs four checks and not one of them is
    // about when the event was, so a ticket and a pass both outlive it. Someone
    // who attended has reason to want the record — the pass they kept, or the
    // code they were scanned with — and withholding it was this app's own rule.
    //
    // What the date does change is whether the answer can still move. A past
    // event's is settled, so it comes from `remembered` without touching the
    // network; an upcoming one is asked live every time, because this is where
    // someone lands right after registering and expects it to have changed.
    //
    // The door and the ticket are separate questions, so they are asked at the
    // same time. In sequence the door would go last, and everything ahead of it
    // is slow in a way a cheap JSON endpoint is not: Indico *renders a PDF* to
    // answer the ticket probe and *signs a pass* to answer the wallet one. An
    // organiser would sit watching 幹部功能 arrive seconds after the rest of the
    // page, held up by two requests about a ticket they may not even hold. iOS
    // had exactly this and it was the first thing anyone noticed.
    LaunchedEffect(eventId, indico.isLinked) {
        launch {
            tickets.hydrate(eventId)
            if (event.isUpcoming() || !tickets.isSettled(eventId)) {
                tickets.load(eventId, indico)
            }
            tickets.loadWalletPass(eventId, indico)
        }
        launch { checkin.probe(eventId, indico) }
    }

    val linkLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        scope.launch {
            try {
                indico.completeAuthorization(result.data)
                tickets.load(eventId, indico)
            } catch (error: Throwable) {
                // Dismissing the authorization tab is a choice, not a failure.
                if (!AuthManager.isUserCancellation(error)) tickets.report(error, eventId)
            }
        }
    }

    ScreenScaffold(
        title = event.title,
        onBack = { navController.popBackStack() },
        // The event's own page is a destination, not an action, and it is the one
        // thing on this screen that is true whatever the member's state —
        // registered or not, ticketed or not. That makes it chrome.
        actions = {
            event.url?.let { url ->
                IconButton(onClick = { uriHandler.openUri(url) }) {
                    Icon(
                        Icons.AutoMirrored.Filled.OpenInNew,
                        contentDescription = stringResource(R.string.event_view_page),
                    )
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(bottom = Theme.Metrics.fabClearance),
        ) {
            Hero(event)

            Spacer(Modifier.size(16.dp))
            InfoCard(event)

            // Inline, directly under the key facts, rather than pinned to the
            // bottom — see Theme.Metrics.fabClearance. This also puts the action
            // next to the time and place instead of at the end of a long
            // description.
            Spacer(Modifier.size(16.dp))
            Actions(
                state = tickets.state(eventId),
                eventUrl = event.url,
                isUpcoming = event.isUpcoming(),
                isBusy = indico.isBusy,
                onOpenUrl = { uriHandler.openUri(it) },
                onLink = { linkLauncher.launch(indico.authorizationIntent()) },
                onShowTicket = { navController.navigate(EventTicket(eventId)) },
            )

            // Only for someone Indico says manages this event.
            //
            // This used to be gated on the `isOfficer` group claim, which
            // answers a different question — a 幹部 is not necessarily a 幹部 of
            // *this* event — so the button appeared for people whose first tap
            // was a 403. `CheckinStore.probe` asks Indico instead, which is the
            // same permission the screen behind it runs on.
            //
            // A row rather than a button, and it carries the count: an organiser
            // opening the event usually wants the number, not the scanner, and a
            // row that answers before it is tapped is worth more than one that
            // does not.
            //
            // No date condition: Indico's check-in API will set `checked_in` on
            // any registration whenever, so an organiser reconciling attendance
            // after the fact is doing something Indico supports and this app has
            // no business refusing.
            if (checkin.access(eventId) == CheckinStore.Access.ALLOWED) {
                Spacer(Modifier.size(16.dp))
                OrganiserRow(
                    checkedIn = checkin.checkedInCount(eventId),
                    registered = checkin.registeredCount(eventId),
                    onClick = { navController.navigate(EventOrganiser(event.id)) },
                )
            }

            if (event.summary.isNotEmpty()) {
                Spacer(Modifier.size(22.dp))
                Text(
                    text = event.summary,
                    style = MaterialTheme.typography.bodyLarge,
                    lineHeight = MaterialTheme.typography.bodyLarge.fontSize * 1.5,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }
    }
}

/**
 * Exactly one filled button, ever.
 *
 * This screen used to stack the registration CTA and the ticket CTA as two
 * equally loud brand slabs, which is a wall of colour and no hierarchy — and it
 * had them the wrong way round for the case that matters: once you hold a
 * ticket, the registration page is the *lesser* action. So the primary is
 * whichever action the member's state makes primary, anything else drops to
 * plain, and there is one line of explanation rather than one per button.
 *
 * Mirrors `EventDetailView.actions` on iOS, down to which case gets the fill.
 */
@Composable
private fun Actions(
    state: TicketStore.State,
    eventUrl: String?,
    isUpcoming: Boolean,
    isBusy: Boolean,
    onOpenUrl: (String) -> Unit,
    onLink: () -> Unit,
    onShowTicket: () -> Unit,
) {
    val primaryLabel = stringResource(
        if (isUpcoming) R.string.event_register else R.string.event_view_page
    )

    Column(
        modifier = Modifier.padding(horizontal = Theme.Metrics.gutter),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        when (state) {
            // One door to the ticket, whatever Indico can serve for it. This
            // used to hand the PDF straight to a Custom Tab, which answers
            // "where is my ticket filed" rather than "what do I show at the
            // door". The screen behind this button answers the second, and still
            // offers the first.
            is TicketStore.State.Available ->
                BrandButton(onClick = onShowTicket) {
                    Text(stringResource(R.string.event_ticket_open))
                }

            TicketStore.State.NeedsLinking -> {
                eventUrl?.let { url ->
                    BrandButton(onClick = { onOpenUrl(url) }) { Text(primaryLabel) }
                }
                BrandTextButton(
                    text = stringResource(R.string.event_ticket_view),
                    onClick = onLink,
                    enabled = !isBusy,
                )
                // Indico's application is registered as trusted, so it shows no
                // consent screen — nothing else in the flow will tell the member
                // what is being connected. So this line has to.
                Caption(stringResource(R.string.event_ticket_link_note))
            }

            is TicketStore.State.Failed -> {
                eventUrl?.let { url ->
                    BrandButton(onClick = { onOpenUrl(url) }) { Text(primaryLabel) }
                }
                Caption(state.message)
            }

            // "Unavailable" could be "not registered", "awaiting approval" or
            // "the organiser turned tickets off" — Indico answers all three with
            // 403, so claiming any of them would be a guess. The registration
            // page knows; this button leads there.
            TicketStore.State.Idle,
            TicketStore.State.Loading,
            TicketStore.State.Unavailable,
            -> eventUrl?.let { url ->
                BrandButton(onClick = { onOpenUrl(url) }) { Text(primaryLabel) }
                // Indico's HTTP API is read-only, so registration cannot happen
                // in-app. Opening Indico is not a downgrade: it signs in through
                // the same authentik.
                Caption(stringResource(R.string.event_registration_note))
            }
        }
    }
}

@Composable
private fun Caption(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
}

/**
 * The door, as a row that has already answered.
 *
 * Above the member's own actions, because for whoever is working the door this
 * is what they came for and they have no time to hunt. Below the facts, because
 * it is not what the page is for.
 */
@Composable
private fun OrganiserRow(checkedIn: Int, registered: Int, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .padding(horizontal = Theme.Metrics.gutter)
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.card))
            .clickable(role = Role.Button, onClick = onClick)
            .background(MaterialTheme.colorScheme.sectionContainer)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.QrCodeScanner,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(R.string.checkin_organiser_title),
                style = MaterialTheme.typography.bodyLarge,
            )
            Text(
                text = if (registered > 0) {
                    stringResource(R.string.checkin_progress, checkedIn, registered)
                } else {
                    stringResource(R.string.checkin_organiser_subtitle)
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Hero(event: IndicoEvent) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 150.dp)
            .background(heroBrush(event.id))
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.Bottom,
    ) {
        Text(
            text = stringResource(event.kickerRes).uppercase(),
            style = MaterialTheme.typography.labelLarge.copy(letterSpacing = 0.8.sp),
            color = Color.White.copy(alpha = 0.8f),
        )
        Spacer(Modifier.size(6.dp))
        Text(
            text = event.title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = Color.White,
        )
    }
}

/**
 * The mock gives every event its own hue. There is no colour in Indico's data,
 * so derive a stable one from the id — same event, same colour.
 *
 * More reliably than iOS, in fact: `String.hashValue` there is seeded per
 * process, so the colour changes between launches. `hashCode` does not.
 */
private fun heroBrush(id: String): Brush {
    val hue = (abs(id.hashCode()) % 360).toFloat()
    return Brush.linearGradient(
        listOf(
            Color.hsv(hue, 0.55f, 0.42f),
            Color.hsv(hue, 0.65f, 0.26f),
        )
    )
}

@Composable
private fun InfoCard(event: IndicoEvent) {
    Column(
        modifier = Modifier
            .padding(horizontal = Theme.Metrics.gutter)
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.card))
            .background(MaterialTheme.colorScheme.sectionContainer),
    ) {
        FactRow(stringResource(R.string.label_time), schedule(event))
        event.place?.let {
            RowSeparator()
            FactRow(stringResource(R.string.label_venue), it)
        }
        event.address?.takeIf { it.isNotEmpty() }?.let {
            RowSeparator()
            FactRow(stringResource(R.string.label_address), it)
        }
    }
}

/**
 * When the event runs, written the way a person would say it — in the event's
 * own zone, not the reader's. Shared with [EventTicketScreen], which prints the
 * same line on the ticket.
 */
internal fun schedule(event: IndicoEvent): String {
    val day = DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withZone(event.zone)
    val clock = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(event.zone)

    val sameDay = event.start.atZone(event.zone).toLocalDate() ==
        event.end.atZone(event.zone).toLocalDate()

    return if (sameDay) {
        "${day.format(event.start)} ${clock.format(event.start)}–${clock.format(event.end)}"
    } else {
        "${day.format(event.start)} ${clock.format(event.start)} – " +
            "${day.format(event.end)} ${clock.format(event.end)}"
    }
}
