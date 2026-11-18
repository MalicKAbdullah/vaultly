package dev.abdullah.vaultkey

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.os.SystemClock
import android.os.Trace
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.util.Log
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import dev.abdullah.vaultkey.fill.AppSigners
import dev.abdullah.vaultkey.fill.BrowserAllowlist
import dev.abdullah.vaultkey.fill.FormDump
import dev.abdullah.vaultkey.fill.FormParser
import dev.abdullah.vaultkey.fill.RequestTarget
import dev.abdullah.vaultkey.fill.ViewFieldNode
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Vaultly as an Android autofill provider.
 *
 * On a fill request we parse the form, and when it looks like a login we
 * answer with a single dataset locked behind authentication: tapping
 * "Unlock Vaultly to fill" launches [MainActivity], which walks the user
 * through unlock + entry selection and returns the filled dataset as the
 * authentication result.
 *
 * Requests are answered on one background thread, so parsing a large page
 * never holds up the service's main thread.
 *
 * Save requests (capturing new logins) are out of scope: no SaveInfo is
 * ever attached, so [onSaveRequest] never fires in practice.
 */
@RequiresApi(Build.VERSION_CODES.O)
class VaultlyAutofillService : AutofillService() {

    private lateinit var worker: ExecutorService

    override fun onCreate() {
        super.onCreate()
        worker = Executors.newSingleThreadExecutor()
    }

    override fun onConnected() {
        // Parse the browser allowlist before the first request needs it.
        worker.execute { BrowserAllowlist.get(this) }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        worker.execute {
            if (cancellationSignal.isCanceled) return@execute
            val started = SystemClock.elapsedRealtimeNanos()
            Trace.beginSection("vaultly.fill.request")
            val response = try {
                respond(request)
            } finally {
                Trace.endSection()
            }
            if (cancellationSignal.isCanceled) return@execute
            callback.onSuccess(response)
            if (Log.isLoggable(TIMING_TAG, Log.DEBUG)) {
                val micros = (SystemClock.elapsedRealtimeNanos() - started) / 1_000
                Log.d(TIMING_TAG, "onFillRequest answered in $micros µs")
            }
        }
    }

    private fun respond(request: FillRequest): FillResponse? {
        val context = request.fillContexts.lastOrNull() ?: return null
        val structure = context.structure
        val clientPackage = structure.activityComponent.packageName
        // Never offer to fill our own screens.
        if (clientPackage == packageName) return null

        val roots = ViewFieldNode.roots(structure)
        FormDump.log(this, roots)
        val parsed = FormParser.parse(roots)
        if (!parsed.isFillable) return null

        val target = RequestTarget.resolve(
            packageName = clientPackage,
            signers = AppSigners.of(this, clientPackage),
            webDomain = parsed.webDomain,
            allowlist = BrowserAllowlist.get(this),
        )
        if (Log.isLoggable(TIMING_TAG, Log.DEBUG)) {
            Log.d(TIMING_TAG, "target is ${target::class.simpleName}")
        }
        // The parser only returns text fields, which all have an autofill id.
        val usernameIds = ArrayList(parsed.usernames.map { it.autofillId!! })
        val passwordIds = ArrayList(parsed.passwords.map { it.autofillId!! })

        val presentation = RemoteViews(packageName, R.layout.vaultly_autofill_item)
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_AUTOFILL, true)
            when (target) {
                is RequestTarget.Web -> putExtra(MainActivity.EXTRA_AUTOFILL_DOMAIN, target.host)
                is RequestTarget.App -> putExtra(MainActivity.EXTRA_AUTOFILL_PACKAGE, target.packageName)
            }
            putParcelableArrayListExtra(MainActivity.EXTRA_AUTOFILL_USERNAME_IDS, usernameIds)
            putParcelableArrayListExtra(MainActivity.EXTRA_AUTOFILL_PASSWORD_IDS, passwordIds)
        }
        var pendingFlags = PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            pendingFlags = pendingFlags or PendingIntent.FLAG_MUTABLE
        }
        val pendingIntent = PendingIntent.getActivity(this, AUTH_REQUEST_CODE, intent, pendingFlags)

        val dataset = Dataset.Builder(presentation).apply {
            // Auth-gated datasets still need every fillable id registered;
            // the real values arrive in the authentication result.
            (usernameIds + passwordIds).forEach { setValue(it, null, presentation) }
            setAuthentication(pendingIntent.intentSender)
        }.build()
        return FillResponse.Builder().addDataset(dataset).build()
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // No SaveInfo is declared, so nothing to save. Kept as a no-op.
        callback.onSuccess()
    }

    private companion object {
        const val AUTH_REQUEST_CODE = 4201
        const val TIMING_TAG = "vaultly.fill"
    }
}
