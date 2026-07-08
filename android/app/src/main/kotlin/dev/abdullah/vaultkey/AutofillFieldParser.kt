package dev.abdullah.vaultkey

import android.app.assist.AssistStructure
import android.os.Build
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi

/**
 * Walks an [AssistStructure] and picks out the username and password
 * fields of a login form. Kept deliberately thin: classification only —
 * all matching/ranking of vault entries happens in Dart where it is
 * unit-tested.
 */
@RequiresApi(Build.VERSION_CODES.O)
object AutofillFieldParser {

    data class ParsedStructure(
        val usernameIds: ArrayList<AutofillId>,
        val passwordIds: ArrayList<AutofillId>,
        val webDomain: String?,
    ) {
        val allIds: List<AutofillId> get() = usernameIds + passwordIds
        val isFillable: Boolean get() = passwordIds.isNotEmpty() || usernameIds.isNotEmpty()
    }

    private val passwordKeywords = listOf("pass", "pwd", "pin")
    private val usernameKeywords = listOf("user", "email", "login", "account", "identifier")

    fun parse(structure: AssistStructure): ParsedStructure {
        val usernameIds = ArrayList<AutofillId>()
        val passwordIds = ArrayList<AutofillId>()
        var webDomain: String? = null

        for (i in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(i).rootViewNode ?: continue
            visit(root) { node ->
                if (webDomain == null && !node.webDomain.isNullOrBlank()) {
                    webDomain = node.webDomain
                }
                val id = node.autofillId ?: return@visit
                if (node.autofillType != View.AUTOFILL_TYPE_TEXT) return@visit
                when (classify(node)) {
                    FieldKind.PASSWORD -> passwordIds.add(id)
                    FieldKind.USERNAME -> usernameIds.add(id)
                    FieldKind.NONE -> Unit
                }
            }
        }
        return ParsedStructure(usernameIds, passwordIds, webDomain)
    }

    private enum class FieldKind { USERNAME, PASSWORD, NONE }

    private fun classify(node: AssistStructure.ViewNode): FieldKind {
        // 1. Explicit autofill hints set by well-behaved apps.
        node.autofillHints?.forEach { hint ->
            val h = hint.lowercase()
            if (h.contains("password")) return FieldKind.PASSWORD
            if (h.contains("username") || h.contains("email")) return FieldKind.USERNAME
        }

        // 2. Input-type heuristics (textPassword, textWebPassword, email).
        val inputType = node.inputType
        if (inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT) {
            when (inputType and InputType.TYPE_MASK_VARIATION) {
                InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                -> return FieldKind.PASSWORD

                InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                -> return FieldKind.USERNAME
            }
        }

        // 3. Keyword heuristics on the field's hint text and view id.
        val haystack = "${node.hint.orEmpty()} ${node.idEntry.orEmpty()}".lowercase()
        if (haystack.isNotBlank()) {
            if (passwordKeywords.any { haystack.contains(it) }) return FieldKind.PASSWORD
            if (usernameKeywords.any { haystack.contains(it) }) return FieldKind.USERNAME
        }
        return FieldKind.NONE
    }

    private fun visit(node: AssistStructure.ViewNode, action: (AssistStructure.ViewNode) -> Unit) {
        action(node)
        for (i in 0 until node.childCount) {
            visit(node.getChildAt(i), action)
        }
    }
}
