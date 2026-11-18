package dev.abdullah.vaultkey.fill

import android.content.Context

/** The form dumper exists in debug builds only. */
object FormDump {
    @Suppress("UNUSED_PARAMETER")
    fun log(context: Context, roots: List<FieldNode<*>>) = Unit
}
