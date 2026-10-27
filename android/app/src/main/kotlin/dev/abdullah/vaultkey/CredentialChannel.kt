package dev.abdullah.vaultkey

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `vaultly/credentials`: whether Vaultly is the device's passkey provider,
 * the system screen to turn it on, and — inside [CredentialProviderActivity]
 * — the request being answered ([session]).
 */
class CredentialChannel(
    private val activity: Activity,
    private val session: CredentialRequestSession? = null,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "vaultly/credentials"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "isEnabled" -> result.success(isEnabled())
            "openSettings" -> result.success(openSettings())
            "getPendingRequest" -> if (session == null) result.success(null) else session.handle(call, result)
            else -> if (session == null) result.notImplemented() else session.handle(call, result)
        }
    }

    /** Credential Manager providers exist from Android 14. */
    private fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    private fun isEnabled(): Boolean {
        if (!isSupported()) return false
        val manager = activity.getSystemService(android.credentials.CredentialManager::class.java)
            ?: return false
        return manager.isEnabledCredentialProviderService(
            ComponentName(activity, VaultlyCredentialProviderService::class.java),
        )
    }

    private fun openSettings(): Boolean {
        if (!isSupported()) return false
        return try {
            activity.startActivity(
                Intent(Settings.ACTION_CREDENTIAL_PROVIDER).apply {
                    data = Uri.parse("package:${activity.packageName}")
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }
}
