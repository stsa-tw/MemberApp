package tw.stsa.memberapp.feature.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.SectionCard
import tw.stsa.memberapp.designsystem.SectionFooter
import tw.stsa.memberapp.designsystem.SectionHeader
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.readableWidth
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * The events behind the 我的 tab's count: the ones the member was checked in
 * to, and — separately, so the number above it is not diluted — the ones they
 * registered for and were not.
 *
 * Reads what [AttendanceStore] already holds. It asks for nothing itself, so
 * opening it is instant and it can never disagree with the count that led here.
 * Mirrors `AttendanceListView` on iOS.
 */
@Composable
fun AttendanceScreen(navController: NavHostController) {
    val attendance = LocalAppContainer.current.attendance
    val attended = attendance.attended.orEmpty()
    val others = attendance.notAttended.orEmpty()

    ScreenScaffold(
        title = stringResource(R.string.attendance_title),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .readableWidth()
                .padding(top = 6.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Section(stringResource(R.string.attendance_attended), attended, stringResource(R.string.attendance_none))
            if (others.isNotEmpty()) {
                Section(stringResource(R.string.attendance_not_attended), others, null)
            }
            SectionFooter(stringResource(R.string.attendance_year_note))
        }
    }
}

@Composable
private fun Section(title: String, entries: List<AttendanceStore.Entry>, empty: String?) {
    Column {
        SectionHeader(title)
        SectionCard {
            if (entries.isEmpty() && empty != null) {
                Text(
                    text = empty,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
                )
            }
            entries.forEachIndexed { index, entry ->
                if (index > 0) RowSeparator()
                EntryRow(entry)
            }
        }
    }
}

@Composable
private fun EntryRow(entry: AttendanceStore.Entry) {
    val uriHandler = LocalUriHandler.current
    val url = entry.url
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (url != null) Modifier.clickable { uriHandler.openUri(url) } else Modifier)
            .padding(horizontal = Theme.Metrics.gutter, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = entry.title, style = MaterialTheme.typography.bodyLarge)
            entry.start?.let { start ->
                Text(
                    text = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                        .format(start.atZone(entry.zone)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        tag(entry)?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Where an unattended registration stands. Says only what Indico says — a
 * future event is not "missed", and a pending one is not "no show".
 */
@Composable
private fun tag(entry: AttendanceStore.Entry): String? =
    if (entry.checkedIn) {
        null
    } else {
        when (entry.status) {
            "no_show" -> stringResource(R.string.attendance_status_no_show)
            "upcoming" -> stringResource(R.string.attendance_status_upcoming)
            "ongoing" -> stringResource(R.string.attendance_status_ongoing)
            "pending" -> stringResource(R.string.attendance_status_pending)
            else -> null
        }
    }
