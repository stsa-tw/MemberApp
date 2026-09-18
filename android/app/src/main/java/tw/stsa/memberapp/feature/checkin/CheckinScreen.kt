package tw.stsa.memberapp.feature.checkin

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.IndicoAuthConfiguration
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.BrandTextButton
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.model.CheckinRegistration
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * The 報到 door scanner, for one registration form.
 *
 * One camera, two QR formats, one outcome sheet. The worker never chooses which
 * kind of code they are scanning — that is the point of the screen. Which form
 * they are working *is* chosen, on the organiser screen, because an event can
 * carry several and each keeps its own registrations and its own check-ins.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckinScreen(navController: NavHostController, eventId: String, formId: Int) {
    val container = LocalAppContainer.current
    val event = container.events.events.firstOrNull { it.id == eventId } ?: return
    val numericId = event.id.toIntOrNull() ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val indico = container.indico
    val session = remember(numericId, formId) { CheckinSession(numericId, formId, indico) }

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
    var isPickingByName by remember { mutableStateOf(false) }
    // Undo is one tap from the screen that admits people, so it asks first.
    // Nothing else here can take an arrival back off the record.
    var undoing by remember { mutableStateOf<CheckinRegistration?>(null) }

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

    // And re-asked every few seconds after that, because this is not the only
    // door: without it the count below the viewfinder is the one this phone
    // started with, and a member another 幹部 already admitted scans here as a
    // first arrival. Tied to RESUMED so it stops while the app is in the
    // background, where the camera is down and nobody is at the desk.
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(session, lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) { session.autoRefresh() }
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
                                session.expectedCount,
                            ),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            text = stringResource(R.string.checkin_hint),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        // Under the hint rather than beside the camera: scanning
                        // is what this screen is for, and the fallback should be
                        // findable without competing with it.
                        BrandTextButton(
                            text = stringResource(R.string.checkin_manual),
                            onClick = { isPickingByName = true },
                        )
                    }
                }
            }
        }
    }

    if (isPickingByName) {
        ModalBottomSheet(
            onDismissRequest = { isPickingByName = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            ManualPicker(
                registrations = session.registrations,
                onPick = { registration ->
                    isPickingByName = false
                    // Straight into the same confirmation a scan produces, so a
                    // name picked off a list is still a name read back to the
                    // person standing there before anything is written.
                    outcome = Outcome.Found(registration)
                },
            )
        }
    }

    undoing?.let { registration ->
        UndoDialog(
            onDismiss = { undoing = null },
            onConfirm = {
                undoing = null
                scope.launch {
                    outcome = try {
                        val updated = session.checkIn(registration, checkedIn = false)
                        container.checkin.update(updated)
                        // Back to the screen a worker who undid the wrong person
                        // needs next: the same name, with 確認報到 under it.
                        Outcome.Found(updated)
                    } catch (error: CheckinError) {
                        Outcome.Failed(
                            error.message(context),
                            error is CheckinError.NeedsAuthorization,
                        )
                    }
                }
            },
        )
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
                            val updated = session.checkIn(registration)
                            // The organiser screen behind this one shows the same
                            // count, so it learns what the door just did rather
                            // than refetching the roster on the way back.
                            container.checkin.update(updated)
                            Outcome.Done(updated)
                        } catch (error: CheckinError) {
                            Outcome.Failed(
                                error.message(context),
                                error is CheckinError.NeedsAuthorization,
                            )
                        }
                    }
                },
                onUndo = { undoing = it },
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
    onUndo: (CheckinRegistration) -> Unit,
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
                // The organiser's own marks, under the name because they are
                // what the desk acts on next — a 素食 chip decides which bag
                // somebody is handed.
                RegistrationTagChips(outcome.registration.tags)
                if (outcome.registration.checkedIn) {
                    Text(
                        text = alreadyLabel(outcome.registration),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (outcome.registration.isAdmissible && !outcome.registration.checkedIn) {
                    BrandButton(
                        onClick = { onConfirm(outcome.registration) },
                        enabled = !isSubmitting,
                    ) {
                        Text(stringResource(R.string.checkin_confirm))
                    }
                }
                // Where 再次報到 used to be. PATCHing a flag that is already true
                // changes nothing and said so to nobody; what a worker actually
                // reaches for on a second scan is the way back out.
                if (outcome.registration.checkedIn) {
                    BrandTextButton(
                        text = stringResource(R.string.checkin_undo),
                        onClick = { onUndo(outcome.registration) },
                        enabled = !isSubmitting,
                    )
                }
            }

            is Outcome.Done -> {
                Message(stringResource(R.string.checkin_done), outcome.registration.fullName)
                RegistrationTagChips(outcome.registration.tags)
                BrandButton(onClick = onDismiss) { Text(stringResource(R.string.checkin_continue)) }
                // The wrong person is admitted at the moment the sheet says so,
                // not five screens later, so the correction lives here too.
                BrandTextButton(
                    text = stringResource(R.string.checkin_undo),
                    onClick = { onUndo(outcome.registration) },
                    enabled = !isSubmitting,
                )
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

/**
 * Asked before an arrival is taken back off Indico's record — the one thing on
 * this screen that undoes rather than records.
 */
@Composable
internal fun UndoDialog(onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.checkin_undo_title)) },
        text = { Text(stringResource(R.string.checkin_undo_detail)) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.checkin_undo))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.checkin_undo_cancel))
            }
        },
    )
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


/**
 * The door's fallback: find somebody on the list by name, when there is no code
 * to scan.
 *
 * Deliberately not the same act as a scan, and worth being clear about. A member
 * card proves the person authenticated within the last 300 seconds and a ticket
 * proves they hold the registration; a name picked off a list proves nothing at
 * all. It is the worker's judgement — which is what Indico's own check-in app
 * asks for here too.
 *
 * It exists because the alternative at a real door is worse. A member with a
 * flat phone, or a ticket in an inbox they cannot reach, and a queue behind
 * them, is admitted on somebody's word either way; the only question is whether
 * the app records it or a paper list does.
 *
 * Nothing is written from here. Picking a name opens the same [OutcomeSheet] a
 * scan does, with the same confirmation and the same refusal for a withdrawn
 * registration.
 */
@Composable
private fun ManualPicker(
    registrations: List<CheckinRegistration>,
    onPick: (CheckinRegistration) -> Unit,
) {
    var query by remember { mutableStateOf("") }

    // Searched and sorted the same way the roster on 幹部功能 is — see
    // CheckinRegistration.matches() and ROSTER_ORDER, which are the one copy of
    // both rules.
    val matches = registrations
        .filter { it.matches(query) }
        .sortedWith(CheckinRegistration.ROSTER_ORDER)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            singleLine = true,
            label = { Text(stringResource(R.string.checkin_manual_search)) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Theme.Metrics.gutter),
        )

        if (matches.isEmpty()) {
            Text(
                text = stringResource(R.string.checkin_manual_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
            )
        } else {
            LazyColumn(modifier = Modifier.heightIn(max = 420.dp)) {
                items(matches, key = { it.id }) { registration ->
                    RegistrationRow(registration, onClick = { onPick(registration) })
                    RowSeparator()
                }
            }
        }
    }
}
