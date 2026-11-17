package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.passkey.AppSigning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RequestTargetTest {

    private val chromeCert = byteArrayOf(1, 2, 3)
    private val otherCert = byteArrayOf(9, 9, 9)
    private val allowlist = BrowserAllowlist(
        mapOf("com.android.chrome" to setOf(AppSigning.sha256Fingerprint(chromeCert))),
    )

    @Test
    fun `an allowlisted browser with its own certificate reports a web host`() {
        val target = RequestTarget.resolve("com.android.chrome", listOf(chromeCert), "accounts.google.com", allowlist)
        assertEquals(RequestTarget.Web("accounts.google.com", "com.android.chrome"), target)
    }

    @Test
    fun `an app claiming a web domain stays an app`() {
        val target = RequestTarget.resolve("com.evil.app", listOf(otherCert), "google.com", allowlist)
        assertEquals(
            RequestTarget.App("com.evil.app", AppSigning.sha256Fingerprint(otherCert), "google.com"),
            target,
        )
    }

    @Test
    fun `a repackaged browser with the right name but another certificate is an app`() {
        val target = RequestTarget.resolve("com.android.chrome", listOf(otherCert), "google.com", allowlist)
        assertTrue(target is RequestTarget.App)
    }

    @Test
    fun `a browser whose signers cannot be read is an app`() {
        val target = RequestTarget.resolve("com.android.chrome", null, "google.com", allowlist)
        assertEquals(RequestTarget.App("com.android.chrome", null, "google.com"), target)
    }

    @Test
    fun `a trusted browser without a page domain is an app`() {
        val target = RequestTarget.resolve("com.android.chrome", listOf(chromeCert), null, allowlist)
        assertTrue(target is RequestTarget.App)
    }

    @Test
    fun `every signer of a multi-signer package must be listed`() {
        assertFalse(
            allowlist.isTrusted(
                "com.android.chrome",
                listOf(AppSigning.sha256Fingerprint(chromeCert), AppSigning.sha256Fingerprint(otherCert)),
            ),
        )
        assertFalse(allowlist.isTrusted("com.android.chrome", emptyList()))
    }

    @Test
    fun `the bundled allowlist trusts release Chrome only with its certificate`() {
        val json = File("src/main/res/raw/privileged_browsers.json").readText()
        val bundled = BrowserAllowlist.parse(json)
        assertTrue(
            bundled.isTrusted(
                "com.android.chrome",
                listOf("F0:FD:6C:5B:41:0F:25:CB:25:C3:B5:33:46:C8:97:2F:AE:30:F8:EE:74:11:DF:91:04:80:AD:6B:2D:60:DB:83"),
            ),
        )
        assertFalse(bundled.isTrusted("com.android.chrome", listOf("00:11")))
        assertFalse(bundled.isTrusted("com.example.notabrowser", listOf("00:11")))
    }
}
