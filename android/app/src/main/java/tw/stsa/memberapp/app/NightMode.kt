package tw.stsa.memberapp.app

import android.app.UiModeManager
import android.content.Context
import android.os.Build
import androidx.core.content.getSystemService

/**
 * Publishes the app's appearance setting to the platform.
 *
 * Without this the setting only reaches Compose, and the resource system keeps
 * resolving `values-night` from the *system's* night mode. The visible symptom
 * is a cold start on a light phone with the app set to dark: the window frame
 * that `Theme.MemberApp` paints before Compose's first draw comes back white,
 * flashes, and is then covered by a dark app.
 *
 * `setApplicationNightMode` is what fixes that rather than a second colour
 * resource, because the system stores it per package: the *next* launch already
 * has the right `uiMode` while the window is being created, which is earlier
 * than any code of ours can run.
 *
 * The activity declares `uiMode` in its `configChanges`, so applying a new value
 * recomposes instead of recreating.
 */
fun Context.applyAppearance(appearance: AppSettings.Appearance) {
    // API 31. The app supports 30, where there is no per-application night mode
    // and the Compose-side branch in MemberAppTheme is the whole story — the
    // launch frame can still flash there, and there is no API to prevent it.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return

    val manager = getSystemService<UiModeManager>() ?: return
    manager.setApplicationNightMode(
        when (appearance) {
            // MODE_NIGHT_AUTO is how an app hands the decision back to the
            // system, which is what "follow system" means here.
            AppSettings.Appearance.SYSTEM -> UiModeManager.MODE_NIGHT_AUTO
            AppSettings.Appearance.LIGHT -> UiModeManager.MODE_NIGHT_NO
            AppSettings.Appearance.DARK -> UiModeManager.MODE_NIGHT_YES
        }
    )
}
