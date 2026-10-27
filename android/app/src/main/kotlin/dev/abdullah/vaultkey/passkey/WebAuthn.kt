package dev.abdullah.vaultkey.passkey

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import java.util.UUID

/** Unpadded base64url, the encoding WebAuthn JSON uses for every binary field. */
object Base64Url {
    fun encode(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    /** Accepts padded and unpadded input. */
    fun decode(value: String): ByteArray = Base64.getUrlDecoder().decode(value)
}

/**
 * WebAuthn authenticator encodings (W3C Web Authentication Level 3, §6) for
 * an ES256 (ECDSA P-256 / SHA-256) authenticator with "none" attestation.
 */
object WebAuthn {
    /** Vaultly's authenticator model id, reported in attested credential data. */
    val AAGUID: ByteArray = uuidBytes(UUID.fromString("66e9f2be-235c-4a96-ad1b-e1666e0ba1fc"))

    const val FLAG_UP = 0x01
    const val FLAG_UV = 0x04
    const val FLAG_BE = 0x08
    const val FLAG_BS = 0x10
    const val FLAG_AT = 0x40

    /**
     * Flags on every Vaultly ceremony. UV: the vault was unlocked (biometric
     * or master password) for this request. BE and BS: the private key lives
     * in the vault file, which travels in encrypted backups and to other
     * devices, so the credential is a multi-device credential.
     */
    const val VAULTLY_FLAGS = FLAG_UP or FLAG_UV or FLAG_BE or FLAG_BS

    const val COSE_ALG_ES256 = -7L
    private const val COSE_KTY_EC2 = 2L
    private const val COSE_CRV_P256 = 1L
    private const val P256_COORDINATE_BYTES = 32

    fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

    fun generateKeyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()

    fun privateKeyFromPkcs8(pkcs8: ByteArray): PrivateKey =
        KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(pkcs8))

    /**
     * Authenticator data (§6.1): rpIdHash ‖ flags ‖ signCount (big-endian
     * u32) ‖ attestedCredentialData. The AT flag must be set exactly when
     * attested credential data is present.
     */
    fun authenticatorData(
        rpId: String,
        flags: Int,
        signCount: Long,
        attestedCredentialData: ByteArray? = null,
    ): ByteArray {
        require((flags and FLAG_AT != 0) == (attestedCredentialData != null)) {
            "AT flag must match the presence of attested credential data"
        }
        require(signCount in 0..0xffffffffL) { "signCount must fit in 32 bits" }
        val acd = attestedCredentialData ?: ByteArray(0)
        return ByteBuffer.allocate(32 + 1 + 4 + acd.size)
            .put(sha256(rpId.toByteArray(Charsets.UTF_8)))
            .put(flags.toByte())
            .putInt(signCount.toInt())
            .put(acd)
            .array()
    }

    /** Attested credential data (§6.5.2): aaguid ‖ L (u16) ‖ credentialId ‖ COSE key. */
    fun attestedCredentialData(
        aaguid: ByteArray,
        credentialId: ByteArray,
        publicKey: ECPublicKey,
    ): ByteArray {
        require(aaguid.size == 16) { "AAGUID is 16 bytes" }
        require(credentialId.size <= 1023) { "credential id is at most 1023 bytes" }
        val cose = coseKey(publicKey)
        return ByteBuffer.allocate(16 + 2 + credentialId.size + cose.size)
            .put(aaguid)
            .putShort(credentialId.size.toShort())
            .put(credentialId)
            .put(cose)
            .array()
    }

    /** COSE_Key for an EC2 P-256 public key (RFC 9053), CTAP2 canonical order. */
    fun coseKey(publicKey: ECPublicKey): ByteArray =
        CborWriter()
            .map(5)
            .int(1).int(COSE_KTY_EC2)
            .int(3).int(COSE_ALG_ES256)
            .int(-1).int(COSE_CRV_P256)
            .int(-2).bytes(fixedLength(publicKey.w.affineX))
            .int(-3).bytes(fixedLength(publicKey.w.affineY))
            .toByteArray()

    /** Attestation object with the "none" format (§8.7), CTAP2 canonical order. */
    fun noneAttestationObject(authenticatorData: ByteArray): ByteArray =
        CborWriter()
            .map(3)
            .text("fmt").text("none")
            .text("attStmt").map(0)
            .text("authData").bytes(authenticatorData)
            .toByteArray()

    /**
     * Assertion signature (§6.3.3 step 11): ECDSA P-256 with SHA-256 over
     * authenticatorData ‖ clientDataHash, ASN.1 DER encoded as ES256 requires.
     */
    fun sign(privateKey: PrivateKey, authenticatorData: ByteArray, clientDataHash: ByteArray): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(authenticatorData)
            update(clientDataHash)
            sign()
        }

    /**
     * clientDataJSON (§5.8.1) in the member order of the spec's serialization
     * (§5.8.1.1): type, challenge, origin, crossOrigin. Native-app callers
     * additionally carry `androidPackageName`, as Google's provider sample
     * does.
     */
    fun clientDataJson(
        type: String,
        challenge: ByteArray,
        origin: String,
        androidPackageName: String? = null,
    ): String = buildString {
        append("{\"type\":").append(jsonString(type))
        append(",\"challenge\":").append(jsonString(Base64Url.encode(challenge)))
        append(",\"origin\":").append(jsonString(origin))
        append(",\"crossOrigin\":false")
        if (androidPackageName != null) {
            append(",\"androidPackageName\":").append(jsonString(androidPackageName))
        }
        append('}')
    }

    /** JSON string literal with the escaping of §5.8.1.1 (CCDToString). */
    internal fun jsonString(value: String): String = buildString {
        append('"')
        for (ch in value) {
            when {
                ch == '"' -> append("\\\"")
                ch == '\\' -> append("\\\\")
                ch < ' ' -> append(String.format("\\u%04x", ch.code))
                else -> append(ch)
            }
        }
        append('"')
    }

    private fun fixedLength(value: BigInteger): ByteArray {
        val raw = value.toByteArray()
        return when {
            raw.size == P256_COORDINATE_BYTES -> raw
            raw.size > P256_COORDINATE_BYTES -> raw.copyOfRange(raw.size - P256_COORDINATE_BYTES, raw.size)
            else -> ByteArray(P256_COORDINATE_BYTES - raw.size) + raw
        }
    }

    private fun uuidBytes(uuid: UUID): ByteArray =
        ByteBuffer.allocate(16)
            .putLong(uuid.mostSignificantBits)
            .putLong(uuid.leastSignificantBits)
            .array()
}
