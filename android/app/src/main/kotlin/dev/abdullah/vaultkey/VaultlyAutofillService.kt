package dev.abdullah.vaultkey

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
import androidx.annotation.RequiresApi
import dev.abdullah.vaultkey.fill.AppSigners
import dev.abdullah.vaultkey.fill.BrowserAllowlist
import dev.abdullah.vaultkey.fill.DatasetFactory
import dev.abdullah.vaultkey.fill.FillRequestIntents
import dev.abdullah.vaultkey.fill.FillSession
import dev.abdullah.vaultkey.fill.InlineChips
import dev.abdullah.vaultkey.fill.FillSessionActivity
import dev.abdullah.vaultkey.fill.FillUnlockActivity
import dev.abdullah.vaultkey.fill.FormDump
import dev.abdullah.vaultkey.fill.FormParser
import dev.abdullah.vaultkey.fill.RequestTarget
import dev.abdullah.vaultkey.fill.ViewFieldNode
import dev.abdullah.vaultkey.vault.VaultKeyWrap
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
        val codeIds = ArrayList(parsed.codes.map { it.autofillId!! })
        val codeOnly = usernameIds.isEmpty() && passwordIds.isEmpty()

        // Fingerprint users get the sheet that fills without starting Flutter;
        // everyone else continues in the full app, which can derive the key
        // from the master password.
        val biometric = VaultKeyWrap(this).hasWrappedKey()
        val session = FillSession.current(target)?.takeIf { codeIds.isEmpty() || it.totp != null }
        // The full-app flow cannot answer a code page, so without a
        // fingerprint key or a live session there is nothing to offer.
        if (codeOnly && !biometric && session == null) return null
        val unlockIntent = if (biometric) {
            FillRequestIntents.put(Intent(this, FillUnlockActivity::class.java), target, usernameIds, passwordIds, codeIds)
        } else {
            FillRequestIntents.mainActivity(this, target, usernameIds, passwordIds)
        }
        val ids = usernameIds + passwordIds + codeIds
        val response = FillResponse.Builder()
        val chips = InlineChips.of(this, request)
        var datasets = 0
        // With the chosen account armed for this page, "Continue as" comes first.
        session?.let {
            val continueIntent = FillRequestIntents.put(
                Intent(this, FillSessionActivity::class.java), target, usernameIds, passwordIds, codeIds,
            )
            response.addDataset(
                DatasetFactory.locked(
                    this, "Continue as ${it.label}${if (codeOnly) " · code" else ""}", ids,
                    DatasetFactory.authIntent(this, SESSION_REQUEST_CODE, continueIntent),
                    chips?.takeIf { c -> c.hasRoom(datasets) }?.chip(datasets, "Continue as ${it.label}"),
                ),
            )
            datasets++
        }
        // Locked chips never name an account.
        response.addDataset(
            DatasetFactory.locked(
                this, "Vaultly", ids, DatasetFactory.authIntent(this, AUTH_REQUEST_CODE, unlockIntent),
                chips?.takeIf { c -> c.hasRoom(datasets) }?.chip(datasets, "Vaultly"),
            ),
        )
        return response.build()
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // No SaveInfo is declared, so nothing to save. Kept as a no-op.
        callback.onSuccess()
    }

    private companion object {
        const val AUTH_REQUEST_CODE = 4201
        const val SESSION_REQUEST_CODE = 4202
        const val TIMING_TAG = "vaultly.fill"
    }
}
