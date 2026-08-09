package tw.stsa.memberapp.auth

import android.content.Context
import android.content.pm.PackageManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.suspendCancellableCoroutine
import tw.stsa.memberapp.R
import kotlin.coroutines.resume

/**
 * Device-owner authentication in front of the member card.
 *
 * This is not a second login — it cannot obtain a token, and the session is
 * already established. It guards against the one case the lock screen does not
 * cover: someone holding the phone while it is already unlocked.
 */
object BiometricGate {

    /**
     * Biometrics *or* the screen lock, the same pairing iOS gets from
     * `.deviceOwnerAuthentication`: a failed scan — a mask, sunglasses, wet
     * hands — falls back to the PIN instead of locking someone out of their own
     * card. This combination is only accepted from API 30, which is what sets
     * the app's minSdk.
     */
    private const val AUTHENTICATORS = BIOMETRIC_STRONG or DEVICE_CREDENTIAL

    /** True when the device can authenticate at all — biometrics or screen lock. */
    fun isAvailable(context: Context): Boolean =
        BiometricManager.from(context).canAuthenticate(AUTHENTICATORS) ==
            BiometricManager.BIOMETRIC_SUCCESS

    /**
     * What the device will actually ask for, so the toggle and the unlock button
     * can say it honestly.
     *
     * Fingerprint is checked before face because face unlock is Class 2 on most
     * Android hardware, and Class 2 does not satisfy BIOMETRIC_STRONG — naming
     * it would promise a prompt the member will never see.
     */
    fun biometryName(context: Context): String {
        val enrolled = BiometricManager.from(context).canAuthenticate(BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS
        if (!enrolled) return context.getString(R.string.biometry_device_credential)

        val packages = context.packageManager
        return when {
            packages.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT) ->
                context.getString(R.string.biometry_fingerprint)

            packages.hasSystemFeature(PackageManager.FEATURE_FACE) ->
                context.getString(R.string.biometry_face)

            else -> context.getString(R.string.biometry_device_credential)
        }
    }

    /** Returns true when the person authenticated. */
    suspend fun authenticate(activity: FragmentActivity, title: String): Boolean =
        suspendCancellableCoroutine { continuation ->
            if (!isAvailable(activity)) {
                // No screen lock set at all: refuse to gate rather than make the
                // card unreachable.
                continuation.resume(true)
                return@suspendCancellableCoroutine
            }

            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (continuation.isActive) continuation.resume(true)
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    if (continuation.isActive) continuation.resume(false)
                }
                // onAuthenticationFailed is one bad read, not a decision — the
                // prompt stays up and the member tries again.
            }

            val prompt = BiometricPrompt(
                activity,
                ContextCompat.getMainExecutor(activity),
                callback,
            )

            // No negative button: setNegativeButtonText and DEVICE_CREDENTIAL
            // are mutually exclusive, and the system supplies its own cancel.
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(title)
                    .setAllowedAuthenticators(AUTHENTICATORS)
                    .build()
            )
        }
}
