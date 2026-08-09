package tw.stsa.memberapp

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import tw.stsa.memberapp.app.AppSettings
import tw.stsa.memberapp.model.Channel
import java.util.UUID

/**
 * Needs Robolectric only for a real `SharedPreferences`. Everything under test
 * is plain logic — the defaulting rules and the seeding rules — the same slice
 * the iOS suite covers with a throwaway `UserDefaults` suite.
 */
@RunWith(RobolectricTestRunner::class)
class AppSettingsTest {

    /** A fresh file per case, so nothing leaks between them. */
    private fun preferences(): SharedPreferences =
        RuntimeEnvironment.getApplication()
            .getSharedPreferences("AppSettingsTest.${UUID.randomUUID()}", Context.MODE_PRIVATE)

    private fun channel(id: String) = Channel.all.first { it.id == id }

    // MARK: - Biometrics

    /**
     * The card is the member's identity credential, so the gate is on until
     * someone turns it off.
     */
    @Test
    fun `biometrics defaults to on when never chosen`() {
        assertTrue(AppSettings(preferences()).requireBiometricsForCard)
    }

    /**
     * The case the iOS implementation comment is about: an explicit off must
     * survive a relaunch rather than being re-defaulted back to on.
     */
    @Test
    fun `an explicit off is not reset to the default`() {
        val prefs = preferences()
        prefs.edit { putBoolean("settings.requireBiometricsForCard", false) }

        assertFalse(AppSettings(prefs).requireBiometricsForCard)
    }

    @Test
    fun `biometrics changes are persisted`() {
        val prefs = preferences()
        AppSettings(prefs).requireBiometricsForCard = false

        assertFalse(AppSettings(prefs).requireBiometricsForCard)
    }

    // MARK: - Appearance

    @Test
    fun `appearance defaults to following the system`() {
        assertEquals(AppSettings.Appearance.SYSTEM, AppSettings(preferences()).appearance)
    }

    @Test
    fun `appearance changes are persisted`() {
        val prefs = preferences()
        AppSettings(prefs).appearance = AppSettings.Appearance.DARK

        assertEquals(AppSettings.Appearance.DARK, AppSettings(prefs).appearance)
    }

    /**
     * A value written by an older build, or by hand, must not leave the app with
     * no appearance at all.
     */
    @Test
    fun `an unrecognised stored value falls back to the system`() {
        val prefs = preferences()
        prefs.edit { putString("settings.appearance", "solarized") }

        assertEquals(AppSettings.Appearance.SYSTEM, AppSettings(prefs).appearance)
    }

    // MARK: - Channels

    /**
     * Null means "never chosen", which is what lets the first read seed from the
     * member's school. An empty set would mean "deliberately unfollowed
     * everything" — a different thing entirely.
     */
    @Test
    fun `channels start as null rather than empty`() {
        assertNull(AppSettings(preferences()).subscribedChannels)
    }

    /**
     * The first toggle applies to the seed, not to an empty set — otherwise
     * following one channel would silently unfollow the defaults.
     */
    @Test
    fun `the first change is applied on top of the seed`() {
        val settings = AppSettings(preferences())

        settings.setSubscribed(true, channel("nus"), setOf("all", "freshmen"))

        assertEquals(setOf("all", "freshmen", "nus"), settings.subscribedChannels)
    }

    @Test
    fun `unfollowing removes only that channel`() {
        val settings = AppSettings(preferences())

        settings.setSubscribed(false, channel("all"), setOf("all", "freshmen"))

        assertEquals(setOf("freshmen"), settings.subscribedChannels)
    }

    /** Once a choice exists it is no longer null, so later reads stop seeding. */
    @Test
    fun `choices are persisted and stop the seeding`() {
        val prefs = preferences()
        AppSettings(prefs).setSubscribed(true, channel("nus"), setOf("all"))

        assertEquals(setOf("all", "nus"), AppSettings(prefs).subscribedChannels)
    }

    /**
     * Unfollowing everything is a real state and must not read as "never chosen"
     * on the next launch.
     */
    @Test
    fun `unfollowing everything persists as an empty set not null`() {
        val prefs = preferences()
        AppSettings(prefs).setSubscribed(false, channel("all"), setOf("all"))

        assertEquals(emptySet<String>(), AppSettings(prefs).subscribedChannels)
    }
}
