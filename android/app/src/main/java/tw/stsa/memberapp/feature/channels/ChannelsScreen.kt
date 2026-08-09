package tw.stsa.memberapp.feature.channels

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.GroupedCard
import tw.stsa.memberapp.designsystem.GroupedCardHeader
import tw.stsa.memberapp.designsystem.GroupedFooter
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.model.Channel

@Composable
fun ChannelsScreen(navController: NavHostController) {
    val container = LocalAppContainer.current
    val settings = container.settings
    val auth = container.auth

    // Seeded from the member's own school, so a first visit is already sensible
    // rather than empty.
    val defaults = Channel.defaultSubscriptions(auth.profile?.school)
    val subscribed = settings.subscribedChannels ?: defaults

    ScreenScaffold(
        title = stringResource(R.string.channels),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(top = 6.dp, bottom = Theme.Metrics.fabClearance),
        ) {
            GroupedCardHeader(stringResource(R.string.channels))
            GroupedCard {
                Channel.all.forEachIndexed { index, channel ->
                    if (index > 0) RowSeparator(inset = 70.dp)
                    ChannelRow(
                        channel = channel,
                        checked = subscribed.contains(channel.id),
                        onCheckedChange = { settings.setSubscribed(it, channel, defaults) },
                    )
                }
            }
            // Says what it does today rather than implying push works.
            GroupedFooter(stringResource(R.string.channels_footer))
        }
    }
}

@Composable
private fun ChannelRow(channel: Channel, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Theme.Metrics.gutter, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(CircleShape)
                .background(channel.tint),
            contentAlignment = Alignment.Center,
        ) {
            if (channel.icon != null) {
                Icon(
                    imageVector = channel.icon,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(20.dp),
                )
            } else {
                Text(
                    text = channel.badge,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }

        Column(Modifier.weight(1f)) {
            Text(
                text = stringResource(channel.nameRes),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = stringResource(channel.detailRes),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
