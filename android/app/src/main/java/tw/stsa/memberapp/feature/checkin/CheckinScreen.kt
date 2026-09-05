package tw.stsa.memberapp.feature.checkin

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.IndicoAuthConfiguration
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.BrandTextButton
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.model.CheckinRegistration
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * The 報到 door scanner.
 *
 * One camera, two QR formats, one outcome sheet. The worker never chooses which
 * kind of code they are scanning — that is the point of the screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckinScreen(navController: NavHostController, eventId: String) {
    val container = LocalAppContainer.current
    val event = container.events.events.firstOrNull { it.id == eventId } ?: return
    val numericId = event.id.toIntOrNull() ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val indico = container.indico
    val session = remember(numericId) { CheckinSession(numericId, indico) }

    var hasCamera by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasCamera = granted }

    var outcome by remember { mutableStateOf<Outcome?>(null) }

    // Widening the grant is an activity result on Android, the same shape the
    // ticket screen uses for the first link. Only this staffer is prompted.
    val authorize = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        scope.launch {
            runCatching { indico.completeAuthorization(result.data) }
            outcome = null
            session.load()
        }
    }

    var isResolving by remember { mutableStateOf(false) }
    // The same code stays in frame for as long as the worker holds it there.
    var lastScanned by remember { mutableStateOf<String?>(null) }
    var lastScannedAt by remember { mutableStateOf(0L) }

    LaunchedEffect(Unit) {
        if (!hasCamera) permission.launch(Manifest.permission.CAMERA)
        session.load()
    }

    ScreenScaffold(
        title = stringResource(R.string.checkin_title),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (val phase = session.phase) {
                is CheckinSession.Phase.Idle,
                is CheckinSession.Phase.Loading,
                -> Centered { CircularProgressIndicator() }

                is CheckinSession.Phase.Denied -> Centered {
                    Message(
                        title = stringResource(R.string.checkin_denied),
                        detail = stringResource(R.string.checkin_denied_detail),
                    )
                }

                is CheckinSession.Phase.Failed -> Centered {
                    Message(
                        title = stringResource(R.string.checkin_failed_to_start),
                        detail = phase.error.message(context),
                    )
                }

                is CheckinSession.Phase.Ready -> {
                    if (!hasCamera) {
                        Centered {
                            Message(
                                title = stringResource(R.string.checkin_camera_needed),
                                detail = stringResource(R.string.checkin_camera_needed_detail),
                            )
                        }
                    } else {
                        CodeScanner(
                            modifier = Modifier.fillMaxSize(),
                            onScan = { raw ->
                                val now = System.currentTimeMillis()
                                val isRepeat = raw == lastScanned && now - lastScannedAt < RESCAN_MS
                                if (outcome != null || isResolving || isRepeat) return@CodeScanner

                                lastScanned = raw
                                lastScannedAt = now
                                isResolving = true
                                scope.launch {
                                    outcome = try {
                                        Outcome.Found(session.resolve(raw))
                                    } catch (error: CheckinError) {
                                        Outcome.Failed(
                                            error.message(context),
                                            error is CheckinError.NeedsAuthorization,
                                        )
                                    } finally {
                                        isResolving = false
                                    }
                                }
                            },
                        )
                    }

                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 32.dp, start = 20.dp, end = 20.dp)
                            .background(
                                MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
                                RoundedCornerShape(Theme.Radius.card),
                            )
                            .padding(horizontal = 20.dp, vertical = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = stringResource(
                                R.string.checkin_progress,
                                session.checkedInCount,
                                session.registrations.size,
                            ),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            text = stringResource(R.string.checkin_hint),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }

    val current = outcome
    if (current != null) {
        ModalBottomSheet(
            onDismissRequest = { outcome = null },
            sheetState = rememberModalBottomSheetState(),
        ) {
            OutcomeSheet(
                outcome = current,
                isSubmitting = session.isSubmitting,
                onConfirm = { registration ->
                    scope.launch {
                        outcome = try {
                            Outcome.Done(session.checkIn(registration))
                        } catch (error: CheckinError) {
                            Outcome.Failed(
                                error.message(context),
                                error is CheckinError.NeedsAuthorization,
                            )
                        }
                    }
                },
                onDismiss = { outcome = null },
                onAuthorize = {
                    authorize.launch(
                        indico.authorizationIntent(IndicoAuthConfiguration.CHECKIN_SCOPES),
                    )
                },
            )
        }
    }
}

/**
 * Shown after every scan, including the ones that worked.
 *
 * A member card is a bearer credential for its 300 seconds, so the name is
 * always put in front of the worker to check against the person standing there.
 * Nobody is checked in without that confirmation.
 */
@Composable
private fun OutcomeSheet(
    outcome: Outcome,
    isSubmitting: Boolean,
    onConfirm: (CheckinRegistration) -> Unit,
    onDismiss: () -> Unit,
    onAuthorize: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        when (outcome) {
            is Outcome.Found -> {
                Message(outcome.registration.fullName, outcome.registration.email)
                if (outcome.registration.checkedIn) {
                    Text(
                        text = alreadyLabel(outcome.registration),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                BrandButton(
                    onClick = { onConfirm(outcome.registration) },
                    enabled = !isSubmitting,
                ) {
                    Text(
                        stringResource(
                            if (outcome.registration.checkedIn) {
                                R.string.checkin_confirm_again
                            } else {
                                R.string.checkin_confirm
                            },
                        ),
                    )
                }
            }

            is Outcome.Done -> {
                Message(stringResource(R.string.checkin_done), outcome.registration.fullName)
                BrandButton(onClick = onDismiss) { Text(stringResource(R.string.checkin_continue)) }
            }

            is Outcome.Failed -> {
                Message(stringResource(R.string.checkin_failed), outcome.reason)
                if (outcome.needsAuthorization) {
                    BrandButton(onClick = onAuthorize) {
                        Text(stringResource(R.string.checkin_authorize))
                    }
                }
                BrandTextButton(text = stringResource(R.string.checkin_continue), onClick = onDismiss)
            }
        }
    }
}

@Composable
private fun alreadyLabel(registration: CheckinRegistration): String {
    val moment = registration.checkedInAt ?: return stringResource(R.string.checkin_already)
    val formatted = DateTimeFormatter.ofPattern("HH:mm")
        .withZone(ZoneId.systemDefault())
        .format(moment)
    return stringResource(R.string.checkin_already_at, formatted)
}

@Composable
private fun Message(title: String, detail: String?) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        if (detail != null) {
            Text(
                text = detail,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun Centered(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Transparent)
            .padding(horizontal = 32.dp),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

private sealed interface Outcome {
    /** Resolved, waiting for the worker to confirm it is the right person. */
    data class Found(val registration: CheckinRegistration) : Outcome

    data class Done(val registration: CheckinRegistration) : Outcome

    data class Failed(val reason: String, val needsAuthorization: Boolean = false) : Outcome
}

private const val RESCAN_MS = 3_000L

