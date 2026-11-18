package dev.abdullah.vaultkey.fill

import android.content.Context
import android.content.Intent
import android.view.autofill.AutofillId
import dev.abdullah.vaultkey.MainActivity

/** The extras that describe one fill request to the activity that answers it. */
object FillRequestIntents {
    const val EXTRA_KIND = "vaultly_target_kind"
    const val EXTRA_HOST = "vaultly_target_host"
    const val EXTRA_PACKAGE = "vaultly_target_package"
    const val EXTRA_CERT = "vaultly_target_cert"
    const val EXTRA_USERNAME_IDS = "vaultly_username_ids"
    const val EXTRA_PASSWORD_IDS = "vaultly_password_ids"
    const val EXTRA_CODE_IDS = "vaultly_code_ids"

    private const val KIND_WEB = "web"
    private const val KIND_APP = "app"

    fun put(
        intent: Intent,
        target: RequestTarget,
        usernameIds: ArrayList<AutofillId>,
        passwordIds: ArrayList<AutofillId>,
        codeIds: ArrayList<AutofillId>,
    ): Intent = intent.apply {
        when (target) {
            is RequestTarget.Web -> {
                putExtra(EXTRA_KIND, KIND_WEB)
                putExtra(EXTRA_HOST, target.host)
                putExtra(EXTRA_PACKAGE, target.browserPackage)
            }
            is RequestTarget.App -> {
                putExtra(EXTRA_KIND, KIND_APP)
                putExtra(EXTRA_PACKAGE, target.packageName)
                putExtra(EXTRA_CERT, target.certSha256)
            }
        }
        putParcelableArrayListExtra(EXTRA_USERNAME_IDS, usernameIds)
        putParcelableArrayListExtra(EXTRA_PASSWORD_IDS, passwordIds)
        putParcelableArrayListExtra(EXTRA_CODE_IDS, codeIds)
    }

    fun target(intent: Intent): RequestTarget {
        val pkg = intent.getStringExtra(EXTRA_PACKAGE)!!
        return when (val kind = intent.getStringExtra(EXTRA_KIND)) {
            KIND_WEB -> RequestTarget.Web(intent.getStringExtra(EXTRA_HOST)!!, pkg)
            KIND_APP -> RequestTarget.App(pkg, intent.getStringExtra(EXTRA_CERT), claimedDomain = null)
            else -> error("Unknown target kind $kind")
        }
    }

    /** The full-app flow ([MainActivity]) for the same request. */
    fun mainActivity(
        context: Context,
        target: RequestTarget,
        usernameIds: ArrayList<AutofillId>,
        passwordIds: ArrayList<AutofillId>,
    ): Intent = Intent(context, MainActivity::class.java).apply {
        putExtra(MainActivity.EXTRA_AUTOFILL, true)
        when (target) {
            is RequestTarget.Web -> putExtra(MainActivity.EXTRA_AUTOFILL_DOMAIN, target.host)
            is RequestTarget.App -> putExtra(MainActivity.EXTRA_AUTOFILL_PACKAGE, target.packageName)
        }
        putParcelableArrayListExtra(MainActivity.EXTRA_AUTOFILL_USERNAME_IDS, usernameIds)
        putParcelableArrayListExtra(MainActivity.EXTRA_AUTOFILL_PASSWORD_IDS, passwordIds)
    }
}
