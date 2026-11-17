package dev.abdullah.vaultkey.fill

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Debug builds only: writes each screen Vaultly is asked to fill as a JSON
 * form fixture (the format of `android/app/src/test/resources/forms/`) to
 * `cache/form-dumps/`. Field values are never part of a [FieldNode], and
 * the HTML `value` attribute is dropped. Off until enabled with
 * `adb shell setprop log.tag.VaultlyFormDump DEBUG`.
 */
object FormDump {
    private const val TAG = "VaultlyFormDump"

    fun log(context: Context, roots: List<FieldNode<*>>) {
        if (!Log.isLoggable(TAG, Log.DEBUG)) return
        val json = JSONObject().put("roots", JSONArray(roots.map(::toJson)))
        val dir = File(context.cacheDir, "form-dumps").apply { mkdirs() }
        val file = File(dir, "${System.currentTimeMillis()}.json")
        file.writeText(json.toString(1))
        Log.d(TAG, "wrote ${file.path}")
    }

    private fun toJson(node: FieldNode<*>): JSONObject = JSONObject().apply {
        node.idEntry?.let { put("id", it) }
        node.hint?.let { put("hint", it) }
        if (node.autofillHints.isNotEmpty()) put("hints", JSONArray(node.autofillHints))
        val attributes = node.inputAttributes - "value"
        if (attributes.isNotEmpty()) put("input", JSONObject(attributes))
        if (node.inputType != 0) put("inputType", node.inputType)
        if (node.isTextField) put("text", true)
        node.webDomain?.let { put("domain", it) }
        if (node.children.isNotEmpty()) put("children", JSONArray(node.children.map(::toJson)))
    }
}
