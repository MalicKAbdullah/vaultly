package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.vault.CardRecord
import dev.abdullah.vaultkey.vault.IdentityRecord
import org.junit.Assert.assertEquals
import org.junit.Test

class SectionValuesTest {
    private val card = CardRecord("Ada Lovelace", "4242424242424242", "7", "2030", "987")

    @Test
    fun `each card field gets its part, the combined expiry as MM slash YY`() {
        val fields = mapOf(
            CardField.NUMBER to "n", CardField.HOLDER to "h", CardField.EXP_COMBINED to "e", CardField.CVC to "c",
        )
        assertEquals(
            mapOf("n" to "4242424242424242", "h" to "Ada Lovelace", "e" to "07/30", "c" to "987"),
            SectionValues.card(card, fields),
        )
    }

    @Test
    fun `month and year fields take two and four digit forms`() {
        val fields = mapOf(CardField.EXP_MONTH to "m", CardField.EXP_YEAR to "y4", CardField.EXP_YEAR_2 to "y2")
        assertEquals(mapOf("m" to "07", "y4" to "2030", "y2" to "30"), SectionValues.card(card, fields))
        assertEquals("2030", SectionValues.card(card.copy(expYear = "30"), fields)["y4"])
    }

    private val identity = IdentityRecord("Ada King Lovelace", "ada@x.org", "", "1 Main St", "", "London", "", "N1", "UK")

    @Test
    fun `an address splits the name and skips empty parts`() {
        val fields = mapOf(
            AddressField.GIVEN_NAME to 1, AddressField.FAMILY_NAME to 2, AddressField.PHONE to 3, AddressField.STREET to 4,
            AddressField.STREET2 to 5, AddressField.POSTAL to 6,
        )
        assertEquals(mapOf(1 to "Ada King", 2 to "Lovelace", 4 to "1 Main St", 6 to "N1"), SectionValues.address(identity, fields))
    }

    @Test
    fun `a single word name is only a given name`() {
        val fields = mapOf(AddressField.GIVEN_NAME to 1, AddressField.FAMILY_NAME to 2)
        assertEquals(mapOf(1 to "Plato"), SectionValues.address(identity.copy(fullName = "Plato"), fields))
    }
}
