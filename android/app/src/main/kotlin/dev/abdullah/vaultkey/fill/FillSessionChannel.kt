package dev.abdullah.vaultkey.fill

import android.content.Context
import dev.abdullah.vaultkey.vault.TotpParams
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Dart's handle on the fill session and its setting. */
class FillSessionChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "vaultly/fill_session"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "arm" -> {
                val url = call.argument<String>("url")!!
                val totp = call.argument<Map<String, Any>>("totp")?.let {
                    TotpParams(
                        secret = it["secret"] as String,
                        algorithm = it["algorithm"] as String,
                        digits = it["digits"] as Int,
                        period = it["period"] as Int,
                    )
                }
                val username = call.argument<String>("username")!!
                FillSession.arm(
                    context,
                    call.argument<String>("entryId")!!,
                    username.ifEmpty { call.argument<String>("title")!! },
                    username.toCharArray(),
                    call.argument<String>("password")!!.toCharArray(),
                    totp,
                    SessionScope.forSite(url, EquivalentDomains.get(context)),
                )
                result.success(null)
            }
            "clear" -> {
                FillSession.wipe()
                result.success(null)
            }
            "status" -> result.success(FillSession.liveEntryId())
            "isEnabled" -> result.success(FillSettings(context).sessionEnabled)
            "setEnabled" -> {
                val on = call.argument<Boolean>("enabled")!!
                FillSettings(context).sessionEnabled = on
                if (!on) FillSession.wipe()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
