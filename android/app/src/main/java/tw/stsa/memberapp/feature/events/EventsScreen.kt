package tw.stsa.memberapp.feature.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.EventDetail
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.SectionHeader
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.feature.home.DateBlock
import tw.stsa.memberapp.model.IndicoEvent
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

private const val EVENTS_WEBSITE = "https://event.stsa.tw"

/**
 * The events tab.
 *
 * A `LazyColumn` rather than a scrolling `Column`: the Indico export is asked for
 * up to 200 entries, and composing every one of them to show the eight on screen
 * is work the reader pays for in dropped frames on the way in.
 *
 * The rows run edge to edge rather than sitting in an inset card. For a list
 * whose length the app does not control, that is both the Material arrangement
 * and the one that does not spend a gutter on each side of every row.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventsScreen(navController: NavHostController) {
    val store = LocalAppContainer.current.events
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) { if (store.events.isEmpty()) store.load() }

    // A failed refresh must not throw away events that are already on screen:
    // the list loaded earlier is still the best answer available. So that error
    // goes to a snackbar rather than replacing the screen. The empty case is
    // different — there the error is all there is to show — and it still gets
    // the full explanation below.
    val errorMessage = store.errorMessage
    LaunchedEffect(errorMessage) {
        if (errorMessage != null && store.events.isNotEmpty()) {
            snackbarHostState.showSnackbar(errorMessage)
        }
    }

    ScreenScaffold(
        title = stringResource(R.string.events),
        large = true,
        snackbarHost = { SnackbarHost(snackbarHostState) },
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
        val upcoming = store.upcoming()
        val past = store.past()
        // Resolved out here: the LazyColumn's content block is a LazyListScope,
        // not a composition, so it cannot read resources itself.
        val upcomingTitle = stringResource(R.string.events_upcoming)
        val pastTitle = stringResource(R.string.events_past)

        PullToRefreshBox(
            // Only once there is a list to pull on. During the very first load
            // the centred spinner below is the affordance, and running both
            // reads as two separate things loading.
            isRefreshing = store.isLoading && store.events.isNotEmpty(),
            onRefresh = { scope.launch { store.load() } },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 6.dp, bottom = Theme.Metrics.fabClearance),
            ) {
                if (upcoming.isNotEmpty()) {
                    section(
                        title = upcomingTitle,
                        events = upcoming,
                        highlightFirst = true,
                        onSelect = { navController.navigate(EventDetail(it.id)) },
                    )
                }
                if (past.isNotEmpty()) {
                    section(
                        title = pastTitle,
                        events = past,
                        highlightFirst = false,
                        onSelect = { navController.navigate(EventDetail(it.id)) },
                    )
                }
                if (store.events.isEmpty()) {
                    item {
                        EmptyState(
                            isLoading = store.isLoading,
                            message = store.errorMessage,
                            onRetry = { scope.launch { store.load() } },
                        )
                    }
                }
            }
        }
    }
}

private fun LazyListScope.section(
    title: String,
    events: List<IndicoEvent>,
    highlightFirst: Boolean,
    onSelect: (IndicoEvent) -> Unit,
) {
    item(key = "header-$title") {
        Spacer(Modifier.size(16.dp))
        SectionHeader(title, inset = Theme.Metrics.gutter)
    }
    // Keyed on the Indico id, so scroll position survives a refresh that
    // reorders the list.
    items(events, key = { it.id }) { event ->
        EventRow(
            event = event,
            isNext = highlightFirst && event.id == events.first().id,
            onClick = { onSelect(event) },
        )
        if (event.id != events.last().id) RowSeparator(inset = Theme.Metrics.gutter)
    }
}

@Composable
private fun EventRow(event: IndicoEvent, isNext: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
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
