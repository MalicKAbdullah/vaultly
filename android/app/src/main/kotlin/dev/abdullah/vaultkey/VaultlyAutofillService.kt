package dev.abdullah.vaultkey

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.widget.RemoteViews
import androidx.annotation.RequiresApi

/**
 * Vaultly as an Android autofill provider.
 *
 * On a fill request we parse the form, and when it looks like a login we
 * answer with a single dataset locked behind authentication: tapping
 * "Unlock Vaultly to fill" launches [MainActivity], which walks the user
 * through unlock + entry selection and returns the filled dataset as the
 * authentication result.
 *
 * Save requests (capturing new logins) are intentionally out of scope:
 * no SaveInfo is ever attached, so [onSaveRequest] never fires in practice.
 */
@RequiresApi(Build.VERSION_CODES.O)
class VaultlyAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val context = request.fillContexts.lastOrNull()
        if (context == null) {
            callback.onSuccess(null)
            return
        }

        val parsed = try {
            AutofillFieldParser.parse(context.structure)
        } catch (_: Exception) {
            callback.onSuccess(null)
            return
        }
        if (!parsed.isFillable) {
            callback.onSuccess(null)
            return
        }

        // Never offer to fill our own unlock screen.
        val clientPackage = context.structure.activityComponent?.packageName
        if (clientPackage == packageName) {
            callback.onSuccess(null)
            return
        }

        val presentation = RemoteViews(packageName, R.layout.vaultly_autofill_item)

        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_AUTOFILL, true)
            putExtra(MainActivity.EXTRA_AUTOFILL_PACKAGE, clientPackage)
            putExtra(MainActivity.EXTRA_AUTOFILL_DOMAIN, parsed.webDomain)
            putParcelableArrayListExtra(
                MainActivity.EXTRA_AUTOFILL_USERNAME_IDS,
                parsed.usernameIds,
            )
            putParcelableArrayListExtra(
                MainActivity.EXTRA_AUTOFILL_PASSWORD_IDS,
                parsed.passwordIds,
            )
        }
        var pendingFlags = PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            pendingFlags = pendingFlags or PendingIntent.FLAG_MUTABLE
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            AUTH_REQUEST_CODE,
            intent,
            pendingFlags,
        )

        val dataset = Dataset.Builder(presentation).apply {
            // Auth-gated datasets still need every fillable id registered;
            // the real values arrive in the authentication result.
            parsed.allIds.forEach { setValue(it, null, presentation) }
            setAuthentication(pendingIntent.intentSender)
        }.build()

        callback.onSuccess(
            FillResponse.Builder().addDataset(dataset).build(),
        )
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // No SaveInfo is declared, so nothing to save. Kept as a no-op.
        callback.onSuccess()
    }

    private companion object {
        const val AUTH_REQUEST_CODE = 4201
    }
}
