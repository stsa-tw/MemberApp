package tw.stsa.memberapp.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import kotlinx.coroutines.delay
import tw.stsa.memberapp.BuildConfig
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.app.Settings
import tw.stsa.memberapp.designsystem.SectionCard
import tw.stsa.memberapp.designsystem.SectionHeader
import tw.stsa.memberapp.designsystem.SectionFooter
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import java.time.Instant

/**
 * The 我的 tab — what a member actually needs to see about their account.
 *
 * Only reachable behind the auth gate, so there is no sign-in branch; that
 * lives on `WelcomeScreen`. Token plumbing is diagnostic, not member-facing, so
 * it is confined to a debug-only section at the bottom.
 */
@Composable
fun AccountScreen(navController: NavHostController) {
    val auth = LocalAppContainer.current.auth
    val profile = auth.profile

    ScreenScaffold(
        title = stringResource(R.string.account),
        large = true,
        actions = {
            IconButton(onClick = { navController.navigate(Settings) }) {
                Icon(
                    Icons.Filled.Settings,
                    contentDescription = stringResource(R.string.settings),
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
            if (profile != null) {
                Column {
                    SectionHeader(stringResource(R.string.identity))
                    SectionCard {
                        LabeledRow(stringResource(R.string.name), profile.displayName)
                        profile.email?.let { email ->
                            RowSeparator()
                            LabeledRow(stringResource(R.string.email), email) {
                                if (profile.emailVerified == true) {
                                    Icon(
                                        imageVector = Icons.Filled.Verified,
                                        contentDescription = stringResource(R.string.verified),
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(16.dp),
                                    )
                                }
                            }
                        }
                        profile.school?.let { school ->
                            RowSeparator()
                            LabeledRow(stringResource(R.string.school), school)
                        }
                    }
                }

                // Shown because members care which departments they are in. Note
                // that these drive display only — see the comment on
                // Profile.groups.
                if (profile.groups.isNotEmpty()) {
                    Column {
                        SectionHeader(stringResource(R.string.groups))
                        SectionCard {
                            profile.groups.forEachIndexed { index, group ->
                                if (index > 0) RowSeparator()
                                Text(
                                    text = group,
                                    style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(
                                            horizontal = Theme.Metrics.gutter,
                                            vertical = 12.dp,
                                        ),
                                )
                            }
                        }
                    }
                }
            }

            if (BuildConfig.DEBUG) TokenDiagnostics()
        }
    }
}

@Composable
private fun LabeledRow(
    label: String,
    value: String? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Theme.Metrics.gutter, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        if (value != null) Text(text = value, style = MaterialTheme.typography.bodyLarge)
        trailing?.invoke()
    }
}

/**
 * Session plumbing, for checking that silent refresh is working.
 *
 * Guarded by `BuildConfig.DEBUG`, which is a compile-time constant, so R8 drops
 * the whole branch from a release build — the same guarantee `#if DEBUG` gives
 * on iOS. That is what makes it safe to print `sub` and token timings here.
 */
@Composable
private fun TokenDiagnostics() {
    val auth = LocalAppContainer.current.auth
    var snapshot by remember { mutableStateOf(auth.snapshot()) }
    var now by remember { mutableStateOf(Instant.now()) }

    LaunchedEffect(Unit) {
        auth.refreshIfNeeded()
        while (true) {
            now = Instant.now()
            snapshot = auth.snapshot()
            delay(1000)
        }
    }

    Column {
        SectionHeader(stringResource(R.string.diagnostics_header))
        SectionCard {
            LabeledRow("sub") {
                SelectionContainer {
                    Text(
                        text = auth.profile?.sub ?: "—",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            RowSeparator()
            LabeledRow(
                stringResource(R.string.diagnostics_refresh_token),
                stringResource(
                    if (snapshot.hasRefreshToken) {
                        R.string.diagnostics_present
                    } else {
                        R.string.diagnostics_absent
                    }
                ),
            )
            RowSeparator()
            LabeledRow(
                stringResource(R.string.diagnostics_access_token_expiry),
                remaining(snapshot.accessTokenExpiry, now),
            )
            snapshot.scopesGranted?.let { scopes ->
                RowSeparator()
                LabeledRow(stringResource(R.string.diagnostics_scopes), scopes)
            }
        }
        SectionFooter(stringResource(R.string.diagnostics_footer))
    }
}

@Composable
private fun remaining(expiry: Instant?, now: Instant): String {
    if (expiry == null) return "—"
    if (!expiry.isAfter(now)) return stringResource(R.string.diagnostics_expired_renews)
    val seconds = expiry.epochSecond - now.epochSecond
    return stringResource(R.string.diagnostics_remaining, seconds / 60, seconds % 60)
}
