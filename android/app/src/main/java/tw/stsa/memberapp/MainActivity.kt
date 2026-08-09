package tw.stsa.memberapp

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.launch
import tw.stsa.memberapp.app.AppContainer
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.app.RootScreen
import tw.stsa.memberapp.designsystem.MemberAppTheme

/**
 * A `FragmentActivity` rather than a plain `ComponentActivity`: `BiometricPrompt`
 * hosts itself in a fragment, and the member-card gate has nowhere to appear
 * without one.
 */
class MainActivity : FragmentActivity() {

    private val container: AppContainer
        get() = (application as MemberApplication).container

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            CompositionLocalProvider(LocalAppContainer provides container) {
                MemberAppTheme(container.settings.appearance) {
                    RootScreen()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        // Coming back from the background is where the token has usually lapsed;
        // renewing here keeps the first tap instant. onStart rather than a timer,
        // for the reason spelled out on AuthManager.refreshIfNeeded.
        container.scope.launch { container.auth.refreshIfNeeded() }
    }
}
