package tw.stsa.memberapp.feature.deals

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
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
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.DealDetail
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.SectionHeader
import tw.stsa.memberapp.designsystem.SectionIntro
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.model.Deal

private const val DEALS_WEBSITE = "https://stsa.tw/discount/"

/**
 * The offers tab.
 *
 * Lazy and edge to edge for the same reasons as the events tab: the partner list
 * is hardcoded today but is meant to come from a backend, and a list that grows
 * should not have to be rewritten to keep scrolling smoothly when it does.
 */
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
        // Resolved out here: the LazyColumn's content block is a LazyListScope,
        // not a composition, so it cannot read resources itself.
        val partnersTitle = stringResource(R.string.deals_partners)
        val partnersFootnote = stringResource(R.string.deals_footnote)
        val expiredTitle = stringResource(R.string.deals_expired)

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(top = 6.dp, bottom = Theme.Metrics.fabClearance),
        ) {
            section(
                title = partnersTitle,
                deals = active,
                footnote = partnersFootnote,
                onSelect = { navController.navigate(DealDetail(it.id)) },
            )
            section(
                title = expiredTitle,
                deals = expired,
                footnote = null,
                onSelect = { navController.navigate(DealDetail(it.id)) },
            )
        }
    }
}

private fun LazyListScope.section(
    title: String,
    deals: List<Deal>,
    footnote: String?,
    onSelect: (Deal) -> Unit,
) {
    if (deals.isEmpty()) return

    item(key = "header-$title") {
        Spacer(Modifier.size(20.dp))
        // Aligned to the rows' own gutter — this list runs edge to edge, so the
        // header has no card inset to clear.
        SectionHeader(title, inset = Theme.Metrics.gutter)
        if (footnote != null) {
            SectionIntro(footnote, inset = Theme.Metrics.gutter)
        }
    }
    items(deals, key = { it.id }) { deal ->
        DealRow(deal = deal, onClick = { onSelect(deal) })
        if (deal.id != deals.last().id) RowSeparator(inset = Theme.Metrics.gutter)
    }
}

@Composable
private fun DealRow(deal: Deal, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .alpha(if (deal.hasExpired()) 0.5f else 1f)
            // A floor rather than fixed padding: the rows carry one, two or
            // three lines of text depending on the offer, and without it the
            // list steps up and down the page.
            .defaultMinSize(minHeight = 76.dp)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
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
    }
}

/**
 * Always on white: the logos are dark-on-transparent and would disappear
 * against the page in dark mode.
 *
 * The plate is drawn rather than implied. In light mode the page is now white
 * too, so a white tile with no edge is not a tile — the marks looked like they
 * had been dropped loose into the row, and the ones with pale artwork
 * (良人食堂, 青鳥旅行) worst of all.
 */
@Composable
fun PartnerLogo(deal: Deal, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(10.dp)
    Image(
        painter = painterResource(deal.logo),
        contentDescription = deal.brand,
        contentScale = ContentScale.Fit,
        modifier = modifier
            .size(width = 76.dp, height = 52.dp)
            .clip(shape)
            .background(Color.White)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape)
            .padding(7.dp),
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
