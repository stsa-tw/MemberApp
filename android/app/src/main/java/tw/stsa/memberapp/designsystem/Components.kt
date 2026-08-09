package tw.stsa.memberapp.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * A group of related rows, as a Material container on the page.
 *
 * The rows inside are [SectionRow]s and the tone comes from
 * [sectionContainer] — a faintly raised block on a plain page, which is the way
 * round Material stacks it. It used to be the reverse (white cards on a tinted
 * page), which is `UITableView.insetGrouped` and read as an iOS screen no matter
 * what the colours were.
 *
 * Hand-rolled rather than a `LazyColumn` of list items because Home mixes list
 * rows with a hero banner and a two-up grid, and one scrolling column keeps
 * that in a single scroll. The screens whose lists are unbounded — Events, and
 * Offers once it has a backend — pass their rows to a `LazyColumn` instead and
 * use [SectionContainerModifier] for the same look.
 */
@Composable
fun SectionCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .padding(horizontal = Theme.Metrics.gutter)
            .fillMaxWidth()
            .then(SectionContainerModifier()),
        content = content,
    )
}

/** The clip-and-fill half of [SectionCard], for callers that supply their own layout. */
@Composable
fun SectionContainerModifier(): Modifier = Modifier
    .clip(RoundedCornerShape(Theme.Radius.list))
    .background(MaterialTheme.colorScheme.sectionContainer)

/**
 * Section label above a [SectionCard] or a list.
 *
 * Sentence case in the app's own type ramp. The uppercase, letter-spaced version
 * this replaced is the iOS grouped-table header — invisible in Chinese, where
 * `uppercase()` does nothing, and unmistakably foreign in English.
 *
 * [inset] has to match where the rows below it start, or the header hangs off to
 * one side of its own section. Inside a [SectionCard] that is two gutters — one
 * for the card, one for the row within it — which is the default. A list that
 * runs edge to edge has only the row's own gutter, and passes it.
 */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    inset: Dp = Theme.Metrics.gutter * 2,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = inset, end = Theme.Metrics.gutter)
            .padding(bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        trailing?.invoke()
    }
}

/** Hairline between rows in a section, starting inside the row. */
@Composable
fun RowSeparator(inset: Dp = 16.dp) {
    HorizontalDivider(
        modifier = Modifier.padding(start = inset),
        color = MaterialTheme.colorScheme.outlineVariant,
    )
}

/**
 * The full-width brand button that anchors Welcome, Deal Detail and the event
 * CTA — the counterpart of iOS's `BrandButtonStyle`.
 */
@Composable
fun BrandButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = Theme.Metrics.ctaHeight),
        shape = RoundedCornerShape(Theme.Radius.button),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary,
        ),
    ) {
        content()
    }
}

/** The same CTA without the fill, for secondary placements. */
@Composable
fun BrandTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TextButton(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = Theme.Metrics.ctaHeight),
        shape = RoundedCornerShape(Theme.Radius.button),
    ) {
        Text(text, style = MaterialTheme.typography.titleSmall)
    }
}

/**
 * One row of a [SectionCard]: label on the left, value or control on the right.
 *
 * A Material `ListItem` rather than a hand-built `Row`, so the heights, paddings
 * and text roles are the platform's. There is no trailing chevron: Android says
 * "this responds to a tap" with the ripple, and a disclosure indicator on every
 * row is the single loudest iOS tell in a list.
 */
@Composable
fun SectionRow(
    label: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    supporting: String? = null,
    icon: ImageVector? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(label) },
        modifier = modifier.then(
            if (onClick != null) {
                Modifier.clickable(role = Role.Button, onClick = onClick)
            } else {
                Modifier
            }
        ),
        supportingContent = supporting?.let { { Text(it) } },
        leadingContent = icon?.let {
            {
                Icon(it, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
        },
        trailingContent = when {
            trailing != null -> trailing
            value != null -> {
                {
                    Text(
                        text = value,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> null
        },
        // The section behind it already carries the tone; a second one here
        // would stack two containers.
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

/** Explanatory paragraph under a [SectionCard]. [inset] follows [SectionHeader]. */
@Composable
fun SectionFooter(
    text: String,
    modifier: Modifier = Modifier,
    inset: Dp = Theme.Metrics.gutter * 2,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = inset)
            .padding(top = 8.dp),
    )
}

/**
 * The same paragraph directly *under a header*, introducing the rows rather than
 * trailing them.
 *
 * A caption that explains what a list is has to be read before the list, not
 * after it. Left below the rows it reads as a stray sentence belonging to
 * whatever comes next.
 */
@Composable
fun SectionIntro(
    text: String,
    modifier: Modifier = Modifier,
    inset: Dp = Theme.Metrics.gutter * 2,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = inset)
            .padding(bottom = 12.dp),
    )
}

/** Section title used on the About page, where the sections are prose, not rows. */
@Composable
fun BrandSectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier,
    )
}
