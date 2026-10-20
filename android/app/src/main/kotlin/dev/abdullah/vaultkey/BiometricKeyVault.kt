package dev.abdullah.vaultkey

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
 */
class BiometricKeyVault(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "vaultly/biometric_key"
        private const val ALIAS = "vaultly_biometric_wrap"
        private const val PREFS = "vaultly_biometric_key"
        private const val BLOB = "wrapped_key"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
        private const val TAG_BITS = 128
    }

    private val prefs by lazy {
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "store" -> store(
                call.argument<ByteArray>("key")!!,
                call.argument<String>("reason")!!,
                result,
            )
            "release" -> release(call.argument<String>("reason")!!, result)
            "delete" -> {
                delete()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Prompts, then persists [key] wrapped by a fresh hardware-bound key. */
    private fun store(key: ByteArray, reason: String, result: MethodChannel.Result) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, createKey())
        prompt(reason, cipher, onCancel = { result.success(false) }) { authorized ->
            val sealed = authorized.doFinal(key)
            val blob = authorized.iv + sealed
            prefs.edit().putString(BLOB, Base64.encodeToString(blob, Base64.NO_WRAP))
                .apply()
            result.success(true)
        }
    }

    /** Prompts, then returns the unwrapped key (status + key map for Dart). */
    private fun release(reason: String, result: MethodChannel.Result) {
        val encoded = prefs.getString(BLOB, null)
        val secret = keyStore().getKey(ALIAS, null) as SecretKey?
        if (encoded == null || secret == null) {
            result.success(mapOf("status" to "missing"))
            return
        }
        val blob = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        try {
            cipher.init(
                Cipher.DECRYPT_MODE,
                secret,
                GCMParameterSpec(TAG_BITS, blob, 0, IV_LENGTH),
            )
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometric enrollment changed: the wrapped key is unrecoverable.
            delete()
            result.success(mapOf("status" to "invalidated"))
            return
        }
        prompt(reason, cipher, onCancel = {
            result.success(mapOf("status" to "cancelled"))
        }) { authorized ->
            val key = authorized.doFinal(blob, IV_LENGTH, blob.size - IV_LENGTH)
            result.success(mapOf("status" to "released", "key" to key))
        }
    }

    private fun delete() {
        prefs.edit().remove(BLOB).apply()
        keyStore().deleteEntry(ALIAS)
    }

    private fun keyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

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

    /**
     * Shows the system prompt bound to [cipher]. Exactly one of [onCancel] or
     * [onAuthorized] runs; a non-matching finger only lets the user retry.
     */
    private fun prompt(
        reason: String,
        cipher: Cipher,
        onCancel: () -> Unit,
        onAuthorized: (Cipher) -> Unit,
    ) {
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(
                result: BiometricPrompt.AuthenticationResult,
            ) {
                onAuthorized(result.cryptoObject!!.cipher!!)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                onCancel()
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(reason)
            .setNegativeButtonText("Use master password")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }
}
