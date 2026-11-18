package dev.abdullah.vaultkey.vault

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** RFC 6238 time-based codes, held to the same vectors as the Dart generator. */
object Totp {
    /** A code this close to expiry could lapse before the site checks it. */
    const val SAFE_MARGIN_MS = 3_000L

    fun code(params: TotpParams, unixMillis: Long): String {
        val counter = unixMillis / 1000 / params.period
        val key = base32(params.secret)
        val hash = try {
            val algorithm = when (params.algorithm.uppercase()) {
                "SHA256" -> "HmacSHA256"
                "SHA512" -> "HmacSHA512"
                else -> "HmacSHA1"
            }
            Mac.getInstance(algorithm).run {
                init(SecretKeySpec(key, algorithm))
                doFinal(ByteBuffer.allocate(8).putLong(counter).array())
            }
        } finally {
            key.fill(0)
        }
        val offset = hash.last().toInt() and 0x0F
        val binary = ((hash[offset].toInt() and 0x7F) shl 24) or
            ((hash[offset + 1].toInt() and 0xFF) shl 16) or
            ((hash[offset + 2].toInt() and 0xFF) shl 8) or
            (hash[offset + 3].toInt() and 0xFF)
        var modulus = 1L
        repeat(params.digits) { modulus *= 10 }
        return (binary % modulus).toString().padStart(params.digits, '0')
    }

    /** Milliseconds to wait so the code sent is not about to expire; 0 when it is safe now. */
    fun waitBeforeUse(params: TotpParams, unixMillis: Long): Long {
        val periodMs = params.period * 1000L
        val remaining = periodMs - unixMillis % periodMs
        return if (remaining < SAFE_MARGIN_MS) remaining + 50 else 0
    }

    /** RFC 4648 base32, tolerant of case, spaces, dashes and missing padding like the Dart decoder. */
    internal fun base32(input: String): ByteArray {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        val cleaned = input.uppercase().filter { !it.isWhitespace() && it != '-' && it != '=' }
        require(cleaned.isNotEmpty()) { "The secret is empty." }
        val out = java.io.ByteArrayOutputStream()
        var buffer = 0
        var bits = 0
        for (c in cleaned) {
            val v = alphabet.indexOf(c)
            require(v >= 0) { "Not a base32 secret." }
            buffer = (buffer shl 5) or v
            bits += 5
            if (bits >= 8) {
                bits -= 8
                out.write((buffer shr bits) and 0xFF)
            }
        }
        return out.toByteArray()
    }
}
