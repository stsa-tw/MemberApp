package tw.stsa.memberapp.auth

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.core.content.edit
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The Android half of `ios/MemberApp/Auth/Keychain.swift`: somewhere to put the
 * one thing that must not touch disk in the clear — the serialised AppAuth
 * `AuthState`, which carries a 30-day refresh token.
 *
 * The payload is sealed with an AES-256-GCM key generated inside the Android
 * Keystore. That key is not extractable, so the ciphertext is meaningless off
 * this device — which is the property `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
 * buys on iOS. Excluding it from backup and device transfer is the other half,
 * and that lives in `res/xml/data_extraction_rules.xml`.
 *
 * Deliberately hand-rolled rather than pulling in `androidx.security-crypto`:
 * this is the platform's own `Cipher`/`KeyStore` API with no invented crypto,
 * it is shorter than the dependency's transitive Tink graph, and the newest
 * release of that library is still alpha.
 *
 * No `setUserAuthenticationRequired` — matching iOS's choice of AfterFirstUnlock
 * over WhenUnlocked. A silent token refresh must be able to run without putting
 * a lock screen in front of the member. Authentication guards the *card*, in
 * [BiometricGate], not the credential store.
 */
class TokenStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(): String? {
        val stored = prefs.getString(KEY_PAYLOAD, null) ?: return null
        return try {
            val blob = Base64.decode(stored, Base64.NO_WRAP)
            val iv = blob.copyOfRange(0, IV_LENGTH)
            val ciphertext = blob.copyOfRange(IV_LENGTH, blob.size)

            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (error: Exception) {
            // An unreadable blob is a blob we will never read: the key is gone,
            // or it was written by a build that used a different one. Drop it so
            // the next sign-in starts clean instead of failing here every launch.
            Log.w(TAG, "Discarding unreadable auth state", error)
            clear()
            null
        }
    }

    fun write(payload: String) {
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val ciphertext = cipher.doFinal(payload.toByteArray(Charsets.UTF_8))
            val blob = cipher.iv + ciphertext
            prefs.edit { putString(KEY_PAYLOAD, Base64.encodeToString(blob, Base64.NO_WRAP)) }
        } catch (error: Exception) {
            // Losing the write means the user re-authenticates next launch —
            // bad UX, not a correctness problem. Never fall back to plaintext.
            Log.e(TAG, "Could not persist auth state", error)
        }
    }

    fun clear() {
        prefs.edit { remove(KEY_PAYLOAD) }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "TokenStore"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        // Same identifier as the iOS keychain service, so the two are obviously
        // the same thing when you are looking at one and remembering the other.
        const val KEY_ALIAS = "tw.stsa.membership.oidc"
        const val PREFS_NAME = "auth"
        const val KEY_PAYLOAD = "authState"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        /** GCM in the Android Keystore always produces a 12-byte IV. */
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
    }
}
