package tw.stsa.memberapp.feature.events

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.Checkin
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.IndicoAuthConfiguration
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.BrandTextButton
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.feature.checkin.CheckinError
import tw.stsa.memberapp.feature.checkin.CheckinStore
import tw.stsa.memberapp.feature.checkin.RegistrationRow
import tw.stsa.memberapp.feature.checkin.RegistrationTagChips
import tw.stsa.memberapp.feature.checkin.UndoDialog
import tw.stsa.memberapp.feature.checkin.registrationStateLabel
import tw.stsa.memberapp.model.CheckinRegistration
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * One registration form, the way a 幹部 works it: how many have arrived, the
 * door, and the list.
 *
 * A form is the unit because Indico makes it one — a registration lives inside
 * exactly one form and carries its own `checked_in`, so 報名表 and 遊覽車報名表
 * are two lists, two doors, and two sets of arrivals that never touch.
 *
 * Mirrors `ios/MemberApp/Features/Events/EventFormView.swift`. Reached from
 * `EventOrganiserScreen`, which is the chooser when an event has several forms
 * and delegates straight to [FormContent] when it has one.
 */
@Composable
fun EventFormScreen(navController: NavHostController, eventId: String, formId: Int) {
    val container = LocalAppContainer.current
    val checkin = container.checkin
    val form = checkin.forms(eventId).firstOrNull { it.id == formId }

    LaunchedEffect(eventId) {
        if (checkin.access(eventId) == CheckinStore.Access.ALLOWED) {
            checkin.loadRoster(eventId, container.indico)
        }
    }

    // The number here is the one an organiser trusts, and this is not the only
    // door: another 幹部 on another phone moves it too. So the screen asks Indico
    // on its own every few seconds rather than redrawing what this phone happens
    // to remember, and stops at RESUMED, where nobody is reading it.
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(eventId, lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            checkin.autoRefresh(eventId, container.indico)
        }
    }

    ScreenScaffold(
        title = form?.title?.ifBlank { stringResource(R.string.checkin_form_fallback) }
            ?: stringResource(R.string.checkin_form_fallback),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Theme.Metrics.gutter)
                .padding(top = 16.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            FormContent(
                eventId = eventId,
                formId = formId,
                onOpenDoor = { navController.navigate(Checkin(eventId, formId)) },
            )
        }
    }
}

/** The count, the door and the list — the same wherever the form is shown. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FormContent(eventId: String, formId: Int, onOpenDoor: () -> Unit) {
    val container = LocalAppContainer.current
    val checkin = container.checkin
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Searching the list is the other half of the door. The scanner is faster
    // when there is a code to scan; a name typed here is what a desk falls back
    // to when there is not — a flat phone, a ticket in an unreachable inbox, or
    // a 幹部 who only wants to know whether somebody has arrived yet.
    var query by remember { mutableStateOf("") }

    // Held by id, not by value: the roster behind this refreshes every few
    // seconds and another 幹部 may admit this person while the sheet is open.
    var openedId by remember { mutableStateOf<Int?>(null) }
    var undoing by remember { mutableStateOf<CheckinRegistration?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var needsAuthorization by remember { mutableStateOf(false) }

    // The roster reads on `read:everything`; the flag is a PATCH, which Indico
    // will not take on that grant. A 幹部 who only ever opened the list has never
    // been asked for the wider one, so this screen has to be able to ask.
    val authorize = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        scope.launch {
            runCatching { container.indico.completeAuthorization(result.data) }
            needsAuthorization = !container.indico.canRecordCheckin
        }
    }

    fun write(registration: CheckinRegistration, checkedIn: Boolean) {
        scope.launch {
            error = null
            try {
                checkin.setCheckedIn(registration, checkedIn, container.indico)
                needsAuthorization = false
            } catch (failure: CheckinError) {
                if (failure is CheckinError.NeedsAuthorization) {
                    needsAuthorization = true
                } else {
                    error = failure.message(context)
                }
            }
        }
    }

    Progress(
        checkedIn = checkin.checkedInCount(eventId, formId),
        registered = checkin.registeredCount(eventId, formId),
    )

    BrandButton(onClick = onOpenDoor) {
        Icon(
            imageVector = Icons.Filled.QrCodeScanner,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = stringResource(R.string.checkin_title),
            modifier = Modifier.padding(start = 8.dp),
        )
    }

    val registrations = checkin.registrations(eventId, formId)
    Roster(
        registrations = registrations,
        isLoading = checkin.isLoadingRoster,
        query = query,
        onQueryChange = { query = it },
        onOpen = { openedId = it.id },
    )

    // Read back out of the store rather than remembered, so a check-in made at a
    // door two minutes ago is on this sheet without it knowing anything about it.
    val opened = openedId?.let { id -> registrations.firstOrNull { it.id == id } }
    if (opened != null) {
        ModalBottomSheet(
            onDismissRequest = {
                openedId = null
                error = null
            },
            sheetState = rememberModalBottomSheetState(),
        ) {
            RegistrationSheet(
                registration = opened,
                isSubmitting = checkin.isSubmitting,
                needsAuthorization = needsAuthorization,
                error = error,
                onCheckIn = { write(opened, true) },
                onUndo = { undoing = opened },
                onAuthorize = {
                    authorize.launch(
                        container.indico.authorizationIntent(
                            IndicoAuthConfiguration.CHECKIN_SCOPES,
                        ),
                    )
                },
            )
        }
    }

    undoing?.let { registration ->
        UndoDialog(
            onDismiss = { undoing = null },
            onConfirm = {
                undoing = null
                write(registration, false)
            },
        )
    }
}

/**
 * One person on the roster, opened from the list rather than through a camera.
 *
 * The door is still the ordinary way in: a scan proves the person authenticated
 * within the last 300 seconds, or holds the ticket. This proves nothing of the
 * kind, and it is here because a real desk needs it anyway — a flat phone, a
 * ticket in an inbox nobody can reach, a queue, somebody checked in by mistake a
 * minute ago. Indico's own check-in app makes the same call: its registrant list
 * checks people in and takes it back.
 *
 * Mirrors `ios/MemberApp/Features/Events/RegistrationDetailView.swift`, minus
 * the answers: the list endpoint carries none, and this app has never decoded
 * `registration_data` on either of its screens.
 */
@Composable
private fun RegistrationSheet(
    registration: CheckinRegistration,
    isSubmitting: Boolean,
    needsAuthorization: Boolean,
    error: String?,
    onCheckIn: () -> Unit,
    onUndo: () -> Unit,
    onAuthorize: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Theme.Metrics.gutter)
            .padding(bottom = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(text = registration.fullName, style = MaterialTheme.typography.titleMedium)
        Text(
            text = registration.email,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        RegistrationTagChips(registration.tags)
        Text(
            text = checkinStatus(registration),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        registrationStateLabel(registration)?.let { state ->
            Text(
                text = state,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        when {
            needsAuthorization -> {
                Text(
                    text = stringResource(R.string.error_checkin_needs_authorization),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                BrandButton(onClick = onAuthorize) {
                    Text(stringResource(R.string.checkin_authorize))
                }
            }

            registration.checkedIn -> BrandTextButton(
                text = stringResource(R.string.checkin_undo),
                onClick = onUndo,
                enabled = !isSubmitting,
            )

            registration.isAdmissible -> BrandButton(
                onClick = onCheckIn,
                enabled = !isSubmitting,
            ) {
                Text(stringResource(R.string.checkin_confirm))
            }

            // Withdrawn or rejected, and not checked in: nothing to undo and
            // nobody to admit. Said plainly rather than drawn as a disabled
            // button nobody can explain.
            else -> Text(
                text = stringResource(R.string.checkin_not_admissible_detail),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        if (error != null) {
            Text(
                text = error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * When Indico knows the moment, say it: whether somebody came through an hour
 * ago or ten seconds ago is the difference between a queue-jumper and a
 * double-tap, and it is what tells a 幹部 they are undoing the right arrival.
 */
@Composable
private fun checkinStatus(registration: CheckinRegistration): String {
    if (!registration.checkedIn) return stringResource(R.string.checkin_not_yet)
    val moment = registration.checkedInAt ?: return stringResource(R.string.checkin_already)
    val formatted = DateTimeFormatter.ofPattern("HH:mm")
        .withZone(ZoneId.systemDefault())
        .format(moment)
    return stringResource(R.string.checkin_already_at, formatted)
}

/**
 * The number a door actually wants, before anyone opens the scanner: how many
 * are in, out of how many are coming.
 *
 * Withdrawn and rejected registrations are in neither half. They stay on
 * Indico's list — `~is_deleted` is the only filter its API applies — but nobody
 * is waiting for them, and counting them made a denominator that could not be
 * reached. Indico's own `active_registration_count` draws the line in the same
 * place, so this number and the one on its management page agree.
 */
@Composable
private fun Progress(checkedIn: Int, registered: Int) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.card))
            .background(MaterialTheme.colorScheme.sectionContainer)
            .padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = "$checkedIn / $registered",
            style = MaterialTheme.typography.displaySmall.copy(fontSize = 44.sp),
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = stringResource(R.string.checkin_checked_in),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Roster(
    registrations: List<CheckinRegistration>,
    isLoading: Boolean,
    query: String,
    onQueryChange: (String) -> Unit,
    onOpen: (CheckinRegistration) -> Unit,
) {
    if (registrations.isNotEmpty()) {
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            singleLine = true,
            label = { Text(stringResource(R.string.checkin_roster_search)) },
            modifier = Modifier.fillMaxWidth(),
        )
    }

    when {
        isLoading && registrations.isEmpty() -> Column(
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator()
        }

        registrations.isEmpty() -> Text(
            text = stringResource(R.string.checkin_roster_empty),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
        )

        else -> {
            val shown = registrations
                .filter { it.matches(query) }
                .sortedWith(CheckinRegistration.ROSTER_ORDER)

            if (shown.isEmpty()) {
                // A search matching nobody is not an empty form, and saying so
                // is the difference between "nobody registered" and "check the
                // spelling".
                Text(
                    text = stringResource(R.string.checkin_manual_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Theme.Radius.card))
                        .background(MaterialTheme.colorScheme.sectionContainer),
                ) {
                    shown.forEachIndexed { index, registration ->
                        if (index > 0) RowSeparator()
                        RegistrationRow(registration, onClick = { onOpen(registration) })
                    }
                }
            }
        }
    }
}
