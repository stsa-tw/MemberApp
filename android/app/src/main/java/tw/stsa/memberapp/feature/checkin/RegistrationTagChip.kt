package tw.stsa.memberapp.feature.checkin

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import tw.stsa.memberapp.model.RegistrationTag

/**
 * One of Indico's registration tags, drawn the way the organiser set it.
 *
 * Mirrors `ios/MemberApp/Features/Scan/RegistrationTagChip.swift`. The colour is
 * the tag's whole point at a door: 幹部 pick them so a row can be read at a
 * glance across a desk, and a list of identical grey chips would throw that
 * away. So the tint is Indico's and only the *text* is ours — drawn in the
 * ordinary label colour rather than the tag's, because Semantic UI's palette was
 * chosen against a white page and half of it disappears against a dark one.
 */
@Composable
fun RegistrationTagChip(tag: RegistrationTag, modifier: Modifier = Modifier) {
    val tint = tag.tint()
    Text(
        text = tag.title,
        style = MaterialTheme.typography.labelSmall,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
            .background(tint.copy(alpha = 0.18f), CircleShape)
            .border(0.5.dp, tint.copy(alpha = 0.4f), CircleShape)
            .padding(horizontal = 7.dp, vertical = 2.dp),
    )
}

/**
 * Every tag on a registration, wrapped onto as many lines as it takes.
 *
 * Wrapping rather than truncating because a tag nobody can see is worse than one
 * more line: 素食 is the tag that decides what the desk hands somebody.
 */
@Composable
fun RegistrationTagChips(tags: List<RegistrationTag>, modifier: Modifier = Modifier) {
    if (tags.isEmpty()) return
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        tags.forEach { RegistrationTagChip(it) }
    }
}

/**
 * Semantic UI's own hex values for the names Indico stores.
 *
 * Written out because the palette is Semantic UI's and nothing else in the app
 * knows it — Material's error red is not `#DB2828`, and a tag that reads as a
 * different colour here than on Indico's page is one the organiser has to think
 * about twice.
 *
 * `black` and `grey`, and anything Indico adds later, fall back to the label
 * grey: the one colour guaranteed to stay visible in both schemes, which black
 * is not.
 */
@Composable
private fun RegistrationTag.tint(): Color = when (color) {
    "red" -> Color(0xFFDB2828)
    "orange" -> Color(0xFFF2711C)
    "yellow" -> Color(0xFFFBBD08)
    "olive" -> Color(0xFFB5CC18)
    "green" -> Color(0xFF21BA45)
    "teal" -> Color(0xFF00B5AD)
    "blue" -> Color(0xFF2185D0)
    "violet" -> Color(0xFF6435C9)
    "purple" -> Color(0xFFA333C8)
    "pink" -> Color(0xFFE03997)
    "brown" -> Color(0xFFA5673F)
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}
