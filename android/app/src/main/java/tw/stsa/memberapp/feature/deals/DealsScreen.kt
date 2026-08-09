package tw.stsa.memberapp.feature.deals

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.DealDetail
import tw.stsa.memberapp.designsystem.DisclosureChevron
import tw.stsa.memberapp.designsystem.GroupedCard
import tw.stsa.memberapp.designsystem.GroupedCardHeader
import tw.stsa.memberapp.designsystem.GroupedFooter
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.model.Deal

private const val DEALS_WEBSITE = "https://stsa.tw/discount/"

@Composable
fun DealsScreen(navController: NavHostController) {
    val uriHandler = LocalUriHandler.current
    val deals = Deal.samples
    val active = deals.filter { !it.hasExpired() }
    val expired = deals.filter { it.hasExpired() }

    ScreenScaffold(
        title = stringResource(R.string.member_deals),
        large = true,
        actions = {
            // Offers are hardcoded here but maintained on the website, so the
            // canonical list is one tap away until this reads from a backend.
            IconButton(onClick = { uriHandler.openUri(DEALS_WEBSITE) }) {
                Icon(
                    Icons.AutoMirrored.Filled.OpenInNew,
                    contentDescription = stringResource(R.string.deals_page),
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
            Section(
                title = stringResource(R.string.deals_partners),
                deals = active,
                footnote = stringResource(R.string.deals_footnote),
                onSelect = { navController.navigate(DealDetail(it.id)) },
            )
            Section(
                title = stringResource(R.string.deals_expired),
                deals = expired,
                footnote = null,
                onSelect = { navController.navigate(DealDetail(it.id)) },
            )
        }
    }
}

@Composable
private fun Section(
    title: String,
    deals: List<Deal>,
    footnote: String?,
    onSelect: (Deal) -> Unit,
) {
    if (deals.isEmpty()) return
    Column {
        GroupedCardHeader(title)
        GroupedCard {
            deals.forEachIndexed { index, deal ->
                if (index > 0) RowSeparator(inset = 0.dp)
                DealRow(deal = deal, onClick = { onSelect(deal) })
            }
        }
        if (footnote != null) GroupedFooter(footnote)
    }
}

@Composable
private fun DealRow(deal: Deal, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .alpha(if (deal.hasExpired()) 0.5f else 1f)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PartnerLogo(deal)

        Column(Modifier.weight(1f)) {
            Text(
                text = deal.brand,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = deal.headline ?: deal.summary,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            expiryLabel(deal)?.let { label ->
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline,
                )
            }
        }

        DisclosureChevron()
    }
}

/**
 * Always on white: the logos are dark-on-transparent and would disappear
 * against the grouped background in dark mode.
 */
@Composable
fun PartnerLogo(deal: Deal, modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(deal.logo),
        contentDescription = deal.brand,
        contentScale = ContentScale.Fit,
        modifier = modifier
            .size(width = 72.dp, height = 44.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White)
            .padding(6.dp),
    )
}

/** "至 2026/6/30", or nothing when the offer has no stated end date. */
@Composable
fun expiryLabel(deal: Deal): String? {
    val expires = deal.expires ?: return null
    return stringResource(
        R.string.deal_expiry_label,
        expires.year,
        expires.monthValue,
        expires.dayOfMonth,
    )
}
