package dev.abdullah.vaultkey.vault

import dev.abdullah.vaultkey.fill.FillValues
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TotpTest {
    @Test
    fun `matches the RFC 6238 vectors shared with Dart`() {
        val vectors = JSONArray(javaClass.getResource("/totp_vectors.json")!!.readText())
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val params = TotpParams(v.getString("secret"), v.getString("algorithm"), v.getInt("digits"), v.getInt("period"))
            assertEquals(v.toString(), v.getString("code"), Totp.code(params, v.getLong("unixSeconds") * 1000))
        }
    }

    private val sha1 = TotpParams("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "SHA1", 6, 30)

    @Test
    fun `waits out the last three seconds of a period`() {
        assertEquals(0, Totp.waitBeforeUse(sha1, 10_000))
        assertEquals(0, Totp.waitBeforeUse(sha1, 26_999))
        assertEquals(1_050, Totp.waitBeforeUse(sha1, 29_000))
        assertTrue(Totp.waitBeforeUse(sha1, 29_990) in 1..100)
    }

    @Test
    fun `a code page fills the code and ends the sign-in`() {
        val r = FillValues.of("u", "p", sha1, emptyList<String>(), emptyList(), listOf("otp"), 59_000)
        assertEquals(mapOf("otp" to Totp.code(sha1, 59_000)), r.values)
        assertTrue(r.lastStep)
    }

    @Test
    fun `a row of boxes gets one digit each`() {
        val boxes = List(6) { "b$it" }
        val r = FillValues.of("u", "p", sha1, emptyList(), emptyList(), boxes, 59_000)
        assertEquals(Totp.code(sha1, 59_000).map { it.toString() }, boxes.map { r.values[it] })
    }

    @Test
    fun `a code page without a secret fills nothing`() {
        val r = FillValues.of("u", "p", null, emptyList<String>(), emptyList(), listOf("otp"), 0)
        assertTrue(r.values.isEmpty())
    }

    @Test
    fun `a password page ends the sign-in only when there is no code to come`() {
        assertTrue(FillValues.of("u", "p", null, listOf("a"), listOf("b"), emptyList(), 0).lastStep)
        assertFalse(FillValues.of("u", "p", sha1, listOf("a"), listOf("b"), emptyList(), 0).lastStep)
        assertFalse(FillValues.of("u", "p", null, listOf("a"), emptyList(), emptyList(), 0).lastStep)
    }
}
