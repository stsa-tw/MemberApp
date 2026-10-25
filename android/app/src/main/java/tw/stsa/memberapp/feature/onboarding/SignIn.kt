package tw.stsa.memberapp.feature.onboarding

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.auth.AuthManager

/**
 * The sign-in flow, for anywhere that offers it: Welcome, and every place a
 * visitor runs into something that needs an account — the member card, a
 * ticket, the 我的 tab.
 *
 * Returns the action that starts it. Failures are shown from here, so a caller
 * only has to put the returned lambda on a button.
 *
 * The Indico link is chained on in RootScreen, not here: a sign-in from Welcome
 * swaps that screen away the moment it succeeds, taking this launcher with it.
 */
@Composable
fun rememberSignIn(): () -> Unit {
    val auth = LocalAppContainer.current.auth
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
        }
    }

    // The logout page has nothing to call back with, so whatever the member did
    // on it — closed it, pressed back — the next step is the sign-in itself.
    val browserSignOut = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { _ ->
        scope.launch {
            try {
                launcher.launch(auth.authorizationIntent())
            } catch (error: Throwable) {
                auth.abandonAuthorization()
                if (!AuthManager.isUserCancellation(error)) errorMessage = error.message
            }
        }
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

    // When the member signed out last time, the step before signing in is to end
    // the browser's session so authentik has to ask who is signing in.
    return {
        scope.launch {
            try {
                val signOut = if (auth.shouldChooseAccount) {
                    auth.browserSignOutIntent()
                } else {
                    null
                }
                if (signOut != null) {
                    browserSignOut.launch(signOut)
                } else {
                    launcher.launch(auth.authorizationIntent())
                }
            } catch (error: Throwable) {
                auth.abandonAuthorization()
                if (!AuthManager.isUserCancellation(error)) errorMessage = error.message
            }
        }
    }
}
