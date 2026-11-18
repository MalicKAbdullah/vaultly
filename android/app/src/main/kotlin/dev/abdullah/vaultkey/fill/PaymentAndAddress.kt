package dev.abdullah.vaultkey.fill

/** Which part of the vault a form asks for. A form is exactly one of these. */
enum class FormKind { LOGIN, CARD, ADDRESS }

enum class CardField { NUMBER, HOLDER, EXP_MONTH, EXP_YEAR, EXP_YEAR_2, EXP_COMBINED, CVC }

enum class AddressField {
    FULL_NAME, GIVEN_NAME, FAMILY_NAME, EMAIL, PHONE, STREET, STREET2, CITY, REGION, POSTAL, COUNTRY,
}

/**
 * Card and address fields are named, never guessed: a field belongs only
 * when the page or app says so through autofill hints, the HTML
 * `autocomplete` value, or the field type Chrome derived from it. Hints are
 * compared with case and punctuation removed (`cc-number`, `CREDIT_CARD_NUMBER`
 * and `creditCardNumber` are one name).
 */
object PaymentAndAddress {

    fun tokens(autofillHints: List<String>, attributes: Map<String, String>): Set<String> = buildSet {
        autofillHints.forEach { add(normalize(it)) }
        attributes["autocomplete"]?.split(' ')?.forEach { add(normalize(it)) }
        attributes["ua-autofill-hints"]?.let { add(normalize(it)) }
        attributes["computed-autofill-hints"]?.let { add(normalize(it)) }
        remove("")
    }

    private fun normalize(s: String) = s.lowercase().filter { it.isLetterOrDigit() }

    private val card = mapOf(
        CardField.NUMBER to setOf("ccnumber", "creditcardnumber"),
        CardField.HOLDER to setOf("ccname", "creditcardname", "creditcardnamefull"),
        CardField.CVC to setOf("cccsc", "creditcardsecuritycode", "creditcardverificationcode"),
        CardField.EXP_MONTH to setOf("ccexpmonth", "creditcardexpirationmonth", "creditcardexpmonth"),
        CardField.EXP_YEAR_2 to setOf("creditcardexp2digityear"),
        CardField.EXP_YEAR to setOf("ccexpyear", "creditcardexpirationyear", "creditcardexp4digityear"),
        CardField.EXP_COMBINED to setOf(
            "ccexp", "creditcardexpirationdate", "creditcardexpdate2digityear", "creditcardexpdate4digityear",
        ),
    )

    private val address = mapOf(
        AddressField.FULL_NAME to setOf("name", "fullname", "namefull"),
        AddressField.GIVEN_NAME to setOf("givenname", "namefirst", "personname"),
        AddressField.FAMILY_NAME to setOf("familyname", "namelast", "personfamilyname"),
        AddressField.EMAIL to setOf("email", "emailaddress"),
        AddressField.PHONE to setOf("tel", "phone", "phonenumber", "phonenational", "telnational"),
        AddressField.STREET to setOf("streetaddress", "addressline1", "postaladdress", "addresshomeline1", "addresshomestreetaddress"),
        AddressField.STREET2 to setOf("addressline2", "addresshomeline2"),
        AddressField.CITY to setOf("addresslevel2", "addresshomecity", "postaladdresslocality"),
        AddressField.REGION to setOf("addresslevel1", "addresshomestate", "postaladdressregion"),
        AddressField.POSTAL to setOf("postalcode", "addresshomezip", "postalcodeaddress"),
        AddressField.COUNTRY to setOf("country", "countryname", "addresshomecountry", "postaladdresscountry"),
    )

    fun cardField(tokens: Set<String>): CardField? =
        card.entries.firstOrNull { (_, names) -> tokens.any { it in names } }?.key

    fun addressField(tokens: Set<String>): AddressField? =
        address.entries.firstOrNull { (_, names) -> tokens.any { it in names } }?.key
}
