package dev.abdullah.vaultkey

import androidx.fragment.app.FragmentActivity
import dev.abdullah.vaultkey.vault.BiometricGate
import dev.abdullah.vaultkey.vault.VaultKeyWrap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart's handle on the biometric-wrapped vault key (see [VaultKeyWrap]):
 * store it behind a fingerprint, release it after one, or delete it.
 */
class BiometricKeyVault(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "vaultly/biometric_key"
    }

    private val wrap by lazy { VaultKeyWrap(activity) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "store" -> store(
                call.argument<ByteArray>("key")!!,
                call.argument<String>("reason")!!,
                result,
            )
            "release" -> release(call.argument<String>("reason")!!, result)
            "delete" -> {
                wrap.delete()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Prompts, then persists [key] wrapped by a fresh hardware-bound key. */
    private fun store(key: ByteArray, reason: String, result: MethodChannel.Result) {
        BiometricGate.prompt(
            activity, reason, null, wrap.sealCipher(),
            onCancel = { result.success(false) },
        ) { authorized ->
            wrap.seal(authorized, key)
            result.success(true)
        }
    }

    /** Prompts, then returns the unwrapped key (status + key map for Dart). */
    private fun release(reason: String, result: MethodChannel.Result) {
        when (val unwrap = wrap.prepareUnwrap()) {
            VaultKeyWrap.Unwrap.Missing -> result.success(mapOf("status" to "missing"))
            VaultKeyWrap.Unwrap.Invalidated -> result.success(mapOf("status" to "invalidated"))
            is VaultKeyWrap.Unwrap.Ready -> BiometricGate.prompt(
                activity, reason, null, unwrap.cipher,
                onCancel = { result.success(mapOf("status" to "cancelled")) },
            ) { authorized ->
                result.success(mapOf("status" to "released", "key" to wrap.unwrap(unwrap, authorized)))
            }
        }
    }
}
