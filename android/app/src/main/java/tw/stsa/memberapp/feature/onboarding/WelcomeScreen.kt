package tw.stsa.memberapp.feature.onboarding

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.AuthManager
import tw.stsa.memberapp.designsystem.BrandButton

private class Highlight(
    val icon: ImageVector,
    @param:StringRes val titleRes: Int,
    @param:StringRes val detailRes: Int,
)

private val highlights = listOf(
    Highlight(
        Icons.Filled.CreditCard,
        R.string.welcome_highlight_card_title,
        // Not "works offline": the QR carries a code that dies after 300s and
        // needs the network to renew, so the card cannot work offline.
        R.string.welcome_highlight_card_detail,
    ),
    Highlight(
        Icons.AutoMirrored.Filled.Chat,
        R.string.welcome_highlight_channels_title,
        R.string.welcome_highlight_channels_detail,
    ),
    Highlight(
        Icons.Filled.LocalOffer,
        R.string.welcome_highlight_deals_title,
        R.string.welcome_highlight_deals_detail,
    ),
)

@Composable
fun WelcomeScreen() {
    val container = LocalAppContainer.current
    val auth = container.auth
    val indico = container.indico
    val scope = rememberCoroutineScope()
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        scope.launch {
            try {
                auth.completeAuthorization(result.data)
            } catch (error: Throwable) {
                // Dismissing the sign-in tab is a choice, not a failure.
                if (!AuthManager.isUserCancellation(error)) errorMessage = error.message
            }
            // The Indico link is chained on in RootScreen, not here: a successful
            // sign-in swaps this screen away immediately.
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
            .padding(horizontal = 28.dp)
            .padding(top = 72.dp, bottom = 34.dp),
    ) {
        Image(
            painter = painterResource(R.drawable.stsa_logo),
            contentDescription = null,
            modifier = Modifier.size(76.dp),
        )
        Spacer(Modifier.size(22.dp))

        Text(
            text = stringResource(R.string.welcome_title),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.size(8.dp))
        Text(
            text = stringResource(R.string.welcome_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.size(34.dp))

        Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
            highlights.forEach { highlight ->
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Icon(
                        imageVector = highlight.icon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(28.dp),
                    )
                    Column {
                        Text(
                            text = stringResource(highlight.titleRes),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            text = stringResource(highlight.detailRes),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        Spacer(Modifier.weight(1f))

        // Straight into the browser flow — no intermediate screen. There is no
        // sign-up either: accounts are created in authentik, so the app only
        // ever authenticates an existing one.
        BrandButton(
            enabled = !auth.isBusy && !indico.isBusy,
            onClick = {
                scope.launch {
                    try {
                        launcher.launch(auth.authorizationIntent())
                    } catch (error: Throwable) {
                        auth.abandonAuthorization()
                        if (!AuthManager.isUserCancellation(error)) errorMessage = error.message
                    }
                }
            },
        ) {
            if (auth.isBusy || indico.isBusy) {
                Box(contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                }
            } else {
                Text(stringResource(R.string.sign_in))
            }
        }

        Spacer(Modifier.size(8.dp))

        // Indico's application is registered as trusted, so it shows no consent
        // screen of its own. Nothing else in the flow will tell the member their
        // Indico account is being connected, so this line has to — before it
        // happens, not after.
        Text(
            text = stringResource(R.string.sign_in_links_indico),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }

    errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(stringResource(R.string.sign_in_failed)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
    }
}
