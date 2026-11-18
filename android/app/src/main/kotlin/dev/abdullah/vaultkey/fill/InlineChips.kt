package dev.abdullah.vaultkey.fill

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.autofill.FillRequest
import android.service.autofill.InlinePresentation
import android.widget.inline.InlinePresentationSpec
import androidx.annotation.RequiresApi
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import dev.abdullah.vaultkey.R

/**
 * Chips for the keyboard's suggestion strip (Android 11+), one per dataset
 * in the order the keyboard gave room for. A keyboard without inline
 * support sends no request, and the dropdown is used as before.
 */
@RequiresApi(Build.VERSION_CODES.R)
class InlineChips private constructor(
    private val context: Context,
    private val specs: List<InlinePresentationSpec>,
    private val maxCount: Int,
) {
    /** Whether the keyboard has room for another chip after [taken]. */
    fun hasRoom(taken: Int): Boolean = taken < maxCount && specs.isNotEmpty()

    /**
     * The chip for the [index]th dataset, or null when the keyboard cannot
     * render the style it asked for (a version we do not speak).
     */
    fun chip(index: Int, title: String): InlinePresentation? {
        val spec = specs[minOf(index, specs.size - 1)]
        if (!UiVersions.getVersions(spec.style).contains(UiVersions.INLINE_UI_VERSION_1)) return null
        // The attribution tap target is required by the slice; it opens nothing.
        val attribution = PendingIntent.getActivity(
            context, 0, Intent(), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val content = InlineSuggestionUi.newContentBuilder(attribution)
            .setTitle(title)
            .setStartIcon(Icon.createWithResource(context, R.mipmap.ic_launcher))
            .build()
        return InlinePresentation(content.slice, spec, false)
    }

    companion object {
        /** Null when the request carries no inline support. */
        fun of(context: Context, request: FillRequest): InlineChips? {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
            val inline = request.inlineSuggestionsRequest ?: return null
            return InlineChips(context, inline.inlinePresentationSpecs, inline.maxSuggestionCount)
        }
    }
}
