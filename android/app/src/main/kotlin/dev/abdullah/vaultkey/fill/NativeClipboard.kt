package dev.abdullah.vaultkey.fill

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle

/** Puts a one-time code on the clipboard for 30 seconds. */
object NativeClipboard {
    private const val CLEAR_AFTER_MS = 30_000L
    private val handler = Handler(Looper.getMainLooper())
    private var pendingClear: Runnable? = null
    private var listener: ClipboardManager.OnPrimaryClipChangedListener? = null

    /**
     * Copies [code], hiding the preview where the platform allows it, and
     * clears it later only if nothing else has been copied since. Reading
     * the clipboard to compare is refused to background apps, so the
     * decision rests on the change listener instead.
     */
    fun copySensitive(context: Context, code: String) {
        val app = context.applicationContext
        val clipboard = app.getSystemService(ClipboardManager::class.java)
        cancel(clipboard)
        val clip = ClipData.newPlainText("Vaultly code", code)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }
        clipboard.setPrimaryClip(clip)

        var replaced = false
        // The listener is added after our own copy, so only later copies reach it.
        val changed = ClipboardManager.OnPrimaryClipChangedListener { replaced = true }
        handler.post { clipboard.addPrimaryClipChangedListener(changed) }
        listener = changed
        val clear = Runnable {
            clipboard.removePrimaryClipChangedListener(changed)
            if (!replaced) clipboard.clearPrimaryClip()
            listener = null
            pendingClear = null
        }
        pendingClear = clear
        handler.postDelayed(clear, CLEAR_AFTER_MS)
    }

    private fun cancel(clipboard: ClipboardManager) {
        pendingClear?.let(handler::removeCallbacks)
        listener?.let(clipboard::removePrimaryClipChangedListener)
        pendingClear = null
        listener = null
    }
}
