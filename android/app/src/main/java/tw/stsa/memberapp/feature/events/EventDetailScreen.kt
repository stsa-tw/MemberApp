package tw.stsa.memberapp.feature.events

import androidx.compose.foundation.background
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.model.IndicoEvent
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs

@Composable
fun EventDetailScreen(navController: NavHostController, eventId: String) {
    val store = LocalAppContainer.current.events
    val event = store.events.firstOrNull { it.id == eventId } ?: return
    val uriHandler = LocalUriHandler.current

    ScreenScaffold(
        title = event.title,
        onBack = { navController.popBackStack() },
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
            event.url?.let { url ->
                Spacer(Modifier.size(16.dp))
                Column(
                    modifier = Modifier.padding(horizontal = Theme.Metrics.gutter),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    BrandButton(onClick = { uriHandler.openUri(url) }) {
                        Text(
                            stringResource(
                                if (event.isUpcoming()) {
                                    R.string.event_register
                                } else {
                                    R.string.event_view_page
                                }
                            )
                        )
                    }
                    // Indico's HTTP API is read-only, so registration cannot
                    // happen in-app. Opening Indico is not a downgrade: it signs
                    // in through the same authentik.
                    Text(
                        text = stringResource(R.string.event_registration_note),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
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
        InfoRow(stringResource(R.string.label_time), schedule(event))
        event.place?.let {
            RowSeparator()
            InfoRow(stringResource(R.string.label_venue), it)
        }
        event.address?.takeIf { it.isNotEmpty() }?.let {
            RowSeparator()
            InfoRow(stringResource(R.string.label_address), it)
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(1f),
        )
    }
}

private fun schedule(event: IndicoEvent): String {
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
