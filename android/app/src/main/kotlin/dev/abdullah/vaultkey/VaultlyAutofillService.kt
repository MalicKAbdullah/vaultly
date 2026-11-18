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
import android.view.autofill.AutofillId
import android.service.autofill.SaveInfo
import android.app.PendingIntent
import android.service.autofill.SaveRequest
import android.util.Log
import androidx.annotation.RequiresApi
import dev.abdullah.vaultkey.fill.AppSigners
import dev.abdullah.vaultkey.fill.BrowserAllowlist
import dev.abdullah.vaultkey.fill.DatasetFactory
import dev.abdullah.vaultkey.fill.FillRequestIntents
import dev.abdullah.vaultkey.fill.FillSession
import dev.abdullah.vaultkey.fill.FormKind
import dev.abdullah.vaultkey.fill.ParsedForm
import dev.abdullah.vaultkey.fill.InlineChips
import dev.abdullah.vaultkey.fill.PendingSave
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
 * A login page also carries a SaveInfo: after the user submits, the system
 * offers to save and [onSaveRequest] hands the captured login to the app,
 * which owns every vault write.
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
        if (parsed.kind != FormKind.LOGIN) return respondWithSection(parsed, target)
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
        // Offer to save what the user submits on a login page (Android 9+, where
        // the save request can hand back an activity to run).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && passwordIds.isNotEmpty()) {
            val save = SaveInfo.Builder(
                SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                passwordIds.toTypedArray(),
            ).setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
            if (usernameIds.isNotEmpty()) save.setOptionalIds(usernameIds.toTypedArray())
            response.setSaveInfo(save.build())
        }
        return response.build()
    }

    /**
     * A card or address form: one chip, behind the fingerprint. These forms
     * are not tied to a site, so nothing is confirmed by host and nothing is
     * filled without the sheet; with a single saved card or identity the
     * sheet fills it straight away. The full-app flow cannot answer them,
     * so without a fingerprint key there is nothing to offer.
     */
    private fun respondWithSection(parsed: ParsedForm<ViewFieldNode>, target: RequestTarget): FillResponse? {
        if (!VaultKeyWrap(this).hasWrappedKey()) return null
        val roles = ArrayList<String>()
        val ids = ArrayList<AutofillId>()
        if (parsed.kind == FormKind.CARD) {
            parsed.card.forEach { (field, node) -> roles.add(field.name); ids.add(node.autofillId!!) }
        } else {
            parsed.address.forEach { (field, node) -> roles.add(field.name); ids.add(node.autofillId!!) }
        }
        val intent = FillRequestIntents.put(
            Intent(this, FillUnlockActivity::class.java), target, ArrayList(), ArrayList(), ArrayList(),
        )
        FillRequestIntents.putSection(intent, parsed.kind, roles, ids)
        return FillResponse.Builder().addDataset(
            DatasetFactory.locked(this, "Vaultly", ids, DatasetFactory.authIntent(this, AUTH_REQUEST_CODE, intent)),
        ).build()
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        worker.execute {
            val capture = capture(request)
            if (capture == null) {
                callback.onSuccess()
                return@execute
            }
            PendingSave.set(capture)
            // Storing goes through the app, which owns every vault write: it
            // opens, unlocks, and asks before saving.
            val intent = Intent(this, MainActivity::class.java).putExtra(MainActivity.EXTRA_SAVE, true)
            val pending = PendingIntent.getActivity(
                this, SAVE_REQUEST_CODE, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                callback.onSuccess(pending.intentSender)
            } else {
                callback.onSuccess()
            }
        }
    }

    /** The submitted login, or null when there is no password to keep. */
    private fun capture(request: SaveRequest): PendingSave.Capture? {
        val structure = request.fillContexts.lastOrNull()?.structure ?: return null
        val clientPackage = structure.activityComponent.packageName
        if (clientPackage == packageName) return null
        val parsed = FormParser.parse(ViewFieldNode.roots(structure))
        val password = parsed.passwords.firstNotNullOfOrNull { it.enteredText?.takeIf(String::isNotEmpty) }
            ?: return null
        val username = parsed.usernames.firstNotNullOfOrNull { it.enteredText?.takeIf(String::isNotEmpty) }.orEmpty()
        val target = RequestTarget.resolve(
            packageName = clientPackage,
            signers = AppSigners.of(this, clientPackage),
            webDomain = parsed.webDomain,
            allowlist = BrowserAllowlist.get(this),
        )
        return PendingSave.Capture(
            username.toCharArray(),
            password.toCharArray(),
            host = (target as? RequestTarget.Web)?.host,
            packageName = (target as? RequestTarget.App)?.packageName,
        )
    }

    private companion object {
        const val AUTH_REQUEST_CODE = 4201
        const val SESSION_REQUEST_CODE = 4202
        const val SAVE_REQUEST_CODE = 4203
        const val TIMING_TAG = "vaultly.fill"
    }
}
