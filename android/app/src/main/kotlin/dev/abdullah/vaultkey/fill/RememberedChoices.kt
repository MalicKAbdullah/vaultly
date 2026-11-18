package dev.abdullah.vaultkey.fill

import android.content.Context
import java.security.MessageDigest

/**
 * The entry the user picked for an exact target, kept on this device. The
 * stored key is a hash of the target and the value a random entry id, so
 * the file names neither a site nor an account. An app's key includes its
 * signing certificate: a repackaged app does not inherit the choice.
 */
class RememberedChoices(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun get(target: RequestTarget): String? = prefs.getString(hash(target), null)

    fun put(target: RequestTarget, entryId: String) {
        prefs.edit().putString(hash(target), entryId).apply()
    }

    fun forget(target: RequestTarget) {
        prefs.edit().remove(hash(target)).apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS = "vaultly_remembered_choices"

        /** Stable text identity of a target. */
        fun identity(target: RequestTarget): String = when (target) {
            is RequestTarget.Web -> "web:${target.host}"
            is RequestTarget.App -> "app:${target.packageName}:${target.certSha256}"
        }

        fun hash(target: RequestTarget): String =
            MessageDigest.getInstance("SHA-256").digest(identity(target).toByteArray())
                .joinToString("") { "%02x".format(it) }
    }
}
