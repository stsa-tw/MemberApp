package tw.stsa.memberapp.feature.deals

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.MemberCard
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.SectionCard
import tw.stsa.memberapp.designsystem.SectionHeader
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.model.Deal

@Composable
fun DealDetailScreen(navController: NavHostController, brand: String) {
    val deal = Deal.samples.firstOrNull { it.id == brand } ?: return
    val uriHandler = LocalUriHandler.current

    ScreenScaffold(
        title = deal.brand,
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(top = 18.dp, bottom = Theme.Metrics.fabClearance),
        ) {
            Header(deal)
            Spacer(Modifier.size(18.dp))

            SummaryCard(deal)

            if (deal.code != null) {
                Spacer(Modifier.size(14.dp))
                CodeCard(deal, deal.code)
            }

            // Inline rather than pinned — see Theme.Metrics.fabClearance. Some
            // partnerships are claimed on a website rather than by showing the
            // card at a counter, so the action follows the deal.
            Spacer(Modifier.size(16.dp))
            Column(
                modifier = Modifier.padding(horizontal = Theme.Metrics.gutter),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (deal.link != null) {
                    BrandButton(onClick = { uriHandler.openUri(deal.link) }) {
                        Text(deal.linkTitle ?: stringResource(R.string.deal_visit_website))
                    }
                    Note(stringResource(R.string.deal_opens_partner_site))
                } else {
                    BrandButton(onClick = { navController.navigate(MemberCard) }) {
                        Text(stringResource(R.string.deal_show_card))
                    }
                    Note(stringResource(R.string.deal_show_card_note))
                }
            }

            if (deal.terms.isNotEmpty()) {
                Spacer(Modifier.size(20.dp))
                SectionHeader(stringResource(R.string.deal_terms))
                SectionCard {
                    deal.terms.forEachIndexed { index, term ->
                        if (index > 0) RowSeparator()
                        Text(
                            text = term,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * The mark and the name, side by side.
 *
 * Stacked, the logo sat alone on a line it could not fill — a small mark with a
 * band of empty page beside it and the brand name pushed a long way down. The
 * plate is bordered for the same reason as the one in the list: on a white page
 * a white tile has no edge of its own.
 */
@Composable
private fun Header(deal: Deal) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Theme.Metrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(deal.logo),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .size(width = 108.dp, height = 76.dp)
                .clip(shape)
                .background(Color.White)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape)
                .padding(10.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = deal.brand,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            deal.brandEnglish?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SummaryCard(deal: Deal) {
    Column(
        modifier = Modifier
            .padding(horizontal = Theme.Metrics.gutter)
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.card))
            .background(MaterialTheme.colorScheme.sectionContainer)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        deal.headline?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
        Text(
            text = deal.summary,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CodeCard(deal: Deal, code: String) {
    val expired = deal.hasExpired()
    val accent = if (expired) {
        MaterialTheme.colorScheme.outline
    } else {
        MaterialTheme.colorScheme.primary
    }
    val corner = Theme.Radius.card

    Column(
        modifier = Modifier
            .padding(horizontal = Theme.Metrics.gutter)
            .fillMaxWidth()
            .clip(RoundedCornerShape(corner))
            .background(MaterialTheme.colorScheme.sectionContainer)
            .drawBehind {
                drawRoundRect(
                    color = accent.copy(alpha = if (expired) 1f else 0.5f),
                    cornerRadius = CornerRadius(corner.toPx()),
                    style = Stroke(
                        width = 1.5.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(
                            floatArrayOf(6.dp.toPx(), 4.dp.toPx())
                        ),
                    ),
                )
            }
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = stringResource(R.string.deal_code),
            style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp),
            color = accent,
        )

        SelectionContainer {
            Text(
                text = code,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                textDecoration = if (expired) TextDecoration.LineThrough else null,
            )
        }

        val date = dateLabel(deal)
        if (date != null) {
            if (expired) {
                // Showing a dead code as if it works wastes someone's time at a
                // counter. Say so rather than rendering it normally.
                Text(
                    text = stringResource(R.string.deal_expired_on, date),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            } else {
                Text(
                    text = stringResource(R.string.deal_valid_until, date),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun Note(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
}

/** The bare date, for the sentences that supply their own preposition. */
private fun dateLabel(deal: Deal): String? {
    val expires = deal.expires ?: return null
    return "${expires.year}/${expires.monthValue}/${expires.dayOfMonth}"
}
