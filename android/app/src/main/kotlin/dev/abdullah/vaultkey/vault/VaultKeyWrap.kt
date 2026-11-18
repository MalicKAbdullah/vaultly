package dev.abdullah.vaultkey.vault

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the vault key encrypted under an Android Keystore key that can only
 * be used inside a successful Class 3 biometric prompt (BiometricPrompt with
 * a CryptoObject). The Keystore key never leaves secure hardware and is
 * invalidated when fingerprints are added or removed, so neither a copy of
 * the app's storage nor code running in the app without a fresh fingerprint
 * can recover the vault key.
 *
 * Only the ciphertext (IV + AES-GCM output) is persisted, in plain
 * SharedPreferences: it is useless without the hardware-bound key.
 *
 * This class prepares and finishes the ciphers; showing the prompt that
 * authorizes them is the caller's job ([BiometricGate]).
 */
class VaultKeyWrap(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** A wrapped key stored for unwrapping, or why there is none to unwrap. */
    sealed class Unwrap {
        /** [cipher] needs a biometric prompt before [VaultKeyWrap.unwrap] can use it. */
        class Ready(val cipher: Cipher, internal val blob: ByteArray) : Unwrap()
        object Missing : Unwrap()

        /**
         * Biometric enrollment changed, so the stored key can never be
         * unwrapped. It is left in place: Dart's `BiometricUnlockService.disable()`
         * is the one owner that deletes it and turns biometric unlock off.
         */
        object Invalidated : Unwrap()
    }

    /** Whether a wrapped key is stored. Reads SharedPreferences only. */
    fun hasWrappedKey(): Boolean = prefs.contains(BLOB)

    /** A cipher under a fresh hardware-bound key, to authorize and pass to [seal]. */
    fun sealCipher(): Cipher =
        Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, createKey()) }

    /** Stores [key] wrapped with [authorized] (from [sealCipher], after the prompt). */
    fun seal(authorized: Cipher, key: ByteArray) {
        val blob = authorized.iv + authorized.doFinal(key)
        prefs.edit().putString(BLOB, Base64.encodeToString(blob, Base64.NO_WRAP)).apply()
    }

    fun prepareUnwrap(): Unwrap {
        val encoded = prefs.getString(BLOB, null)
        val secret = keyStore().getKey(ALIAS, null) as SecretKey?
        if (encoded == null || secret == null) return Unwrap.Missing
        val blob = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        return try {
            cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(TAG_BITS, blob, 0, IV_LENGTH))
            Unwrap.Ready(cipher, blob)
        } catch (_: KeyPermanentlyInvalidatedException) {
            Unwrap.Invalidated
        }
    }

    /** The vault key, from [ready]'s cipher once a prompt authorized it. The caller zeroes it. */
    fun unwrap(ready: Unwrap.Ready, authorized: Cipher): ByteArray =
        authorized.doFinal(ready.blob, IV_LENGTH, ready.blob.size - IV_LENGTH)

    fun delete() {
        prefs.edit().remove(BLOB).apply()
        keyStore().deleteEntry(ALIAS)
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun createKey(): SecretKey {
        keyStore().deleteEntry(ALIAS)
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }
            .generateKey()
    }

    private companion object {
        const val ALIAS = "vaultly_biometric_wrap"
        const val PREFS = "vaultly_biometric_key"
        const val BLOB = "wrapped_key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
    }
}
