package dev.abdullah.vaultkey.fill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class FormParserTest {

    private fun parse(fixture: String) = FormParser.parse(JsonFieldNode.fixture(fixture))

    private fun ParsedForm<JsonFieldNode>.usernameLabels() = usernames.map { it.label }
    private fun ParsedForm<JsonFieldNode>.passwordLabels() = passwords.map { it.label }

    @Test
    fun `Google email page`() {
        val form = parse("google_email")
        assertEquals(listOf("identifier"), form.usernameLabels())
        assertEquals(listOf("hiddenPassword"), form.passwordLabels())
        assertEquals("accounts.google.com", form.webDomain)
    }

    @Test
    fun `Google password page keeps the hidden username field`() {
        val form = parse("google_password")
        assertEquals(listOf("identifier"), form.usernameLabels())
        assertEquals(listOf("Passwd"), form.passwordLabels())
    }

    @Test
    fun `Microsoft email then password pages`() {
        assertEquals(listOf("loginfmt"), parse("microsoft_email").usernameLabels())
        val password = parse("microsoft_password")
        assertEquals(listOf("passwd"), password.passwordLabels())
        assertEquals("login.live.com", password.webDomain)
    }

    @Test
    fun `GitHub login`() {
        val form = parse("github_login")
        assertEquals(listOf("login"), form.usernameLabels())
        assertEquals(listOf("password"), form.passwordLabels())
    }

    @Test
    fun `Amazon sign-in reports the host without www`() {
        val form = parse("amazon_signin")
        assertEquals(listOf("email"), form.usernameLabels())
        assertEquals(listOf("password"), form.passwordLabels())
        assertEquals("amazon.com", form.webDomain)
    }

    @Test
    fun `sign-up with new and confirm password`() {
        val form = parse("signup")
        assertEquals(listOf("new_username"), form.usernameLabels())
        assertEquals(listOf("new_password", "confirm_password"), form.passwordLabels())
    }

    @Test
    fun `shipping address fields are not passwords`() {
        val form = parse("shipping_address")
        assertEquals(emptyList<String>(), form.passwordLabels())
        assertEquals(emptyList<String>(), form.usernameLabels())
        assertFalse(form.isFillable)
    }

    @Test
    fun `keywords count as whole words`() {
        val form = parse("keyword_only_login")
        assertEquals(listOf("user_name"), form.usernameLabels())
        assertEquals(listOf("pin"), form.passwordLabels())
    }

    @Test
    fun `native app with autofill hints`() {
        val form = parse("native_app_login")
        assertEquals(listOf("email"), form.usernameLabels())
        assertEquals(listOf("password"), form.passwordLabels())
        assertNull(form.webDomain)
    }

    @Test
    fun `a WebView's domain is reported as parsed, trust is decided elsewhere`() {
        assertEquals("accounts.google.com", parse("webview_claiming_domain").webDomain)
    }

    @Test
    fun `words split on punctuation, camelCase and digits`() {
        assertEquals(listOf("shipping", "address"), FormParser.words("shipping_address"))
        assertEquals(listOf("user", "name", "2"), FormParser.words("userName2"))
        assertEquals(listOf("identifier", "id"), FormParser.words("identifierId"))
        assertEquals(listOf("enter", "your", "password"), FormParser.words("Enter your password"))
        assertEquals(emptyList<String>(), FormParser.words(null))
    }

    @Test
    fun `one-time-code autocomplete is a code field, not a password`() {
        val form = parse("otp_autocomplete")
        assertEquals(listOf("pin"), form.codes.map { it.label })
        assertEquals(emptyList<String>(), form.passwordLabels())
    }

    @Test
    fun `verification code by name is a code field`() {
        assertEquals(1, parse("otp_by_name").codes.size)
    }

    @Test
    fun `a row of one-character boxes is a code in order`() {
        assertEquals(listOf("d0", "d1", "d2", "d3", "d4", "d5"), parse("otp_boxes").codes.map { it.label })
    }

    @Test
    fun `a zip code or a lone one-character field is not a one-time code`() {
        assertEquals(emptyList<String>(), parse("not_otp_zip").codes.map { it.label })
        assertEquals(emptyList<String>(), parse("shipping_address").codes.map { it.label })
    }

    @Test
    fun `a code field Chrome typed from autocomplete is a code field`() {
        assertEquals(listOf("code"), parse("otp_chrome_type").codes.map { it.label })
    }

    @Test
    fun `a checkout card form is a card form and its email is not a login field`() {
        val form = parse("checkout_card")
        assertEquals(FormKind.CARD, form.kind)
        assertEquals(
            setOf(CardField.HOLDER, CardField.NUMBER, CardField.EXP_COMBINED, CardField.CVC),
            form.card.keys,
        )
        assertEquals(listOf("email"), form.usernameLabels())
    }

    @Test
    fun `a shipping form is an address form`() {
        val form = parse("checkout_address")
        assertEquals(FormKind.ADDRESS, form.kind)
        assertEquals(
            setOf(AddressField.FULL_NAME, AddressField.STREET, AddressField.POSTAL, AddressField.EMAIL),
            form.address.keys,
        )
    }

    @Test
    fun `login forms stay login forms`() {
        assertEquals(FormKind.LOGIN, parse("github_login").kind)
        assertEquals(FormKind.LOGIN, parse("signup").kind)
        assertEquals(FormKind.LOGIN, parse("google_email").kind)
    }

    @Test
    fun `an email field alone is not an address form`() {
        assertEquals(FormKind.LOGIN, parse("otp_by_name").kind)
    }
}
