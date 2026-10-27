package dev.abdullah.vaultkey.passkey

import java.io.ByteArrayOutputStream

/**
 * The subset of CBOR (RFC 8949) that WebAuthn registration needs: integers,
 * byte strings, text strings and definite-length maps.
 *
 * Map entries are written in the order the caller emits them. Callers emit
 * them in CTAP2 canonical order (shorter encoded key first, then bytewise),
 * which keeps the output byte-for-byte deterministic.
 */
internal class CborWriter {
    private val out = ByteArrayOutputStream()

    fun int(value: Long): CborWriter = apply {
        if (value >= 0) head(MAJOR_UNSIGNED, value) else head(MAJOR_NEGATIVE, -1 - value)
    }

    fun bytes(value: ByteArray): CborWriter = apply {
        head(MAJOR_BYTES, value.size.toLong())
        out.write(value)
    }

    fun text(value: String): CborWriter = apply {
        val encoded = value.toByteArray(Charsets.UTF_8)
        head(MAJOR_TEXT, encoded.size.toLong())
        out.write(encoded)
    }

    /** Starts a map of [size] entries; the caller then writes key, value pairs. */
    fun map(size: Int): CborWriter = apply { head(MAJOR_MAP, size.toLong()) }

    fun toByteArray(): ByteArray = out.toByteArray()

    private fun head(major: Int, value: Long) {
        val type = major shl 5
        when {
            value < 24 -> out.write(type or value.toInt())
            value < 0x100 -> {
                out.write(type or 24)
                out.write(value.toInt())
            }
            value < 0x10000 -> {
                out.write(type or 25)
                writeBigEndian(value, 2)
            }
            value < 0x100000000L -> {
                out.write(type or 26)
                writeBigEndian(value, 4)
            }
            else -> {
                out.write(type or 27)
                writeBigEndian(value, 8)
            }
        }
    }

    private fun writeBigEndian(value: Long, bytes: Int) {
        for (i in bytes - 1 downTo 0) out.write(((value shr (8 * i)) and 0xff).toInt())
    }

    private companion object {
        const val MAJOR_UNSIGNED = 0
        const val MAJOR_NEGATIVE = 1
        const val MAJOR_BYTES = 2
        const val MAJOR_TEXT = 3
        const val MAJOR_MAP = 5
    }
}
