package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.vault.Totp
import dev.abdullah.vaultkey.vault.TotpParams

/** What to write into a page's fields, and whether that finishes the sign-in. */
class FillValues<K>(val values: Map<K, String>, val lastStep: Boolean) {
    companion object {
        /**
         * [codeFields] holds one field for a single code input, or one per
         * digit for a row of single-character boxes. A page asking for a
         * code needs [totp]; without one nothing is filled for it.
         */
        fun <K> of(
            username: String,
            password: String,
            totp: TotpParams?,
            usernameFields: List<K>,
            passwordFields: List<K>,
            codeFields: List<K>,
            nowMillis: Long,
        ): FillValues<K> {
            val out = LinkedHashMap<K, String>()
            usernameFields.forEach { out[it] = username }
            passwordFields.forEach { out[it] = password }
            var lastStep = passwordFields.isNotEmpty() && totp == null
            if (codeFields.isNotEmpty() && totp != null) {
                val code = Totp.code(totp, nowMillis)
                if (codeFields.size == 1) {
                    out[codeFields.single()] = code
                } else {
                    // A row of one-digit boxes: one digit each, extra boxes stay empty.
                    codeFields.zip(code.toList()).forEach { (field, digit) -> out[field] = digit.toString() }
                }
                lastStep = true
            }
            return FillValues(out, lastStep)
        }
    }
}
