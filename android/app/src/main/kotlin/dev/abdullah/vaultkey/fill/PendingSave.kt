package dev.abdullah.vaultkey.fill

/**
 * A login captured by a save request, on its way to the app that stores it.
 * Held in this process only (an Intent would pass the password through the
 * system) and zeroed when the save screen finishes or the capture is replaced.
 */
object PendingSave {
    class Capture(
        val username: CharArray,
        val password: CharArray,
        /** The trusted browser's page host, or null for an app. */
        val host: String?,
        /** The app's package for an app, null for a web page. */
        val packageName: String?,
    )

    @Volatile private var current: Capture? = null

    @Synchronized
    fun set(capture: Capture) {
        clear()
        current = capture
    }

    fun get(): Capture? = current

    @Synchronized
    fun clear() {
        current?.let {
            it.username.fill('\u0000')
            it.password.fill('\u0000')
        }
        current = null
    }
}
