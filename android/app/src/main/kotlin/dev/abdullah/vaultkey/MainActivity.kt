package dev.abdullah.vaultkey

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (biometric prompt).
class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val EXTRA_AUTOFILL = "vaultly_autofill"
        const val EXTRA_AUTOFILL_PACKAGE = "vaultly_autofill_package"
        const val EXTRA_AUTOFILL_DOMAIN = "vaultly_autofill_domain"
        const val EXTRA_AUTOFILL_USERNAME_IDS = "vaultly_autofill_username_ids"
        const val EXTRA_AUTOFILL_PASSWORD_IDS = "vaultly_autofill_password_ids"

        private const val CHANNEL = "vaultly/autofill"
    }

    /** Fill request this activity was launched to answer, when any. */
    private var autofillPackage: String? = null
    private var autofillDomain: String? = null
    private var usernameIds: ArrayList<AutofillId> = arrayListOf()
    private var passwordIds: ArrayList<AutofillId> = arrayListOf()
    private var isAutofillFlow = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and hide vault contents in the recents preview.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        readAutofillIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readAutofillIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun readAutofillIntent(intent: Intent?) {
        if (intent == null || !intent.getBooleanExtra(EXTRA_AUTOFILL, false)) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        isAutofillFlow = true
        autofillPackage = intent.getStringExtra(EXTRA_AUTOFILL_PACKAGE)
        autofillDomain = intent.getStringExtra(EXTRA_AUTOFILL_DOMAIN)
        usernameIds =
            intent.getParcelableArrayListExtra(EXTRA_AUTOFILL_USERNAME_IDS) ?: arrayListOf()
        passwordIds =
            intent.getParcelableArrayListExtra(EXTRA_AUTOFILL_PASSWORD_IDS) ?: arrayListOf()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingRequest" -> result.success(pendingRequest())
                    "complete" -> {
                        val username = call.argument<String>("username").orEmpty()
                        val password = call.argument<String>("password").orEmpty()
                        val label = call.argument<String>("label").orEmpty()
                        result.success(completeAutofill(username, password, label))
                    }
                    "cancel" -> {
                        cancelAutofill()
                        result.success(null)
                    }
                    "isSupported" -> result.success(isAutofillSupported())
                    "isEnabled" -> result.success(isVaultlyAutofillEnabled())
                    "openSettings" -> result.success(openAutofillSettings())
                    else -> result.notImplemented()
                }
            }
    }

    private fun pendingRequest(): Map<String, Any?>? {
        if (!isAutofillFlow) return null
        return mapOf(
            "package" to autofillPackage,
            "domain" to autofillDomain,
        )
    }

    /**
     * Builds the result dataset from the picked entry and hands it back to
     * the requesting app via EXTRA_AUTHENTICATION_RESULT, which fills the
     * form. Returns false when there is nothing to answer.
     */
    private fun completeAutofill(username: String, password: String, label: String): Boolean {
        if (!isAutofillFlow || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (usernameIds.isEmpty() && passwordIds.isEmpty()) return false

        val presentation = RemoteViews(packageName, R.layout.vaultly_autofill_item).apply {
            setTextViewText(
                R.id.vaultly_autofill_text,
                label.ifBlank { "Vaultly" },
            )
        }
        val dataset = android.service.autofill.Dataset.Builder(presentation).apply {
            usernameIds.forEach { setValue(it, AutofillValue.forText(username), presentation) }
            passwordIds.forEach { setValue(it, AutofillValue.forText(password), presentation) }
        }.build()

        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset),
        )
        isAutofillFlow = false
        finish()
        return true
    }

    private fun cancelAutofill() {
        if (!isAutofillFlow) return
        isAutofillFlow = false
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    private fun isAutofillSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return getSystemService(AutofillManager::class.java)?.isAutofillSupported ?: false
    }

    private fun isVaultlyAutofillEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return getSystemService(AutofillManager::class.java)
            ?.hasEnabledAutofillServices() ?: false
    }

    private fun openAutofillSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                    data = Uri.parse("package:$packageName")
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }
}
