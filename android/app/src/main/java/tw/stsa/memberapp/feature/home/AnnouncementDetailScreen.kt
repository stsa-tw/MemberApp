package tw.stsa.memberapp.feature.home

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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.EventDetail
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.model.Announcement

@Composable
fun AnnouncementDetailScreen(navController: NavHostController, index: Int) {
    val announcement = Announcement.samples.getOrNull(index) ?: return
    val events = LocalAppContainer.current.events
    val uriHandler = LocalUriHandler.current

    ScreenScaffold(
        title = stringResource(R.string.announcement),
        onBack = { navController.popBackStack() },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
                .padding(bottom = Theme.Metrics.fabClearance),
        ) {
            Text(
                text = "${announcement.channel} · ${announcement.month} ${announcement.day}",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.size(8.dp))

            Text(
                text = announcement.title,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.size(6.dp))

            Text(
                text = announcement.subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.size(18.dp))

            announcement.body.forEach { paragraph ->
                Text(
                    text = paragraph,
                    style = MaterialTheme.typography.bodyLarge,
                    lineHeight = MaterialTheme.typography.bodyLarge.fontSize * 1.5,
                )
                Spacer(Modifier.size(14.dp))
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Theme.Radius.card))
                    .background(MaterialTheme.colorScheme.sectionContainer),
            ) {
                DetailRow(stringResource(R.string.label_time), announcement.whenText)
                RowSeparator()
                DetailRow(stringResource(R.string.label_venue), announcement.place)
                announcement.contact?.let { contact ->
                    RowSeparator()
                    DetailRow(stringResource(R.string.label_contact), contact)
                }
            }

            Spacer(Modifier.size(20.dp))

            // Prefers pushing the event inside the app; falls back to the web
            // only when the event is not in the loaded window or has left the
            // category. Inline rather than pinned — see Theme.Metrics.fabClearance.
            val event = announcement.eventId?.let { id -> events.events.firstOrNull { it.id == id } }
            when {
                event != null -> BrandButton(onClick = {
                    navController.navigate(EventDetail(event.id))
                }) {
                    Text(stringResource(R.string.open_event))
                }

                announcement.eventUrl != null -> Column(
                    horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    BrandButton(onClick = { uriHandler.openUri(announcement.eventUrl) }) {
                        Text(stringResource(R.string.open_event_page))
                    }
                    Text(
                        text = stringResource(R.string.opens_indico_event_page),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(text = value, style = MaterialTheme.typography.bodyMedium)
    }
}
