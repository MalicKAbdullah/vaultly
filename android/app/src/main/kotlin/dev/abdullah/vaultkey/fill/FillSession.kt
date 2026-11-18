package dev.abdullah.vaultkey.fill

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import dev.abdullah.vaultkey.vault.TotpParams

/** The one account the user chose, ready for the next pages of the same sign-in. */
class SessionData(
    val entryId: String,
    /** What the "Continue as" chip shows. */
    val label: String,
    val username: CharArray,
    val password: CharArray,
    val totp: TotpParams?,
    val scope: SessionScope,
    internal val expiresAt: Long,
) {
    internal fun zero() {
        username.fill('\u0000')
        password.fill('\u0000')
    }
}

/**
 * In-process memory of the chosen account (never on disk, never inside a
 * `FillResponse`): the password leaves only when a "Continue as" chip is
 * tapped. It is wiped on expiry (a timer, and again on every read), screen
 * off, the last step being filled, arming another entry, and an explicit
 * end. Process death ends it too.
 */
object FillSession {
    const val LIFETIME_MS = 120_000L

    var clock: () -> Long = { SystemClock.elapsedRealtime() }

    private val lock = Any()
    private var data: SessionData? = null
    private var receiver: BroadcastReceiver? = null
    private var appContext: Context? = null
    private val timer by lazy { Handler(Looper.getMainLooper()) }
    private val expire = Runnable { wipe() }

    /** [context] is null in JVM tests: no timer and no screen-off receiver. */
    fun arm(
        context: Context?,
        entryId: String,
        label: String,
        username: CharArray,
        password: CharArray,
        totp: TotpParams?,
        scope: SessionScope,
    ) {
        synchronized(lock) {
            wipeLocked()
            data = SessionData(entryId, label, username, password, totp, scope, clock() + LIFETIME_MS)
            if (context != null) {
                val app = context.applicationContext
                appContext = app
                receiver = object : BroadcastReceiver() {
                    override fun onReceive(c: Context, i: Intent) = wipe()
                }.also { app.registerReceiver(it, IntentFilter(Intent.ACTION_SCREEN_OFF)) }
                timer.postDelayed(expire, LIFETIME_MS)
            }
        }
    }

    /** The live session when [target] is within its scope, else null. */
    fun current(target: RequestTarget): SessionData? = synchronized(lock) {
        val s = data ?: return null
        if (clock() >= s.expiresAt) {
            wipeLocked()
            return null
        }
        if (s.scope.covers(target)) s else null
    }

    /** Whether any session is live, for the entry screen's "Ready" line. */
    fun liveEntryId(): String? = synchronized(lock) {
        val s = data ?: return null
        if (clock() >= s.expiresAt) {
            wipeLocked()
            return null
        }
        s.entryId
    }

    fun wipe() = synchronized(lock) { wipeLocked() }

    private fun wipeLocked() {
        data?.zero()
        data = null
        receiver?.let { appContext?.unregisterReceiver(it) }
        receiver = null
        // The timer exists only for a session armed with a context.
        if (appContext != null) timer.removeCallbacks(expire)
        appContext = null
    }
}
