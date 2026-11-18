package dev.abdullah.vaultkey.fill

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import androidx.annotation.RequiresApi
import dev.abdullah.vaultkey.vault.Totp

/**
 * Behind a "Continue as" chip: hands the session's values to the page, with
 * no UI and no prompt. When the session has been wiped since the chip was
 * drawn, the normal unlock sheet takes over instead, so a stale chip never
 * fills.
 */
@RequiresApi(Build.VERSION_CODES.O)
class FillSessionActivity : Activity() {

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val target = FillRequestIntents.target(intent)
        val session = FillSession.current(target)
        if (session == null) {
            val unlock = Intent(intent).setClass(this, FillUnlockActivity::class.java)
            unlock.addFlags(Intent.FLAG_ACTIVITY_FORWARD_RESULT)
            startActivity(unlock)
            finish()
            return
        }
        val usernameIds: ArrayList<AutofillId> =
            intent.getParcelableArrayListExtra(FillRequestIntents.EXTRA_USERNAME_IDS)!!
        val passwordIds: ArrayList<AutofillId> =
            intent.getParcelableArrayListExtra(FillRequestIntents.EXTRA_PASSWORD_IDS)!!
        val codeIds: ArrayList<AutofillId> =
            intent.getParcelableArrayListExtra(FillRequestIntents.EXTRA_CODE_IDS)!!
        val totp = session.totp
        // A code about to expire could lapse before the site checks it. This
        // activity must finish before it is drawn, so the rare wait blocks here.
        if (codeIds.isNotEmpty() && totp != null) {
            val wait = Totp.waitBeforeUse(totp, System.currentTimeMillis())
            if (wait > 0) Thread.sleep(wait)
        }
        val filled = FillValues.of(
            String(session.username), String(session.password), totp,
            usernameIds, passwordIds, codeIds, System.currentTimeMillis(),
        )
        val dataset = DatasetFactory.filled(this, "Vaultly", filled.values)
        if (filled.lastStep) FillSession.wipe()
        setResult(
            RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, true)
                }
            },
        )
        finish()
    }
}
