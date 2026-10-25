package tw.stsa.memberapp.designsystem

import androidx.compose.foundation.layout.BoxWithConstraintsScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The widest a column of content gets before it stops growing and centres.
 *
 * Every screen here was drawn for a phone held upright. On a wider window — a
 * foldable open, a tablet, a phone on its side — they stretched to the edges,
 * and a card, a button or a line of text twice its intended width reads as a
 * layout that went wrong rather than one with room to breathe. Matches
 * `Theme.Metrics.readableWidth` on iOS.
 */
val ReadableWidth: Dp = 600.dp

/**
 * Holds a scrolling column's content to [ReadableWidth], centred.
 *
 * Goes *after* `verticalScroll` in the chain, so the scroll container itself
 * still spans the window and a drag anywhere across it scrolls.
 */
fun Modifier.readableWidth(): Modifier = this
    .fillMaxWidth()
    .wrapContentWidth(Alignment.CenterHorizontally)
    .widthIn(max = ReadableWidth)

/**
 * The same, for a `LazyColumn`: horizontal content padding that centres its
 * items at [ReadableWidth], so the list still spans the window and scrolls
 * from anywhere across it. Zero on a phone.
 */
fun BoxWithConstraintsScope.readableSidePadding(): Dp =
    ((maxWidth - ReadableWidth) / 2).coerceAtLeast(0.dp)
