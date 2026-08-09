package tw.stsa.memberapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.launch
import tw.stsa.memberapp.app.AppContainer
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.app.RootScreen
import tw.stsa.memberapp.app.applyAppearance
import tw.stsa.memberapp.designsystem.MemberAppTheme

/**
 * A `FragmentActivity` rather than a plain `ComponentActivity`: `BiometricPrompt`
 * hosts itself in a fragment, and the member-card gate has nowhere to appear
 * without one.
 */
class MainActivity : FragmentActivity() {

    private val container: AppContainer
        get() = (application as MemberApplication).container

    /**
     * Set when the launcher shortcut started us, and cleared once the shell has
     * navigated. Compose state rather than a field so a shortcut tapped while
     * the app is already up redraws instead of waiting for the next event.
     */
    private var showCardRequest by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Before setContent: this is the value the *next* cold start's window
        // frame is painted from. See applyAppearance.
        applyAppearance(container.settings.appearance)
        showCardRequest = intent.isShowCard()

        setContent {
            val appearance = container.settings.appearance
            LaunchedEffect(appearance) { applyAppearance(appearance) }

            CompositionLocalProvider(LocalAppContainer provides container) {
                MemberAppTheme(appearance) {
                    RootScreen(
                        showCardRequest = showCardRequest,
                        onCardRequestHandled = { showCardRequest = false },
                    )
                }
            }
        }
    }

    /** Reached when the shortcut is tapped while the app is already running. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.isShowCard()) showCardRequest = true
    }

    override fun onStart() {
        super.onStart()
        // Coming back from the background is where the token has usually lapsed;
        // renewing here keeps the first tap instant. onStart rather than a timer,
        // for the reason spelled out on AuthManager.refreshIfNeeded.
        container.scope.launch { container.auth.refreshIfNeeded() }
    }

    private fun Intent.isShowCard() = action == ACTION_SHOW_CARD

    companion object {
        /** Declared by the launcher shortcut in `res/xml/shortcuts.xml`. */
        const val ACTION_SHOW_CARD = "tw.stsa.memberapp.action.SHOW_CARD"
    }
}
