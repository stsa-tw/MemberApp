package tw.stsa.memberapp.feature.settings

import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.designsystem.BrandSectionTitle
import tw.stsa.memberapp.designsystem.GroupedCard
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme

/** Text gutter for this page. Wider than the standard one, as on iOS. */
private val PAGE_GUTTER = 20.dp

/**
 * Mirrors https://stsa.tw/about/ so members can read it without leaving the app.
 *
 * The copy is STSA's own, transcribed rather than rewritten, and lives in
 * strings.xml alongside its English translation. If the website changes, that
 * file and `ios/MemberApp/Resources/Localizable.xcstrings` are what to update —
 * there is no backend for it, and one hardcoded page is cheaper than a content
 * service for text that changes once a year.
 *
 * The page pads its own text rather than padding the whole column, because the
 * goals card has to reach the standard gutter. iOS gets there with a negative
 * inset; `Modifier.padding` rejects negative values, so the inset never happens
 * in the first place here.
 */
@Composable
fun AboutScreen(navController: NavHostController) {
    val uriHandler = LocalUriHandler.current

    ScreenScaffold(
        title = stringResource(R.string.about_stsa),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(top = PAGE_GUTTER, bottom = Theme.Metrics.fabClearance),
        ) {
            Masthead()

            SectionTitle(R.string.about_purpose)
            Paragraph(R.string.about_purpose_1)
            Paragraph(R.string.about_purpose_2)
            Paragraph(R.string.about_purpose_3)

            SectionTitle(R.string.about_goals)
            GroupedCard {
                goals.forEachIndexed { index, goal ->
                    if (index > 0) RowSeparator(inset = 0.dp)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = "%02d".format(index + 1),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            text = stringResource(goal),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }

            SectionTitle(R.string.about_wwtsa)
            Paragraph(R.string.about_wwtsa_body)
            Row(
                modifier = Modifier
                    .padding(horizontal = PAGE_GUTTER)
                    .padding(top = 4.dp)
                    .clickable { uriHandler.openUri("https://www.wwtsa.org.tw/") },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = stringResource(R.string.about_wwtsa_link),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.OpenInNew,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(14.dp),
                )
            }

            SectionTitle(R.string.about_milestones)
            Spacer(Modifier.size(4.dp))
            milestones.forEachIndexed { index, milestone ->
                MilestoneRow(milestone, isFirst = index == 0)
            }
        }
    }
}

@Composable
private fun Masthead() {
    Column(
        modifier = Modifier.padding(horizontal = PAGE_GUTTER),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Image(
            painter = painterResource(R.drawable.stsa_logo),
            contentDescription = null,
            modifier = Modifier.size(64.dp),
        )
        Column {
            Text(
                text = stringResource(R.string.about_org_name),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.about_org_english),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SectionTitle(@StringRes titleRes: Int) {
    Spacer(Modifier.size(24.dp))
    BrandSectionTitle(
        text = stringResource(titleRes),
        modifier = Modifier.padding(horizontal = PAGE_GUTTER),
    )
    Spacer(Modifier.size(8.dp))
}

@Composable
private fun Paragraph(@StringRes textRes: Int) {
    Text(
        text = stringResource(textRes),
        style = MaterialTheme.typography.bodyLarge,
        lineHeight = MaterialTheme.typography.bodyLarge.fontSize * 1.5,
        modifier = Modifier
            .padding(horizontal = PAGE_GUTTER)
            .padding(bottom = 8.dp),
    )
}

/**
 * A dot-and-rule timeline; the rule is dropped above the first row so it does
 * not appear to continue past the earliest entry.
 *
 * The row is measured at its minimum intrinsic height so the trailing rule can
 * take the remaining space — without that the rail column sizes to its own
 * content and the line between entries disappears.
 */
@Composable
private fun MilestoneRow(milestone: Milestone, isFirst: Boolean) {
    Row(
        modifier = Modifier
            .padding(horizontal = PAGE_GUTTER)
            .height(IntrinsicSize.Min),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(
            modifier = Modifier.width(7.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier
                    .width(1.dp)
                    .height(10.dp)
                    .background(
                        if (isFirst) Color.Transparent else MaterialTheme.colorScheme.outlineVariant
                    )
            )
            Box(
                Modifier
                    .size(7.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
            )
            Box(
                Modifier
                    .width(1.dp)
                    .weight(1f)
                    .background(MaterialTheme.colorScheme.outlineVariant)
            )
        }

        Column(Modifier.padding(bottom = 16.dp)) {
            Text(
                text = milestone.date,
                style = MaterialTheme.typography.labelMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = stringResource(milestone.titleRes),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            milestone.detailRes?.let {
                Text(
                    text = stringResource(it),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private class Milestone(
    /** Not localised: it is a date in digits either way. */
    val date: String,
    @param:StringRes val titleRes: Int,
    @param:StringRes val detailRes: Int? = null,
)

private val goals = listOf(
    R.string.about_goal_1,
    R.string.about_goal_2,
    R.string.about_goal_3,
)

private val milestones = listOf(
    Milestone("2019", R.string.milestone_founded, R.string.milestone_founded_detail),
    Milestone("2022 / 12", R.string.milestone_sea, R.string.milestone_sea_detail),
    Milestone("2023 / 03", R.string.milestone_bloomberg),
    Milestone("2023 / 12", R.string.milestone_careers, R.string.milestone_careers_taipei_office),
    Milestone("2024 / 01", R.string.milestone_umc),
    Milestone("2024 / 04·06·07", R.string.milestone_careers, R.string.milestone_careers_partners),
    Milestone("2025 / 04", R.string.milestone_uob),
    Milestone("2025 / 09", R.string.milestone_orientation),
    Milestone("2026 / 03", R.string.milestone_wbc),
    Milestone("2026 / 03", R.string.milestone_hsbc),
)
