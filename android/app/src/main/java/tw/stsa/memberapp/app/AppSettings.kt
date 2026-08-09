package tw.stsa.memberapp.app

import android.content.SharedPreferences
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import tw.stsa.memberapp.R
import tw.stsa.memberapp.model.Channel

/**
 * User preferences, persisted in SharedPreferences.
 *
 * None of this is sensitive — it is display preference, not credentials — so
 * plain preferences are the right home. Anything token-shaped belongs in
 * [tw.stsa.memberapp.auth.TokenStore].
 */
class AppSettings(private val prefs: SharedPreferences) {

    enum class Appearance(val stored: String, @param:StringRes val labelRes: Int) {
        SYSTEM("system", R.string.theme_system),
        LIGHT("light", R.string.theme_light),
        DARK("dark", R.string.theme_dark);

        companion object {
            fun from(stored: String?): Appearance =
                entries.firstOrNull { it.stored == stored } ?: SYSTEM
        }
    }

    // Backing state plus an explicit setter, which is how you get iOS's `didSet`
    // in Kotlin: a delegated property cannot carry a side effect, and a `var`
    // with `private set` beside a `setAppearance` function is the same JVM
    // signature twice.
    private var appearanceState by mutableStateOf(Appearance.from(prefs.getString(KEY_APPEARANCE, null)))

    var appearance: Appearance
        get() = appearanceState
        set(value) {
            appearanceState = value
            prefs.edit { putString(KEY_APPEARANCE, value.stored) }
        }

    /**
     * Requires device authentication before the member card is shown.
     *
     * On by default: the card is the member's identity credential, and a phone
     * handed to someone while unlocked is exactly the case the lock screen does
     * not cover. Devices with no screen lock fall through in `BiometricGate`
     * rather than being locked out.
     *
     * Unlike iOS, "never set" needs no special handling here — `getBoolean`
     * takes the default inline, so the `true` below *is* the default. The iOS
     * version has to check for the key first because `bool(forKey:)` cannot tell
     * "never set" from "explicitly off".
     */
    private var requireBiometricsState by mutableStateOf(prefs.getBoolean(KEY_BIOMETRICS, true))

    var requireBiometricsForCard: Boolean
        get() = requireBiometricsState
        set(value) {
            requireBiometricsState = value
            prefs.edit { putBoolean(KEY_BIOMETRICS, value) }
        }

    /**
     * Channels the member follows, by `Channel.id`. Null means never chosen,
     * which lets the first read seed from their school rather than assuming
     * they deliberately unfollowed everything.
     */
    var subscribedChannels: Set<String>? by mutableStateOf(prefs.getStringSet(KEY_CHANNELS, null))
        private set

    fun setSubscribed(subscribed: Boolean, channel: Channel, defaultingTo: Set<String>) {
        val ids = (subscribedChannels ?: defaultingTo).toMutableSet()
        if (subscribed) ids.add(channel.id) else ids.remove(channel.id)
        subscribedChannels = ids
        // getStringSet hands back a set the caller must not mutate and must not
        // hold, so this stores a copy.
        prefs.edit { putStringSet(KEY_CHANNELS, ids.toSet()) }
    }

    private companion object {
        const val KEY_APPEARANCE = "settings.appearance"
        const val KEY_BIOMETRICS = "settings.requireBiometricsForCard"
        const val KEY_CHANNELS = "settings.subscribedChannels"
    }
}
