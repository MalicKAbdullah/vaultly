package dev.abdullah.vaultkey.passkey

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RelyingPartyTest {

    @Test
    fun `rp id must be the origin host or a parent domain of it`() {
        assertTrue(RpIdRules.isValidForOrigin("webauthn.io", "https://webauthn.io"))
        assertTrue(RpIdRules.isValidForOrigin("example.com", "https://login.example.com"))
        assertTrue(RpIdRules.isValidForOrigin("example.com", "https://example.com:8443/"))
        assertTrue(RpIdRules.isValidForOrigin("localhost", "http://localhost:3000"))

        assertFalse(RpIdRules.isValidForOrigin("login.example.com", "https://example.com"))
        assertFalse(RpIdRules.isValidForOrigin("example.com", "https://badexample.com"))
        assertFalse(RpIdRules.isValidForOrigin("example.com", "https://example.com.evil.io"))
        assertFalse(RpIdRules.isValidForOrigin("com", "https://example.com"))
        assertFalse(RpIdRules.isValidForOrigin("", "https://example.com"))
    }

    @Test
    fun `only secure web origins count`() {
        assertEquals("example.com", RpIdRules.secureOriginHost("https://Example.com"))
        assertNull(RpIdRules.secureOriginHost("http://example.com"))
        assertNull(RpIdRules.secureOriginHost("https://user@example.com"))
        assertNull(RpIdRules.secureOriginHost("https://example.com/path"))
        assertNull(RpIdRules.secureOriginHost("android:apk-key-hash:abc"))
        assertFalse(RpIdRules.isValidForOrigin("example.com", "http://example.com"))
    }

    @Test
    fun `apk-key-hash origin and fingerprint encode the certificate's SHA-256`() {
        val cert = "certificate".toByteArray()
        val digest = WebAuthn.sha256(cert)
        assertEquals("android:apk-key-hash:" + Base64Url.encode(digest), AppSigning.apkKeyHashOrigin(cert))
        val fingerprint = AppSigning.sha256Fingerprint(cert)
        assertEquals(32 * 3 - 1, fingerprint.length)
        assertArrayEquals(digest, hex(fingerprint.replace(":", "")))
        assertEquals(fingerprint.uppercase(), fingerprint)
    }

    private val statements = """
        [
          {"relation": ["delegate_permission/common.handle_all_urls"],
           "target": {"namespace": "android_app", "package_name": "com.other.app",
                      "sha256_cert_fingerprints": ["AA:BB"]}},
          {"relation": ["delegate_permission/common.handle_all_urls",
                        "delegate_permission/common.get_login_creds"],
           "target": {"namespace": "android_app", "package_name": "com.example.app",
                      "sha256_cert_fingerprints": ["0a:1b:2c"]}},
          {"relation": ["delegate_permission/common.get_login_creds"],
           "target": {"namespace": "web", "site": "https://example.com"}}
        ]
    """.trimIndent()

    @Test
    fun `asset links delegate login to the listed app and certificate`() {
        assertTrue(AssetLinks.delegatesLogin(statements, "com.example.app", listOf("0A:1B:2C")))
        assertFalse(AssetLinks.delegatesLogin(statements, "com.example.app", listOf("FF:FF:FF")))
        assertFalse(AssetLinks.delegatesLogin(statements, "com.evil.app", listOf("0A:1B:2C")))
        // handle_all_urls alone does not delegate sign-in credentials.
        assertFalse(AssetLinks.delegatesLogin(statements, "com.other.app", listOf("AA:BB")))
        assertFalse(AssetLinks.delegatesLogin("not json", "com.example.app", listOf("0A:1B:2C")))
        assertEquals("https://example.com/.well-known/assetlinks.json", AssetLinks.url("example.com"))
    }
}
