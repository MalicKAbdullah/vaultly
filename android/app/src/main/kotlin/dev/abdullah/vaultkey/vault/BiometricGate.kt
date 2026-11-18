package dev.abdullah.vaultkey.vault

import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import javax.crypto.Cipher

/** The Class 3 biometric prompt that authorizes a [VaultKeyWrap] cipher. */
object BiometricGate {

    /**
     * Shows the system prompt bound to [cipher]. Exactly one of [onCancel] or
     * [onAuthorized] runs; a non-matching finger only lets the user retry.
     * [onCancel] gets the [BiometricPrompt] error code (the negative button
     * is [BiometricPrompt.ERROR_NEGATIVE_BUTTON]).
     */
    fun prompt(
        activity: FragmentActivity,
        title: String,
        subtitle: String?,
        cipher: Cipher,
        onCancel: (errorCode: Int) -> Unit,
        onAuthorized: (Cipher) -> Unit,
    ) {
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onAuthorized(result.cryptoObject!!.cipher!!)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                onCancel(errorCode)
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply { if (subtitle != null) setSubtitle(subtitle) }
            .setNegativeButtonText("Use master password")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }
}
