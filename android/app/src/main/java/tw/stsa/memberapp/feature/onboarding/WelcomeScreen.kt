package tw.stsa.memberapp.feature.onboarding

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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.BrandButton
import tw.stsa.memberapp.designsystem.BrandTextButton

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
    val startSignIn = rememberSignIn()

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
            onClick = startSignIn,
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

        // Events, deals and announcements are all public, so nobody has to hold
        // an account to read them — App Review asks as much of the iOS app
        // (5.1.1(v)), and the two offer the same thing. What does need an
        // account says so where it is met.
        BrandTextButton(
            text = stringResource(R.string.browse_as_visitor),
            onClick = { container.settings.skipsWelcome = true },
            enabled = !auth.isBusy && !indico.isBusy,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
