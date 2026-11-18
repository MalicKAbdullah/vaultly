package dev.abdullah.vaultkey.fill

import android.text.InputType

/** The login fields of one screen, and the web domain its page reports. */
class ParsedForm<N>(
    val usernames: List<N>,
    val passwords: List<N>,
    val webDomain: String?,
    /** One-time-code fields: a single input, or a row of one-digit boxes in order. */
    val codes: List<N> = emptyList(),
    val card: Map<CardField, N> = emptyMap(),
    val address: Map<AddressField, N> = emptyMap(),
) {
    /**
     * A form is a card form when it names a card number, a login when it has
     * a password, an address form when it names at least two address fields
     * (an email alone is a username); otherwise whatever login fields it has.
     * The partitions never mix: a card form's name and email fields are not
     * login fields.
     */
    val kind: FormKind = when {
        CardField.NUMBER in card -> FormKind.CARD
        passwords.isNotEmpty() -> FormKind.LOGIN
        address.size >= MIN_ADDRESS_FIELDS -> FormKind.ADDRESS
        else -> FormKind.LOGIN
    }

    val isFillable: Boolean
        get() = when (kind) {
            FormKind.CARD -> card.isNotEmpty()
            FormKind.ADDRESS -> address.isNotEmpty()
            FormKind.LOGIN -> usernames.isNotEmpty() || passwords.isNotEmpty() || codes.isNotEmpty()
        }

    private companion object {
        const val MIN_ADDRESS_FIELDS = 2
    }
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

    private enum class Kind { USERNAME, PASSWORD, CODE }

    private val codeWords = setOf("otp", "totp", "2fa", "mfa", "tfa")

    /** `verification code`, `security code`, `authenticator code`: `code` beside one of these. */
    private val codeQualifiers = setOf("verification", "verify", "security", "authenticator", "authentication")
    private val CHROME_TYPE_KEYS = listOf("ua-autofill-hints", "computed-autofill-hints")
    private const val MAX_BOX_ROW = 8
    private const val MIN_BOX_ROW = 4

    fun <N : FieldNode<N>> parse(roots: List<N>): ParsedForm<N> {
        val usernames = ArrayList<N>()
        val passwords = ArrayList<N>()
        val codes = ArrayList<N>()
        val card = LinkedHashMap<CardField, N>()
        val address = LinkedHashMap<AddressField, N>()
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
                val tokens = PaymentAndAddress.tokens(node.autofillHints, attributes)
                PaymentAndAddress.cardField(tokens)?.let { card.putIfAbsent(it, node) }
                PaymentAndAddress.addressField(tokens)?.let { address.putIfAbsent(it, node) }
                when (kind) {
                    Kind.PASSWORD -> passwords.add(node)
                    Kind.USERNAME -> usernames.add(node)
                    Kind.CODE -> codes.add(node)
                    null -> Unit
                }
            }
            node.children.forEach(::visit)
            if (codes.isEmpty()) codes.addAll(digitBoxes(node))
        }
        roots.forEach(::visit)
        return ParsedForm(usernames, passwords, webDomain, codes, card, address)
    }

    /** `getWebDomain()` is documented as a bare host; scheme, port and path are stripped all the same. */
    private fun normalizeDomain(raw: String): String {
        var value = raw.trim().lowercase()
        val scheme = value.indexOf("://")
        if (scheme >= 0) value = value.substring(scheme + 3)
        value = value.substringBefore('/').substringBefore(':')
        return value.removePrefix("www.")
    }

    /**
     * A row of 4 to 8 sibling inputs that each take one character and
     * carry no other meaning: the boxes of a code entered digit by digit.
     */
    private fun <N : FieldNode<N>> digitBoxes(parent: N): List<N> {
        val boxes = parent.children.filter {
            it.isTextField && it.inputAttributes["maxlength"] == "1" && classify(it, it.inputAttributes) == null
        }
        return if (boxes.size in MIN_BOX_ROW..MAX_BOX_ROW) boxes else emptyList()
    }

    private fun isCodeByWords(words: Set<String>, attributes: Map<String, String>): Boolean {
        val maxLength = attributes["maxlength"]?.toIntOrNull()
        if (maxLength != null && maxLength > MAX_BOX_ROW) return false
        if (words.any { it in codeWords }) return true
        // The word splitter breaks `2fa` into `2` and `fa`, and `two-factor` into two words.
        if ("2" in words && "fa" in words) return true
        if ("two" in words && "factor" in words) return true
        return "code" in words && words.any { it in codeQualifiers }
    }

    private fun classify(node: FieldNode<*>, attributes: Map<String, String>): Kind? {
        for (hint in node.autofillHints) {
            val h = hint.lowercase()
            if (h.contains("otp")) return Kind.CODE
            if (h.contains("password")) return Kind.PASSWORD
            if (h.contains("username") || h.contains("email")) return Kind.USERNAME
        }

        classifyHtml(attributes)?.let { return it }

        val words = buildSet {
            addAll(words(node.hint))
            addAll(words(node.idEntry))
            addAll(words(attributes["name"]))
            addAll(words(attributes["id"]))
        }
        if (isCodeByWords(words, attributes)) return Kind.CODE

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

        if (words.any { it in passwordWords }) return Kind.PASSWORD
        if (words.any { it in usernameWords }) return Kind.USERNAME
        return null
    }

    private fun classifyHtml(attributes: Map<String, String>): Kind? {
        if (attributes.isEmpty()) return null
        val autocomplete = attributes["autocomplete"].orEmpty().lowercase().split(' ')
        if ("one-time-code" in autocomplete) return Kind.CODE
        // Chrome reports the field type it derived from `autocomplete` here, not the attribute itself.
        if (CHROME_TYPE_KEYS.any { attributes[it]?.contains("ONE_TIME_CODE") == true }) return Kind.CODE
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
