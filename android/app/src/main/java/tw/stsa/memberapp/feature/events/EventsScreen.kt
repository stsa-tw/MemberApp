package tw.stsa.memberapp.feature.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.EventDetail
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.DisclosureChevron
import tw.stsa.memberapp.designsystem.GroupedCard
import tw.stsa.memberapp.designsystem.GroupedCardHeader
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.feature.home.DateBlock
import tw.stsa.memberapp.model.IndicoEvent
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

private const val EVENTS_WEBSITE = "https://event.stsa.tw"

@Composable
fun EventsScreen(navController: NavHostController) {
    val store = LocalAppContainer.current.events
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) { if (store.events.isEmpty()) store.load() }

    ScreenScaffold(
        title = stringResource(R.string.events),
        large = true,
        actions = {
            // The app shows a read-only slice of Indico; the full site has
            // registration, attachments and past material.
            IconButton(onClick = { uriHandler.openUri(EVENTS_WEBSITE) }) {
                Icon(
                    Icons.AutoMirrored.Filled.OpenInNew,
                    contentDescription = stringResource(R.string.events_website),
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(top = 6.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            val upcoming = store.upcoming()
            val past = store.past()

            if (upcoming.isNotEmpty()) {
                Section(
                    title = stringResource(R.string.events_upcoming),
                    events = upcoming,
                    highlightFirst = true,
                    onSelect = { navController.navigate(EventDetail(it.id)) },
                )
            }
            if (past.isNotEmpty()) {
                Section(
                    title = stringResource(R.string.events_past),
                    events = past,
                    highlightFirst = false,
                    onSelect = { navController.navigate(EventDetail(it.id)) },
                )
            }
            if (store.events.isEmpty()) {
                EmptyState(
                    isLoading = store.isLoading,
                    message = store.errorMessage,
                    onRetry = { scope.launch { store.load() } },
                )
            }
        }
    }
}

@Composable
private fun Section(
    title: String,
    events: List<IndicoEvent>,
    highlightFirst: Boolean,
    onSelect: (IndicoEvent) -> Unit,
) {
    Column {
        GroupedCardHeader(title)
        GroupedCard {
            events.forEachIndexed { index, event ->
                if (index > 0) RowSeparator(inset = 0.dp)
                EventRow(
                    event = event,
                    isNext = highlightFirst && index == 0,
                    onClick = { onSelect(event) },
                )
            }
        }
    }
}

@Composable
private fun EventRow(event: IndicoEvent, isNext: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Formatted with an explicit US locale rather than the reader's, so the
        // date block matches the announcement rows' "15 / AUG" instead of
        // rendering "15日 / 8月".
        DateBlock(
            day = DAY.withZone(event.zone).format(event.start),
            month = MONTH.withZone(event.zone).format(event.start).uppercase(Locale.US),
            highlighted = isNext,
        )

        Column(Modifier.weight(1f)) {
            Text(
                text = event.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                // Indico titles run long ("… In Conversation with NUS
                // Admissions"); two lines keeps the rows an even height.
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                // Time stays in the reader's locale — only the date block is fixed.
                text = listOfNotNull(
                    TIME.withZone(event.zone).format(event.start),
                    event.place,
                ).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        DisclosureChevron()
    }
}

@Composable
private fun EmptyState(isLoading: Boolean, message: String?, onRetry: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 40.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            isLoading -> CircularProgressIndicator()
            message != null -> Unavailable(
                icon = Icons.Filled.WifiOff,
                title = stringResource(R.string.events_load_failed),
                detail = message,
                action = {
                    TextButton(onClick = onRetry) { Text(stringResource(R.string.retry)) }
                },
            )

            else -> Unavailable(
                icon = Icons.Filled.CalendarMonth,
                title = stringResource(R.string.no_events),
                detail = stringResource(R.string.events_empty_detail),
            )
        }
    }
}

@Composable
private fun Unavailable(
    icon: ImageVector,
    title: String,
    detail: String,
    action: @Composable (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier.padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(44.dp),
        )
        Spacer(Modifier.size(12.dp))
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.size(4.dp))
        Text(
            text = detail,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        action?.invoke()
    }
}

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d", Locale.US)
private val MONTH: DateTimeFormatter = DateTimeFormatter.ofPattern("MMM", Locale.US)
private val TIME: DateTimeFormatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
