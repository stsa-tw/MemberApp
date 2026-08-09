package tw.stsa.memberapp.feature.card

import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.navigation.NavHostController
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.BiometricGate
import tw.stsa.memberapp.designsystem.BrandTextButton
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.groupedCard
import java.time.Instant
import kotlin.math.max

private const val QR_SIZE_DP = 152

@Composable
fun MemberCardScreen(navController: NavHostController) {
    val container = LocalAppContainer.current
    val auth = container.auth
    val codes = container.codes
    val settings = container.settings

    val activity = LocalActivity.current as? FragmentActivity
    val scope = rememberCoroutineScope()
    // Resolved in the composition rather than from a Context inside the
    // coroutine, so the prompt follows the app's language like every other
    // string on screen.
    val authReason = stringResource(R.string.card_auth_reason)

    var isUnlocked by remember { mutableStateOf(false) }
    var now by remember { mutableStateOf(Instant.now()) }

    suspend fun unlockIfNeeded() {
        isUnlocked = when {
            !settings.requireBiometricsForCard -> true
            // No FragmentActivity means no BiometricPrompt to show. Falling
            // through beats making the card unreachable, same as a device with
            // no screen lock.
            activity == null -> true
            else -> BiometricGate.authenticate(activity, authReason)
        }
        if (isUnlocked) codes.start(auth)
    }

    LaunchedEffect(Unit) { unlockIfNeeded() }

    DisposableEffect(Unit) {
        onDispose { codes.stop() }
    }

    // Raised so the code scans, and put back on the way out. Scoped to the
    // window rather than the device, which is the part Android makes easier
    // than iOS — nothing to restore if the process dies here.
    DisposableEffect(isUnlocked) {
        val window = activity?.window
        if (isUnlocked && window != null) {
            window.attributes = window.attributes.apply { screenBrightness = 1f }
        }
        onDispose {
            if (window != null) {
                window.attributes = window.attributes.apply {
                    screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                }
            }
        }
    }

    LaunchedEffect(isUnlocked) {
        while (isUnlocked) {
            now = Instant.now()
            delay(1000)
        }
    }

    ScreenScaffold(
        title = stringResource(R.string.member_card),
        onBack = { navController.popBackStack() },
        actions = {
            TextButton(onClick = { navController.popBackStack() }) {
                Text(stringResource(R.string.done))
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Theme.Metrics.gutter)
                .padding(top = 6.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (isUnlocked) {
                Card(now = now)
                Text(
                    text = stringResource(R.string.card_footnote),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            } else {
                LockedState(onUnlock = { scope.launch { unlockIfNeeded() } })
            }
        }
    }
}

@Composable
private fun LockedState(onUnlock: () -> Unit) {
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 80.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.Lock,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(40.dp),
        )
        Text(
            text = stringResource(R.string.card_locked),
            style = MaterialTheme.typography.titleMedium,
        )
        BrandTextButton(
            text = stringResource(R.string.unlock_with, BiometricGate.biometryName(context)),
            onClick = onUnlock,
        )
    }
}

@Composable
private fun Card(now: Instant) {
    val container = LocalAppContainer.current
    val auth = container.auth
    val codes = container.codes
    val profile = auth.profile

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Theme.Radius.memberCard))
            .background(MaterialTheme.colorScheme.groupedCard)
            .padding(20.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.card_member_year),
                    style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp),
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.size(6.dp))
                Text(
                    text = profile?.name ?: "—",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                val subtitle = profile?.nickname ?: profile?.preferredUsername
                if (subtitle != null) {
                    Spacer(Modifier.size(3.dp))
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Image(
                painter = painterResource(R.drawable.stsa_logo),
                contentDescription = null,
                modifier = Modifier.size(58.dp),
            )
        }

        Spacer(Modifier.size(18.dp))
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            contentAlignment = Alignment.Center,
        ) {
            QrPanel(now = now)
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Spacer(Modifier.size(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            profile?.school?.let { CardField(stringResource(R.string.card_field_school), it) }
            if (profile?.isOfficer == true) {
                CardField(stringResource(R.string.card_field_role), stringResource(R.string.officer))
            }
            CardField(stringResource(R.string.card_field_code), codeFreshness(codes.expiresAt, now))
        }
    }
}

@Composable
private fun QrPanel(now: Instant) {
    val container = LocalAppContainer.current
    val codes = container.codes
    val auth = container.auth
    val scope = rememberCoroutineScope()
    val payload = codes.payload
    val message = codes.errorMessage

    val sizePx = with(androidx.compose.ui.platform.LocalDensity.current) { QR_SIZE_DP.dp.roundToPx() }
    val image = remember(payload, sizePx) { payload?.let { QrCode.bitmap(it, sizePx) } }

    when {
        image != null -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val expired = codes.hasExpired(now)
            Box(contentAlignment = Alignment.Center) {
                Image(
                    bitmap = image,
                    contentDescription = stringResource(R.string.card_qr_description),
                    contentScale = ContentScale.FillBounds,
                    // Always on white, in both appearances: scanners expect dark
                    // modules on a light field.
                    modifier = Modifier
                        .size(QR_SIZE_DP.dp)
                        .background(Color.White)
                        // An expired code still renders; dimming it says so
                        // without yanking the card away mid-scan.
                        .alpha(if (expired) 0.25f else 1f),
                    filterQuality = FilterQuality.None,
                )
                if (expired) {
                    Text(
                        text = stringResource(R.string.expired),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (message != null) {
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }

        message != null -> Column(
            modifier = Modifier.height(QR_SIZE_DP.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(40.dp),
            )
            Spacer(Modifier.size(10.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(onClick = { scope.launch { codes.refresh(auth) } }) {
                Text(stringResource(R.string.retry))
            }
        }

        else -> Box(
            modifier = Modifier.height(QR_SIZE_DP.dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
    }
}

@Composable
private fun CardField(label: String, value: String) {
    Column {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.5.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.size(3.dp))
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
        )
    }
}

@Composable
private fun codeFreshness(expiresAt: Instant?, now: Instant): String {
    if (expiresAt == null) return "—"
    val seconds = max(0, expiresAt.epochSecond - now.epochSecond)
    if (seconds <= 0L) return stringResource(R.string.expired)
    return "%d:%02d".format(seconds / 60, seconds % 60)
}
