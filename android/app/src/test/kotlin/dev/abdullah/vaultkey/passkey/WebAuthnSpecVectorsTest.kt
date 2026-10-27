package dev.abdullah.vaultkey.passkey

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigInteger
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec

/**
 * W3C Web Authentication Level 3, §16.2 "ES256 Credential with No
 * Attestation" (https://www.w3.org/TR/webauthn-3/#sctn-test-vectors-none-es256).
 * rpId is "example.org" and origin "https://example.org" for all vectors.
 */
class WebAuthnSpecVectorsTest {

    private val rpId = "example.org"
    private val origin = "https://example.org"

    private val privateScalar = hex("6e68e7a58484a3264f66b77f5d6dc5bc36a47085b615c9727ab334e8c369c2ee")
    private val aaguid = hex("8446ccb9ab1db374750b2367ff6f3a1f")
    private val credentialId = hex("f91f391db4c9b2fde0ea70189cba3fb63f579ba6122b33ad94ff3ec330084be4")

    // The COSE x / y coordinates carried in the vector's attestationObject.
    private val publicX = hex("afefa16f97ca9b2d23eb86ccb64098d20db90856062eb249c33a9b672f26df61")
    private val publicY = hex("930a56b87a2fca66334b03458abf879717c12cc68ed73290af2e2664796b9220")

    private val registrationAttestationObject = hex(
        "a363666d74646e6f6e656761747453746d74a068617574684461746158a4bfabc37432958b063360d3" +
            "ad6461c9c4735ae7f8edd46592a5e0f01452b2e4b559000000008446ccb9ab1db374750b2367ff6f" +
            "3a1f0020f91f391db4c9b2fde0ea70189cba3fb63f579ba6122b33ad94ff3ec330084be4a5010203" +
            "262001215820afefa16f97ca9b2d23eb86ccb64098d20db90856062eb249c33a9b672f26df612258" +
            "20930a56b87a2fca66334b03458abf879717c12cc68ed73290af2e2664796b9220",
    )

    private val authenticationChallenge = hex("39c0e7521417ba54d43e8dc95174f423dee9bf3cd804ff6d65c857c9abf4d408")
    private val authenticationAuthData = hex("bfabc37432958b063360d3ad6461c9c4735ae7f8edd46592a5e0f01452b2e4b51900000000")
    private val authenticationClientData = hex(
        "7b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a224f63446e55685158756c5455506f334a5558543049393770767a7a59425039745a63685879617630314167222c226f726967696e223a2268747470733a2f2f6578616d706c652e6f7267222c2263726f73734f726967696e223a66616c73657d",
    )
    private val authenticationSignature = hex(
        "3046022100f50a4e2e4409249c4a853ba361282f09841df4dd4547a13a87780218deffcd380221008480ac0f0b93538174f575bf11a1dd5d78c6e486013f937295ea13653e331e87",
    )

    @Test
    fun `registration attestationObject matches the spec byte for byte`() {
        // Vector flags 0x59 = UP | BE | BS | AT (no UV).
        val flags = WebAuthn.FLAG_UP or WebAuthn.FLAG_BE or WebAuthn.FLAG_BS or WebAuthn.FLAG_AT
        val authData = WebAuthn.authenticatorData(
            rpId = rpId,
            flags = flags,
            signCount = 0,
            attestedCredentialData = WebAuthn.attestedCredentialData(aaguid, credentialId, publicKey()),
        )
        assertArrayEquals(registrationAttestationObject, WebAuthn.noneAttestationObject(authData))
    }

    @Test
    fun `authentication authenticatorData matches the spec`() {
        // Vector flags 0x19 = UP | BE | BS.
        val flags = WebAuthn.FLAG_UP or WebAuthn.FLAG_BE or WebAuthn.FLAG_BS
        assertArrayEquals(authenticationAuthData, WebAuthn.authenticatorData(rpId, flags, signCount = 0))
    }

    @Test
    fun `authentication clientDataJSON matches the spec`() {
        val json = WebAuthn.clientDataJson("webauthn.get", authenticationChallenge, origin)
        assertArrayEquals(authenticationClientData, json.toByteArray(Charsets.UTF_8))
    }

    @Test
    fun `the spec signature verifies over authData and the clientDataJSON hash`() {
        assertTrue(
            verify(
                publicKey(),
                authenticationAuthData,
                WebAuthn.sha256(authenticationClientData),
                authenticationSignature,
            ),
        )
    }

    @Test
    fun `a signature made with the spec private key verifies with its public key`() {
        val clientDataHash = WebAuthn.sha256(authenticationClientData)
        val signature = WebAuthn.sign(privateKey(), authenticationAuthData, clientDataHash)
        assertEquals(0x30, signature[0].toInt() and 0xff) // ASN.1 DER SEQUENCE
        assertTrue(verify(publicKey(), authenticationAuthData, clientDataHash, signature))
    }

    private fun publicKey(): ECPublicKey {
        val params = (WebAuthn.generateKeyPair().public as ECPublicKey).params
        val point = ECPoint(BigInteger(1, publicX), BigInteger(1, publicY))
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(point, params)) as ECPublicKey
    }

    private fun privateKey(): PrivateKey {
        val params = (WebAuthn.generateKeyPair().public as ECPublicKey).params
        return KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, privateScalar), params))
    }
}

internal fun verify(
    publicKey: java.security.PublicKey,
    authData: ByteArray,
    clientDataHash: ByteArray,
    signature: ByteArray,
): Boolean =
    Signature.getInstance("SHA256withECDSA").run {
        initVerify(publicKey)
        update(authData)
        update(clientDataHash)
        verify(signature)
    }

internal fun hex(value: String): ByteArray =
    ByteArray(value.length / 2) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
