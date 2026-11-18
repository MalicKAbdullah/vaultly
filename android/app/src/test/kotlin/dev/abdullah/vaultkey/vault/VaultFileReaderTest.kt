package dev.abdullah.vaultkey.vault

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.AEADBadTagException

class VaultFileReaderTest {

    private fun resource(name: String) = javaClass.getResource("/$name")!!

    private val encrypted = resource("vault.enc").readBytes()
    private val key = resource("vault.key.hex").readText().trim()
        .chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @Test
    fun `the vault Dart encrypted opens with its key`() {
        val records = VaultFileReader.decrypt(encrypted, key)
        assertEquals(listOf("a1", "a2", "a3", "a4", "a5"), records.map { it.id })

        val github = records.first()
        assertEquals("GitHub", github.title)
        assertEquals("ali@example.com", github.username)
        assertEquals("gh-Pässwörd \"quoted\" \\ ✓", github.password)
        assertEquals("https://github.com/login", github.url)
        assertEquals("login", github.category)
        assertEquals(TotpParams("JBSWY3DPEHPK3PXP", "SHA256", 8, 30), github.totp)
        assertFalse(github.hasPasskey)

        assertTrue(records.last().hasPasskey)
    }

    @Test
    fun `the plaintext JSON parses to the same records`() {
        assertEquals(
            VaultFileReader.decrypt(encrypted, key),
            VaultFileReader.parse(resource("vault.json").readText()),
        )
    }

    @Test(expected = AEADBadTagException::class)
    fun `a wrong key throws`() {
        VaultFileReader.decrypt(encrypted, key.copyOf().also { it[0] = (it[0] + 1).toByte() })
    }

    @Test(expected = AEADBadTagException::class)
    fun `a flipped ciphertext byte throws`() {
        VaultFileReader.decrypt(encrypted.copyOf().also { it[60] = (it[60].toInt() xor 1).toByte() }, key)
    }

    @Test(expected = AEADBadTagException::class)
    fun `a flipped nonce byte throws`() {
        VaultFileReader.decrypt(encrypted.copyOf().also { it[40] = (it[40].toInt() xor 1).toByte() }, key)
    }
}
