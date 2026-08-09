package tw.stsa.memberapp.feature.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.BuildConfig
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.About
import tw.stsa.memberapp.app.AppSettings
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.BiometricGate
import tw.stsa.memberapp.designsystem.SectionCard
import tw.stsa.memberapp.designsystem.SectionHeader
import tw.stsa.memberapp.designsystem.SectionFooter
import tw.stsa.memberapp.designsystem.SectionRow
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme

@Composable
fun SettingsScreen(navController: NavHostController) {
    val container = LocalAppContainer.current
    val settings = container.settings
    val auth = container.auth
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val languageUnavailable = stringResource(R.string.language_settings_unavailable)

    ScreenScaffold(
        title = stringResource(R.string.settings),
        onBack = { navController.popBackStack() },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(top = 6.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Column {
                SectionHeader(stringResource(R.string.appearance))
                SectionCard {
                    SingleChoiceSegmentedButtonRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(Theme.Metrics.gutter),
                    ) {
                        AppSettings.Appearance.entries.forEachIndexed { index, appearance ->
                            SegmentedButton(
                                selected = settings.appearance == appearance,
                                onClick = { settings.appearance = appearance },
                                shape = SegmentedButtonDefaults.itemShape(
                                    index = index,
                                    count = AppSettings.Appearance.entries.size,
                                ),
                            ) {
                                Text(stringResource(appearance.labelRes))
                            }
                        }
                    }
                }
            }

            if (BiometricGate.isAvailable(context)) {
                Column {
                    SectionHeader(stringResource(R.string.security))
                    SectionCard {
                        // The whole row toggles, not just the switch: a 48dp
                        // target across the width is what Material asks for, and
                        // aiming at the thumb is not something anyone should
                        // have to do.
                        SectionRow(
                            label = stringResource(R.string.require_auth_for_card),
                            onClick = {
                                settings.requireBiometricsForCard =
                                    !settings.requireBiometricsForCard
                            },
                            trailing = {
                                Switch(
                                    checked = settings.requireBiometricsForCard,
                                    onCheckedChange = {
                                        settings.requireBiometricsForCard = it
                                    },
                                )
                            },
                        )
                    }
                    SectionFooter(
                        stringResource(
                            R.string.require_auth_for_card_footer,
                            BiometricGate.biometryName(context),
                        )
                    )
                }
            }

            Column {
                SectionCard {
                    // Android owns per-app language from 13 onward. A custom
                    // picker would fight that setting and need a restart to take
                    // effect, so this defers to it — the same call the iOS side
                    // makes with openSettingsURLString.
                    SectionRow(
                        label = stringResource(R.string.language),
                        value = currentLanguage(),
                        onClick = {
                            // Guarded: the per-app language screen is not on
                            // every build of Android, and an unresolved
                            // startActivity is an ActivityNotFoundException, not
                            // a no-op.
                            if (!context.openLanguageSettings()) {
                                scope.launch { snackbarHostState.showSnackbar(languageUnavailable) }
                            }
                        },
                    )
                }
                SectionFooter(stringResource(R.string.language_footer))
            }

            Column {
                SectionHeader(stringResource(R.string.about))
                SectionCard {
                    SectionRow(
                        label = stringResource(R.string.about_stsa),
                        onClick = { navController.navigate(About) },
                    )
                    RowSeparator()
                    SectionRow(
                        label = stringResource(R.string.version),
                        value = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    )
                    RowSeparator()
                    SectionRow(
                        label = stringResource(R.string.stsa_website),
                        onClick = { uriHandler.openUri("https://stsa.tw") },
                    )
                    RowSeparator()
                    SectionRow(
                        label = stringResource(R.string.event_system),
                        onClick = { uriHandler.openUri("https://event.stsa.tw") },
                    )
                }
            }

            Column {
                SectionCard {
                    TextButton(
                        onClick = {
                            auth.logout()
                            // The graph is inside the signed-in branch of
                            // RootScreen, so it goes away with the session; there
                            // is nothing to pop.
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            text = stringResource(R.string.sign_out),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
                SectionFooter(stringResource(R.string.sign_out_footer))
            }
        }
    }
}

/**
 * The localisation actually in use, not the device language — they differ once
 * someone overrides it in the system's per-app language screen.
 */
@Composable
private fun currentLanguage(): String {
    // LocalConfiguration rather than LocalContext.resources: the composition
    // reads it as state, so switching the app's language redraws this row
    // instead of leaving the old name behind.
    val locale = LocalConfiguration.current.locales[0]
    return locale.getDisplayLanguage(locale)
        .replaceFirstChar { it.uppercase(locale) }
}

/**
 * Opens the system's per-app language screen, falling back to the app's detail
 * page. Returns false when neither resolves.
 *
 * The app has to be listed in Settings → System → Languages for the first of
 * these to lead anywhere, and it is only listed because `generateLocaleConfig`
 * in build.gradle.kts declares which languages it ships. Without that the intent
 * resolves to nothing and this row used to take the app down with it.
 */
private fun Context.openLanguageSettings(): Boolean {
    val target = Uri.fromParts("package", packageName, null)
    // ACTION_APP_LOCALE_SETTINGS only exists from 13. Below that the app detail
    // page is the closest thing that leads somewhere useful.
    val actions = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(AndroidSettings.ACTION_APP_LOCALE_SETTINGS)
        }
        add(AndroidSettings.ACTION_APPLICATION_DETAILS_SETTINGS)
    }

    for (action in actions) {
        try {
            startActivity(Intent(action, target))
            return true
        } catch (_: ActivityNotFoundException) {
            // Try the next one down.
        }
    }
    return false
}
