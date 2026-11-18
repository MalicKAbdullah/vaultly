package dev.abdullah.vaultkey.vault

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EntryMatcherTest {

    private val vault = VaultFileReader.parse(javaClass.getResource("/vault.json")!!.readText())

    private fun record(id: String, url: String, title: String = id, passkey: Boolean = false) =
        VaultRecord(id, title, "user-$id", "pw-$id", url, "login", null, passkey)

    @Test
    fun `ranks like the Dart matcher on the shared vectors`() {
        val cases = JSONArray(javaClass.getResource("/matcher_vectors.json")!!.readText())
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            val domain = if (case.has("domain")) case.getString("domain") else null
            val pkg = if (case.has("package")) case.getString("package") else null
            val expected = case.getJSONArray("ranked").let { a -> List(a.length()) { a.getString(it) } }
            assertEquals("domain=$domain package=$pkg", expected, EntryMatcher.rank(vault, domain, pkg).map { it.id })
        }
    }

    @Test
    fun `one exact host match and nothing related fills without a list`() {
        assertEquals("a1", EntryMatcher.confirmed(vault, "github.com", null, null)?.id)
    }

    @Test
    fun `an exact match with a related-domain rival shows the list`() {
        // accounts.google.com is exact for a2, google.com is a parent for a3.
        assertNull(EntryMatcher.confirmed(vault, "accounts.google.com", null, null))
    }

    @Test
    fun `a subdomain-only match shows the list`() {
        val entries = listOf(record("x", "example.com"))
        assertNull(EntryMatcher.confirmed(entries, "login.example.com", null, null))
    }

    @Test
    fun `a title-only match shows the list`() {
        val entries = listOf(record("x", "", title = "GitHub backup"))
        assertNull(EntryMatcher.confirmed(entries, "github.com", null, null))
    }

    @Test
    fun `a remembered choice is confirmed for an app`() {
        val entries = listOf(record("x", "github.com"), record("y", "bank.example"))
        assertEquals("x", EntryMatcher.confirmed(entries, null, "com.github.android", "x")?.id)
    }

    @Test
    fun `a remembered choice with a rival on the same host shows the list`() {
        val entries = listOf(record("x", "github.com"), record("y", "github.com"))
        assertNull(EntryMatcher.confirmed(entries, "github.com", null, "x"))
    }

    @Test
    fun `a remembered choice that matches the host exactly counts once`() {
        val entries = listOf(record("x", "github.com"))
        assertEquals("x", EntryMatcher.confirmed(entries, "github.com", null, "x")?.id)
    }

    @Test
    fun `a remembered id that no longer exists confirms nothing`() {
        assertNull(EntryMatcher.confirmed(listOf(record("x", "bank.example")), null, "com.bank", "gone"))
    }

    @Test
    fun `an app's package never confirms an entry by itself`() {
        assertNull(EntryMatcher.confirmed(listOf(record("x", "github.com")), null, "com.github.android", null))
    }

    @Test
    fun `passkey-only entries are never filled`() {
        assertNull(EntryMatcher.confirmed(listOf(record("x", "webauthn.io", passkey = true)), "webauthn.io", null, null))
    }

    @Test
    fun `look-alike hosts are not related`() {
        assertEquals(0, EntryMatcher.score(record("x", "github.com"), "notgithub.com", null))
        assertEquals(EntryMatcher.RELATED_HOST, EntryMatcher.score(record("x", "google.com"), "accounts.google.com", null))
    }
}
