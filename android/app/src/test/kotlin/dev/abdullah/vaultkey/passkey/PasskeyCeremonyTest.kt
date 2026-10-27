package dev.abdullah.vaultkey.passkey

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec

class PasskeyCeremonyTest {

    private val challenge = ByteArray(32) { it.toByte() }
    private val userHandle = "user-42".toByteArray()

    private val creationJson = """
        {
          "challenge": "${Base64Url.encode(challenge)}",
          "rp": {"id": "webauthn.io", "name": "WebAuthn.io"},
          "user": {"id": "${Base64Url.encode(userHandle)}", "name": "alice", "displayName": "Alice"},
          "pubKeyCredParams": [{"type": "public-key", "alg": -8}, {"type": "public-key", "alg": -7}],
          "excludeCredentials": [{"type": "public-key", "id": "AQID"}]
        }
    """.trimIndent()

    private val web = VerifiedCaller(origin = "https://webauthn.io", androidPackageName = null, clientDataHash = null)

    @Test
    fun `registration produces a none attestation over correct authenticator data`() {
        val registration = PasskeyCeremony.register(PasskeyRequests.parseCreation(creationJson), "webauthn.io", web)
        val json = JSONObject(registration.responseJson)
        val response = json.getJSONObject("response")

        assertEquals(Base64Url.encode(registration.credentialId), json.getString("id"))
        assertEquals(json.getString("id"), json.getString("rawId"))
        assertEquals("public-key", json.getString("type"))
        assertEquals(-7, response.getInt("publicKeyAlgorithm"))
        assertArrayEquals(registration.publicKey, Base64Url.decode(response.getString("publicKey")))

        val authData = Base64Url.decode(response.getString("authenticatorData"))
        val attestation = Base64Url.decode(response.getString("attestationObject"))
        // {"fmt": "none", "attStmt": {}, "authData": bytes(1-byte length)}
        val prefix = hex("a363666d74646e6f6e656761747453746d74a068617574684461746158")
        assertArrayEquals(prefix, attestation.copyOfRange(0, prefix.size))
        assertEquals(authData.size, attestation[prefix.size].toInt() and 0xff)
        assertArrayEquals(authData, attestation.copyOfRange(prefix.size + 1, attestation.size))

        assertArrayEquals(WebAuthn.sha256("webauthn.io".toByteArray()), authData.copyOfRange(0, 32))
        val flags = authData[32].toInt() and 0xff
        assertEquals(
            WebAuthn.FLAG_UP or WebAuthn.FLAG_UV or WebAuthn.FLAG_BE or WebAuthn.FLAG_BS or WebAuthn.FLAG_AT,
            flags,
        )
        assertEquals(0, ByteBuffer.wrap(authData, 33, 4).int)
        assertArrayEquals(WebAuthn.AAGUID, authData.copyOfRange(37, 53))
        val idLength = ByteBuffer.wrap(authData, 53, 2).short.toInt()
        assertArrayEquals(registration.credentialId, authData.copyOfRange(55, 55 + idLength))

        // The COSE key's coordinates are the stored public key's.
        val publicKey = spki(registration.publicKey)
        val cose = authData.copyOfRange(55 + idLength, authData.size)
        assertArrayEquals(WebAuthn.coseKey(publicKey), cose)
        assertEquals(BigInteger(1, cose.copyOfRange(10, 42)), publicKey.w.affineX)
        assertEquals(BigInteger(1, cose.copyOfRange(45, 77)), publicKey.w.affineY)

        val clientData = JSONObject(String(Base64Url.decode(response.getString("clientDataJSON"))))
        assertEquals("webauthn.create", clientData.getString("type"))
        assertEquals(Base64Url.encode(challenge), clientData.getString("challenge"))
        assertEquals("https://webauthn.io", clientData.getString("origin"))
        assertFalse(clientData.getBoolean("crossOrigin"))
        assertFalse(clientData.has("androidPackageName"))
    }

    @Test
    fun `an assertion signs authData and the clientDataJSON hash with the stored key`() {
        val registration = PasskeyCeremony.register(PasskeyRequests.parseCreation(creationJson), "webauthn.io", web)
        val request = PasskeyRequests.parseAssertion(
            """{"challenge": "${Base64Url.encode(challenge)}", "rpId": "webauthn.io",
               "allowCredentials": [{"type": "public-key", "id": "${Base64Url.encode(registration.credentialId)}"}]}""",
        )
        val json = JSONObject(
            PasskeyCeremony.assert(
                options = request,
                rpId = "webauthn.io",
                caller = web,
                credentialId = registration.credentialId,
                userHandle = userHandle,
                privateKey = WebAuthn.privateKeyFromPkcs8(registration.privateKey),
            ),
        )
        val response = json.getJSONObject("response")
        val authData = Base64Url.decode(response.getString("authenticatorData"))
        val clientData = Base64Url.decode(response.getString("clientDataJSON"))

        assertEquals(37, authData.size)
        assertEquals(WebAuthn.VAULTLY_FLAGS, authData[32].toInt() and 0xff)
        assertEquals("webauthn.get", JSONObject(String(clientData)).getString("type"))
        assertArrayEquals(userHandle, Base64Url.decode(response.getString("userHandle")))
        assertTrue(
            verify(
                spki(registration.publicKey),
                authData,
                WebAuthn.sha256(clientData),
                Base64Url.decode(response.getString("signature")),
            ),
        )
    }

    @Test
    fun `a privileged browser's clientDataHash is what gets signed`() {
        val registration = PasskeyCeremony.register(PasskeyRequests.parseCreation(creationJson), "webauthn.io", web)
        val browserHash = WebAuthn.sha256("browser-built clientDataJSON".toByteArray())
        val json = JSONObject(
            PasskeyCeremony.assert(
                options = PasskeyRequests.parseAssertion("""{"challenge": "${Base64Url.encode(challenge)}"}"""),
                rpId = "webauthn.io",
                caller = VerifiedCaller("https://webauthn.io", null, browserHash),
                credentialId = registration.credentialId,
                userHandle = userHandle,
                privateKey = WebAuthn.privateKeyFromPkcs8(registration.privateKey),
            ),
        ).getJSONObject("response")
        assertTrue(
            verify(
                spki(registration.publicKey),
                Base64Url.decode(json.getString("authenticatorData")),
                browserHash,
                Base64Url.decode(json.getString("signature")),
            ),
        )
    }

    @Test
    fun `an app caller's clientDataJSON names its package`() {
        val app = VerifiedCaller("android:apk-key-hash:abc", "com.example.app", null)
        val registration = PasskeyCeremony.register(PasskeyRequests.parseCreation(creationJson), "webauthn.io", app)
        val response = JSONObject(registration.responseJson).getJSONObject("response")
        val clientData = JSONObject(String(Base64Url.decode(response.getString("clientDataJSON"))))
        assertEquals("android:apk-key-hash:abc", clientData.getString("origin"))
        assertEquals("com.example.app", clientData.getString("androidPackageName"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `an assertion refuses a credential outside allowCredentials`() {
        val registration = PasskeyCeremony.register(PasskeyRequests.parseCreation(creationJson), "webauthn.io", web)
        PasskeyCeremony.assert(
            options = PasskeyRequests.parseAssertion(
                """{"challenge": "AA", "allowCredentials": [{"type": "public-key", "id": "AQID"}]}""",
            ),
            rpId = "webauthn.io",
            caller = web,
            credentialId = registration.credentialId,
            userHandle = userHandle,
            privateKey = WebAuthn.privateKeyFromPkcs8(registration.privateKey),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `registration refuses an RP that does not accept ES256`() {
        val rsaOnly = creationJson.replace("\"alg\": -7", "\"alg\": -257")
        PasskeyCeremony.register(PasskeyRequests.parseCreation(rsaOnly), "webauthn.io", web)
    }

    @Test
    fun `creation options are parsed`() {
        val options = PasskeyRequests.parseCreation(creationJson)
        assertEquals("webauthn.io", options.rpId)
        assertEquals("WebAuthn.io", options.rpName)
        assertEquals("alice", options.userName)
        assertEquals("Alice", options.userDisplayName)
        assertArrayEquals(userHandle, options.userHandle)
        assertTrue(options.acceptsEs256)
        assertArrayEquals(byteArrayOf(1, 2, 3), options.excludeCredentialIds.single())
    }

    @Test
    fun `an omitted rp id is left to the caller's origin`() {
        val options = PasskeyRequests.parseCreation(creationJson.replace("\"id\": \"webauthn.io\", ", ""))
        assertEquals(null, options.rpId)
        assertEquals(null, PasskeyRequests.parseAssertion("""{"challenge": "AA"}""").rpId)
    }

    private fun spki(encoded: ByteArray): ECPublicKey =
        KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(encoded)) as ECPublicKey
}
