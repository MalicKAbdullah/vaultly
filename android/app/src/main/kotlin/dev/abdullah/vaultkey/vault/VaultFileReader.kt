package dev.abdullah.vaultkey.vault

import android.content.Context
import org.json.JSONObject
import java.io.File
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** A TOTP secret as an entry stores it. */
data class TotpParams(
    val secret: String,
    val algorithm: String,
    val digits: Int,
    val period: Int,
)

/** A saved payment card as an entry stores it. */
data class CardRecord(
    val holder: String,
    val number: String,
    val expMonth: String,
    val expYear: String,
    val cvc: String,
)

/** A saved identity (name, contact, address) as an entry stores it. */
data class IdentityRecord(
    val fullName: String,
    val email: String,
    val phone: String,
    val address1: String,
    val address2: String,
    val city: String,
    val region: String,
    val postalCode: String,
    val country: String,
)

/**
 * Read-only view of one vault entry: the fields filling needs. The vault
 * JSON is written only by Dart (`VaultEntry.toJson`); the contract fixtures
 * in `test/fixtures/contract/` pin the two sides together.
 */
data class VaultRecord(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val url: String,
    val category: String,
    val totp: TotpParams?,
    val hasPasskey: Boolean,
    val card: CardRecord? = null,
    val identity: IdentityRecord? = null,
)

/**
 * Reads the vault file Dart writes: `salt(32) | nonce(12) | AES-256-GCM
 * ciphertext+tag(16)`, the plaintext `{"version":n,"entries":[…]}`.
 */
object VaultFileReader {
    private const val FILE_NAME = "vaultkey_vault.enc"
    private const val SALT_LENGTH = 32
    private const val NONCE_LENGTH = 12
    private const val TAG_BITS = 128
    /** Format 2 added card and identity details; the fields read here are the same in 1 and 2. */
    private const val NEWEST_FORMAT = 2

    /** Where Flutter's `getApplicationDocumentsDirectory()` keeps the vault on Android. */
    fun file(context: Context): File = File(context.getDir("flutter", Context.MODE_PRIVATE), FILE_NAME)

    /** The encrypted file, or null when no vault exists. Not secret: read it while the prompt is up. */
    fun readEncrypted(file: File): ByteArray? = if (file.exists()) file.readBytes() else null

    /**
     * Decrypts and parses [encrypted] with [key]. Throws
     * `javax.crypto.AEADBadTagException` for a wrong key or a modified file.
     * The decrypted bytes are zeroed before returning; [key] is the
     * caller's to zero.
     */
    fun decrypt(encrypted: ByteArray, key: ByteArray): List<VaultRecord> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(TAG_BITS, encrypted, SALT_LENGTH, NONCE_LENGTH),
        )
        val offset = SALT_LENGTH + NONCE_LENGTH
        val plaintext = cipher.doFinal(encrypted, offset, encrypted.size - offset)
        try {
            return parse(String(plaintext, Charsets.UTF_8))
        } finally {
            plaintext.fill(0)
        }
    }

    fun parse(json: String): List<VaultRecord> {
        val doc = JSONObject(json)
        val version = doc.getInt("version")
        check(version in 1..NEWEST_FORMAT) { "Unknown vault format $version" }
        val entries = doc.getJSONArray("entries")
        return List(entries.length()) { i ->
            val e = entries.getJSONObject(i)
            VaultRecord(
                id = e.getString("id"),
                title = e.getString("title"),
                username = e.getString("username"),
                password = e.getString("password"),
                url = e.getString("url"),
                category = e.getString("category"),
                totp = e.optJSONObject("totp")?.let { t ->
                    TotpParams(
                        secret = t.getString("secret"),
                        algorithm = t.getString("algorithm"),
                        digits = t.getInt("digits"),
                        period = t.getInt("period"),
                    )
                },
                hasPasskey = e.has("passkey"),
                card = e.optJSONObject("card")?.let { c ->
                    CardRecord(
                        c.getString("holder"), c.getString("number"), c.getString("expMonth"),
                        c.getString("expYear"), c.getString("cvc"),
                    )
                },
                identity = e.optJSONObject("identity")?.let { i ->
                    IdentityRecord(
                        i.getString("fullName"), i.getString("email"), i.getString("phone"),
                        i.getString("address1"), i.getString("address2"), i.getString("city"),
                        i.getString("region"), i.getString("postalCode"), i.getString("country"),
                    )
                },
            )
        }
    }
}
