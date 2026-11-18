package dev.abdullah.vaultkey.fill

import android.content.Context

/** Fill preferences kept on the native side, where the fill path reads them. */
class FillSettings(context: Context) {
    private val prefs = context.getSharedPreferences("vaultly_fill_settings", Context.MODE_PRIVATE)

    /** Keep the chosen account ready for the next pages of a sign-in. On by default. */
    var sessionEnabled: Boolean
        get() = prefs.getBoolean(SESSION, true)
        set(value) = prefs.edit().putBoolean(SESSION, value).apply()

    /** Copy the current 2FA code after a password fill. Off by default. */
    var copyCode: Boolean
        get() = prefs.getBoolean(COPY_CODE, false)
        set(value) = prefs.edit().putBoolean(COPY_CODE, value).apply()

    private companion object {
        const val SESSION = "session_enabled"
        const val COPY_CODE = "copy_code"
    }
}
