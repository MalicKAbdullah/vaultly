package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.vault.CardRecord
import dev.abdullah.vaultkey.vault.IdentityRecord

/** The values for a card or address form: each named field gets its part of the record. */
object SectionValues {

    fun <K> card(card: CardRecord, fields: Map<CardField, K>): Map<K, String> {
        val month = card.expMonth.padStart(2, '0')
        val year4 = if (card.expYear.length == 2) "20${card.expYear}" else card.expYear
        val year2 = year4.takeLast(2)
        val out = LinkedHashMap<K, String>()
        fields.forEach { (field, key) ->
            val value = when (field) {
                CardField.NUMBER -> card.number
                CardField.HOLDER -> card.holder
                CardField.EXP_MONTH -> month
                CardField.EXP_YEAR -> year4
                CardField.EXP_YEAR_2 -> year2
                CardField.EXP_COMBINED -> if (card.expMonth.isEmpty()) "" else "$month/$year2"
                CardField.CVC -> card.cvc
            }
            if (value.isNotEmpty()) out[key] = value
        }
        return out
    }

    fun <K> address(identity: IdentityRecord, fields: Map<AddressField, K>): Map<K, String> {
        val name = identity.fullName.trim()
        val split = name.lastIndexOf(' ')
        val given = if (split < 0) name else name.substring(0, split)
        val family = if (split < 0) "" else name.substring(split + 1)
        val out = LinkedHashMap<K, String>()
        fields.forEach { (field, key) ->
            val value = when (field) {
                AddressField.FULL_NAME -> name
                AddressField.GIVEN_NAME -> given
                AddressField.FAMILY_NAME -> family
                AddressField.EMAIL -> identity.email
                AddressField.PHONE -> identity.phone
                AddressField.STREET -> identity.address1
                AddressField.STREET2 -> identity.address2
                AddressField.CITY -> identity.city
                AddressField.REGION -> identity.region
                AddressField.POSTAL -> identity.postalCode
                AddressField.COUNTRY -> identity.country
            }
            if (value.isNotEmpty()) out[key] = value
        }
        return out
    }
}
