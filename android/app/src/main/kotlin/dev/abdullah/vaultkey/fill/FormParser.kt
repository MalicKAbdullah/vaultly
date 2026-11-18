package dev.abdullah.vaultkey.fill

import android.text.InputType

/** The login fields of one screen, and the web domain its page reports. */
class ParsedForm<N>(
    val usernames: List<N>,
    val passwords: List<N>,
    val webDomain: String?,
) {
    val isFillable: Boolean get() = usernames.isNotEmpty() || passwords.isNotEmpty()
}

/**
 * Finds the username and password fields of a login form. Classification
 * only: which vault entry belongs to the screen is decided elsewhere.
 *
 * Signals, strongest first: the app's autofill hints, the HTML
 * `autocomplete` and `type` of a browser field, the input type, then
 * keywords in the field's hint text, view id and HTML name/id. Keywords are
 * matched as whole words (`shipping_address` holds no `pin`), split on
 * punctuation, digits and camelCase.
 */
object FormParser {

    private val passwordWords = setOf("password", "passwd", "pass", "pwd", "passcode", "pin")
    private val usernameWords = setOf(
        "user", "username", "userid", "login", "loginid",
        "email", "emailaddress", "account", "identifier",
    )

    private enum class Kind { USERNAME, PASSWORD }

    fun <N : FieldNode<N>> parse(roots: List<N>): ParsedForm<N> {
        val usernames = ArrayList<N>()
        val passwords = ArrayList<N>()
        var webDomain: String? = null

        fun visit(node: N) {
            val attributes = node.inputAttributes
            val kind = classify(node, attributes)
            // A browser tags every DOM node of the page with its host.
            // Prefer the one carried by a login field, else take any.
            node.webDomain?.takeIf { it.isNotBlank() }?.let { domain ->
                if (webDomain == null || kind != null) webDomain = normalizeDomain(domain)
            }
            if (node.isTextField) {
                when (kind) {
                    Kind.PASSWORD -> passwords.add(node)
                    Kind.USERNAME -> usernames.add(node)
                    null -> Unit
                }
            }
            node.children.forEach(::visit)
        }
        roots.forEach(::visit)
        return ParsedForm(usernames, passwords, webDomain)
    }

    /** `getWebDomain()` is documented as a bare host; scheme, port and path are stripped all the same. */
    private fun normalizeDomain(raw: String): String {
        var value = raw.trim().lowercase()
        val scheme = value.indexOf("://")
        if (scheme >= 0) value = value.substring(scheme + 3)
        value = value.substringBefore('/').substringBefore(':')
        return value.removePrefix("www.")
    }

    private fun classify(node: FieldNode<*>, attributes: Map<String, String>): Kind? {
        for (hint in node.autofillHints) {
            val h = hint.lowercase()
            if (h.contains("password")) return Kind.PASSWORD
            if (h.contains("username") || h.contains("email")) return Kind.USERNAME
        }

        classifyHtml(attributes)?.let { return it }

        val inputType = node.inputType
        if (inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT) {
            when (inputType and InputType.TYPE_MASK_VARIATION) {
                InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                -> return Kind.PASSWORD

                InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                -> return Kind.USERNAME
            }
        }

        val words = buildSet {
            addAll(words(node.hint))
            addAll(words(node.idEntry))
            addAll(words(attributes["name"]))
            addAll(words(attributes["id"]))
        }
        if (words.any { it in passwordWords }) return Kind.PASSWORD
        if (words.any { it in usernameWords }) return Kind.USERNAME
        return null
    }

    private fun classifyHtml(attributes: Map<String, String>): Kind? {
        if (attributes.isEmpty()) return null
        val autocomplete = attributes["autocomplete"].orEmpty().lowercase().split(' ')
        if (autocomplete.any { it.endsWith("password") }) return Kind.PASSWORD
        if (autocomplete.any { it == "username" || it == "email" }) return Kind.USERNAME
        return when (attributes["type"]?.lowercase()) {
            "password" -> Kind.PASSWORD
            "email" -> Kind.USERNAME
            else -> null
        }
    }

    private val camelBoundary = Regex("(?<=\\p{Ll})(?=\\p{Lu})|(?<=\\p{L})(?=\\p{N})|(?<=\\p{N})(?=\\p{L})")
    private val separators = Regex("[^\\p{L}\\p{N}]+")

    /** `shipping_address` → [shipping, address]; `userName2` → [user, name, 2]. */
    internal fun words(text: String?): List<String> {
        if (text.isNullOrEmpty()) return emptyList()
        return text.split(camelBoundary)
            .flatMap { it.split(separators) }
            .filter { it.isNotEmpty() }
            .map { it.lowercase() }
    }
}
