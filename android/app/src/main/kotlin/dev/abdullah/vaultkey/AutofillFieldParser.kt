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
                // Browsers (Chrome, etc.) tag the DOM nodes of the page being
                // shown with the site's host; the package is just the browser.
                // Prefer a domain that sits on/near a form field, but fall back
                // to any node that carries one.
                if (!node.webDomain.isNullOrBlank()) {
                    val kind = classify(node)
                    if (webDomain == null || kind != FieldKind.NONE) {
                        webDomain = normalizeDomain(node.webDomain!!)
                    }
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

    /** `getWebDomain()` is a bare host, but be defensive about scheme/path. */
    private fun normalizeDomain(raw: String): String {
        var value = raw.trim()
        val scheme = value.indexOf("://")
        if (scheme >= 0) value = value.substring(scheme + 3)
        value = value.substringBefore('/').substringBefore(':')
        return value.removePrefix("www.")
    }

    private fun classify(node: AssistStructure.ViewNode): FieldKind {
        // 1. Explicit autofill hints set by well-behaved apps.
        node.autofillHints?.forEach { hint ->
            val h = hint.lowercase()
            if (h.contains("password")) return FieldKind.PASSWORD
            if (h.contains("username") || h.contains("email")) return FieldKind.USERNAME
        }

        // 2. HTML attributes of the <input> element. Browser web forms rarely
        //    set autofillHints, but they do expose the DOM: the `type` and
        //    `autocomplete` attributes are the strongest browser signals.
        classifyHtml(node)?.let { return it }

        // 3. Input-type heuristics (textPassword, textWebPassword, email).
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

        // 4. Keyword heuristics on hint text, view id, and any HTML name/id.
        val html = htmlAttributes(node)
        val haystack = buildString {
            append(node.hint.orEmpty()).append(' ')
            append(node.idEntry.orEmpty()).append(' ')
            append(html["name"].orEmpty()).append(' ')
            append(html["id"].orEmpty())
        }.lowercase()
        if (haystack.isNotBlank()) {
            if (passwordKeywords.any { haystack.contains(it) }) return FieldKind.PASSWORD
            if (usernameKeywords.any { haystack.contains(it) }) return FieldKind.USERNAME
        }
        return FieldKind.NONE
    }

    /** Classifies a browser field from its HTML `autocomplete`/`type`. */
    private fun classifyHtml(node: AssistStructure.ViewNode): FieldKind? {
        val attrs = htmlAttributes(node)
        if (attrs.isEmpty()) return null

        val autocomplete = attrs["autocomplete"]?.lowercase().orEmpty()
        if (autocomplete.contains("password")) return FieldKind.PASSWORD
        if (autocomplete.contains("username") || autocomplete.contains("email")) {
            return FieldKind.USERNAME
        }

        return when (attrs["type"]?.lowercase()) {
            "password" -> FieldKind.PASSWORD
            "email" -> FieldKind.USERNAME
            else -> null
        }
    }

    /** Lower-cased HTML attribute map for an `<input>` node, or empty. */
    private fun htmlAttributes(node: AssistStructure.ViewNode): Map<String, String> {
        val info = node.htmlInfo ?: return emptyMap()
        if (!info.tag.equals("input", ignoreCase = true)) return emptyMap()
        val attrs = info.attributes ?: return emptyMap()
        val map = HashMap<String, String>(attrs.size)
        for (pair in attrs) {
            val name = pair.first ?: continue
            map[name.lowercase()] = pair.second ?: ""
        }
        return map
    }

    private fun visit(node: AssistStructure.ViewNode, action: (AssistStructure.ViewNode) -> Unit) {
        action(node)
        for (i in 0 until node.childCount) {
            visit(node.getChildAt(i), action)
        }
    }
}
