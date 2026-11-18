package dev.abdullah.vaultkey.fill

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class FillSessionTest {
    private var now = 1_000L
    private val equivalents = EquivalentDomains.parse(
        """{"groups":[["live.com","microsoftonline.com"],["google.com","youtube.com"]]}""",
    )
    private val chrome = "com.android.chrome"

    private fun web(host: String) = RequestTarget.Web(host, chrome)
    private fun app(pkg: String, cert: String = "AA") = RequestTarget.App(pkg, cert, null)

    @Before fun setUp() {
        FillSession.clock = { now }
        FillSession.wipe()
    }

    @After fun tearDown() = FillSession.wipe()

    private fun arm(begunOn: RequestTarget, url: String = "https://accounts.google.com", totp: Boolean = false) {
        val pw = "secret".toCharArray()
        FillSession.arm(
            null, "e1", "me@x.com", "me@x.com".toCharArray(), pw, null,
            SessionScope.begunOn(begunOn, url, equivalents),
        )
    }

    @Test fun `same host is in scope`() {
        arm(web("accounts.google.com"))
        assertNotNull(FillSession.current(web("accounts.google.com")))
    }

    @Test fun `subdomains and the entry's equivalent domains are in scope`() {
        arm(web("accounts.google.com"))
        assertNotNull(FillSession.current(web("mail.google.com")))
        assertNotNull(FillSession.current(web("www.youtube.com")))
    }

    @Test fun `a look-alike is not in scope`() {
        arm(web("accounts.google.com"))
        assertNull(FillSession.current(web("notgoogle.com")))
        assertNull(FillSession.current(web("google.com.evil.org")))
    }

    @Test fun `a web session is not offered to an app`() {
        arm(web("accounts.google.com"))
        assertNull(FillSession.current(app("com.google.android.gm")))
    }

    @Test fun `an app session covers that app and its own site, not another signer`() {
        arm(app("com.example.shop"), url = "shop.example.com")
        assertNotNull(FillSession.current(app("com.example.shop")))
        assertNull(FillSession.current(app("com.example.shop", cert = "BB")))
        assertNotNull(FillSession.current(web("shop.example.com")))
    }

    @Test fun `it expires after two minutes, checked on read`() {
        arm(web("accounts.google.com"))
        now += FillSession.LIFETIME_MS - 1
        assertNotNull(FillSession.current(web("accounts.google.com")))
        now += 1
        assertNull(FillSession.current(web("accounts.google.com")))
        assertNull(FillSession.liveEntryId())
    }

    @Test fun `wipe zeroes the secrets and ends the session`() {
        val pw = "secret".toCharArray()
        val user = "me".toCharArray()
        FillSession.arm(null, "e1", "me", user, pw, null, SessionScope.begunOn(web("a.com"), "a.com", equivalents))
        FillSession.wipe()
        assertTrue(pw.all { it == '\u0000' } && user.all { it == '\u0000' })
        assertNull(FillSession.current(web("a.com")))
    }

    @Test fun `arming another entry wipes the first`() {
        val first = "one".toCharArray()
        FillSession.arm(null, "e1", "a", "a".toCharArray(), first, null, SessionScope.begunOn(web("a.com"), "a.com", equivalents))
        FillSession.arm(null, "e2", "b", "b".toCharArray(), "two".toCharArray(), null, SessionScope.begunOn(web("b.com"), "b.com", equivalents))
        assertTrue(first.all { it == '\u0000' })
        assertEquals("e2", FillSession.liveEntryId())
        assertFalse(FillSession.current(web("a.com")) != null)
    }
}
