package tw.stsa.memberapp.feature.home

import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.AnnouncementDetail
import tw.stsa.memberapp.app.Channels
import tw.stsa.memberapp.app.Deals
import tw.stsa.memberapp.app.Events
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.app.MemberCard
import tw.stsa.memberapp.designsystem.DisclosureChevron
import tw.stsa.memberapp.designsystem.GroupedCard
import tw.stsa.memberapp.designsystem.GroupedCardHeader
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.groupedCard
import tw.stsa.memberapp.model.Announcement
import tw.stsa.memberapp.model.Deal
import java.time.LocalTime

@Composable
fun HomeScreen(navController: NavHostController) {
    val container = LocalAppContainer.current
    val auth = container.auth
    val events = container.events
    val announcements = Announcement.samples

    // Prefer the nickname: authentik fills given_name with the full name, and
    // trimming a surname by character count breaks on two-character ones.
    val name = auth.profile?.let { it.nickname ?: it.givenName ?: it.displayName }.orEmpty()
    val timeOfDay = stringResource(
        when (LocalTime.now().hour) {
            in 5..11 -> R.string.greeting_morning
            in 12..17 -> R.string.greeting_afternoon
            else -> R.string.greeting_evening
        }
    )

    // Real count from Indico rather than the mock's fixed "3 場".
    val upcoming = events.upcoming()
    val upcomingLabel = if (upcoming.isEmpty()) {
        stringResource(R.string.no_events)
    } else {
        pluralStringResource(R.plurals.events_upcoming_count, upcoming.size, upcoming.size)
    }
    // Buddy 配對 has no data source yet, so the second shortcut points at the
    // one thing behind it that does.
    val partnerCount = Deal.samples.count { !it.hasExpired() }
    val dealsLabel = pluralStringResource(
        R.plurals.deals_partner_count,
        partnerCount,
        partnerCount,
    )

    ScreenScaffold(
        title = stringResource(R.string.greeting_format, timeOfDay, name),
        large = true,
        actions = {
            IconButton(onClick = { navController.navigate(Channels) }) {
                Icon(
                    Icons.AutoMirrored.Filled.Chat,
                    contentDescription = stringResource(R.string.channels),
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
            MemberCardBanner(
                name = auth.profile?.let { profile ->
                    listOfNotNull(profile.displayName, profile.school).joinToString(" · ")
                },
                onClick = { navController.navigate(MemberCard) },
            )

            Row(
                modifier = Modifier.padding(horizontal = Theme.Metrics.gutter),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ShortcutTile(
                    icon = Icons.Filled.CalendarMonth,
                    titleRes = R.string.home_shortcut_events,
                    detail = upcomingLabel,
                    modifier = Modifier.weight(1f),
                    onClick = { navController.navigate(Events) },
                )
                ShortcutTile(
                    icon = Icons.Filled.LocalOffer,
                    titleRes = R.string.home_shortcut_deals,
                    detail = dealsLabel,
                    modifier = Modifier.weight(1f),
                    onClick = { navController.navigate(Deals) },
                )
            }

            Column {
                GroupedCardHeader(stringResource(R.string.announcements)) {
                    TextButton(onClick = { navController.navigate(Channels) }) {
                        Text(stringResource(R.string.channels))
                    }
                }
                GroupedCard {
                    announcements.forEachIndexed { index, announcement ->
                        // The mock rules edge-to-edge inside the card rather than
                        // insetting past the date column.
                        if (index > 0) RowSeparator(inset = 0.dp)
                        AnnouncementRow(
                            announcement = announcement,
                            isLatest = index == 0,
                            onClick = { navController.navigate(AnnouncementDetail(index)) },
                        )
                    }
                }
            }
        }
    }
}

/** The dark banner that opens the member card. */
@Composable
private fun MemberCardBanner(name: String?, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .padding(horizontal = Theme.Metrics.gutter)
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.button))
            .background(Theme.InkCard)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Image(
            painter = painterResource(R.drawable.stsa_logo),
            contentDescription = null,
            modifier = Modifier.size(42.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = stringResource(R.string.member_card),
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
            )
            if (name != null) {
                Text(
                    text = name,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.6f),
                )
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.35f),
        )
    }
}

/** One of the two shortcuts under the member card. */
@Composable
private fun ShortcutTile(
    icon: ImageVector,
    @StringRes titleRes: Int,
    detail: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(Theme.Radius.button))
            .background(MaterialTheme.colorScheme.groupedCard)
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(24.dp),
        )
        Spacer(Modifier.size(8.dp))
        Text(stringResource(titleRes), style = MaterialTheme.typography.titleSmall)
        Text(
            text = detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun AnnouncementRow(
    announcement: Announcement,
    isLatest: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        DateBlock(day = announcement.day, month = announcement.month, highlighted = isLatest)

        Column(Modifier.weight(1f)) {
            Text(
                text = announcement.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "${announcement.channel} · ${announcement.subtitle}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        DisclosureChevron()
    }
}

/** The day-over-month column that leads every announcement and event row. */
@Composable
fun DateBlock(day: String, month: String, highlighted: Boolean) {
    Column(
        modifier = Modifier.size(width = 42.dp, height = 42.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = day,
            style = MaterialTheme.typography.titleMedium,
            color = if (highlighted) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            },
        )
        Text(
            text = month,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
