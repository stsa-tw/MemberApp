package tw.stsa.memberapp.app

import android.content.Context
import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import tw.stsa.memberapp.auth.AuthManager
import tw.stsa.memberapp.feature.card.MembershipCodeStore
import tw.stsa.memberapp.feature.events.EventsStore

/**
 * The single instance of every piece of shared state, created once in
 * [tw.stsa.memberapp.MemberApplication] and reached through
 * [LocalAppContainer] — the same shape as iOS creating them in `MemberAppApp`
 * and injecting with `.environment(…)`.
 *
 * Hand-rolled rather than Hilt. Five objects with no graph between them do not
 * need a dependency-injection framework, and the rule that matters here is not
 * "how are these constructed" but "there is exactly one of each": nothing may
 * own a second copy of identity. `AuthManager.isLoggedIn` is the single gate.
 */
class AppContainer(context: Context) {

    private val appContext = context.applicationContext

    /**
     * Outlives any one screen, which is the point: the member card's refresh
     * loop belongs to the store, not to the composition that started it.
     */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val settings = AppSettings(
        appContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
    )
    val auth = AuthManager(appContext)
    val codes = MembershipCodeStore(appContext, scope)
    val events = EventsStore(appContext)
}

val LocalAppContainer = staticCompositionLocalOf<AppContainer> {
    error("No AppContainer in scope. MainActivity provides it around the whole app.")
}
