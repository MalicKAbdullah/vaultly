package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.vault.VaultRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FillPlanTest {
    private fun record(id: String, url: String, title: String = id, user: String = "u", pw: String = "p") =
        VaultRecord(id, title, user, pw, url, "login", null, false)

    private val web = RequestTarget.Web("github.com", "com.android.chrome")
    private val app = RequestTarget.App("com.example.shop", "AA", null)

    @Test
    fun `one exact host fills without a list`() {
        val plan = FillPlan.of(listOf(record("a", "github.com"), record("b", "gitlab.com")), web, null)
        assertEquals("a", (plan as FillPlan.Fill).record.id)
    }

    @Test
    fun `two accounts on one host show the list`() {
        val plan = FillPlan.of(listOf(record("a", "github.com"), record("b", "github.com")), web, null)
        assertEquals(listOf("a", "b"), (plan as FillPlan.Choose).ranked.map { it.id })
    }

    @Test
    fun `a native app fills only from a remembered choice`() {
        val entries = listOf(record("a", "shop.example.com", title = "Shop"))
        assertTrue(FillPlan.of(entries, app, null) is FillPlan.Choose)
        assertEquals("a", (FillPlan.of(entries, app, "a") as FillPlan.Fill).record.id)
    }

    @Test
    fun `an entry with nothing to fill is never offered`() {
        val plan = FillPlan.of(listOf(record("a", "github.com", user = "", pw = "")), web, null)
        assertTrue((plan as FillPlan.Choose).ranked.isEmpty())
    }

    @Test
    fun `a pick with no signal for the target is not a match`() {
        assertFalse(FillPlan.matches(record("z", "other.org"), web))
        assertTrue(FillPlan.matches(record("a", "github.com"), web))
    }

    @Test
    fun `remembered keys differ by host and by signing certificate`() {
        val a = RememberedChoices.hash(app)
        assertNotEquals(a, RememberedChoices.hash(RequestTarget.App("com.example.shop", "BB", null)))
        assertNotEquals(a, RememberedChoices.hash(web))
        assertEquals(64, a.length)
    }
}
