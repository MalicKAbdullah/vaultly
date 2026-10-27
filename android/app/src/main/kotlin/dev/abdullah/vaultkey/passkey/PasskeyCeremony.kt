package dev.abdullah.vaultkey.passkey

import java.security.KeyPair
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey

/** Who is asking, as already verified by the caller of [PasskeyCeremony]. */
class VerifiedCaller(
    /** The origin placed in clientDataJSON. */
    val origin: String,
    /** Set for native-app callers; null for web origins. */
    val androidPackageName: String?,
    /**
     * Hash of the clientDataJSON a privileged browser built itself. When
     * present it is what gets signed; the browser substitutes its own
     * clientDataJSON in the response it returns to the page.
     */
    val clientDataHash: ByteArray?,
)

/** A new passkey: what the vault stores and what goes back to the RP. */
class Registration(
    val credentialId: ByteArray,
    /** X.509 SubjectPublicKeyInfo DER. */
    val publicKey: ByteArray,
    /** PKCS#8 DER. Only ever persisted inside the encrypted vault. */
    val privateKey: ByteArray,
    val responseJson: String,
)

/** Registration and assertion ceremonies for a Vaultly passkey (ES256, "none" attestation, signCount 0). */
object PasskeyCeremony {
    private const val CREDENTIAL_ID_BYTES = 32

    fun register(
        options: CreationOptions,
        rpId: String,
        caller: VerifiedCaller,
        keyPair: KeyPair = WebAuthn.generateKeyPair(),
        credentialId: ByteArray = randomCredentialId(),
    ): Registration {
        require(options.acceptsEs256) { "The relying party does not accept ES256" }
        val publicKey = keyPair.public as ECPublicKey
        val authData = WebAuthn.authenticatorData(
            rpId = rpId,
            flags = WebAuthn.VAULTLY_FLAGS or WebAuthn.FLAG_AT,
            signCount = 0,
            attestedCredentialData = WebAuthn.attestedCredentialData(
                WebAuthn.AAGUID,
                credentialId,
                publicKey,
            ),
        )
        val clientDataJson = WebAuthn.clientDataJson(
            type = "webauthn.create",
            challenge = options.challenge,
            origin = caller.origin,
            androidPackageName = caller.androidPackageName,
        )
        return Registration(
            credentialId = credentialId,
            publicKey = publicKey.encoded,
            privateKey = keyPair.private.encoded,
            responseJson = PasskeyResponses.registration(
                credentialId = credentialId,
                clientDataJson = clientDataJson,
                authenticatorData = authData,
                attestationObject = WebAuthn.noneAttestationObject(authData),
                publicKey = publicKey,
            ),
        )
    }

    /** The `AuthenticationResponseJSON` for one stored passkey. */
    fun assert(
        options: AssertionOptions,
        rpId: String,
        caller: VerifiedCaller,
        credentialId: ByteArray,
        userHandle: ByteArray,
        privateKey: PrivateKey,
    ): String {
        require(
            options.allowCredentialIds.isEmpty() ||
                options.allowCredentialIds.any { it.contentEquals(credentialId) },
        ) { "The relying party did not ask for this credential" }
        // A synced-style credential keeps signCount at 0 (WebAuthn §6.1.1).
        val authData = WebAuthn.authenticatorData(rpId, WebAuthn.VAULTLY_FLAGS, signCount = 0)
        val clientDataJson = WebAuthn.clientDataJson(
            type = "webauthn.get",
            challenge = options.challenge,
            origin = caller.origin,
            androidPackageName = caller.androidPackageName,
        )
        val clientDataHash =
            caller.clientDataHash ?: WebAuthn.sha256(clientDataJson.toByteArray(Charsets.UTF_8))
        return PasskeyResponses.assertion(
            credentialId = credentialId,
            clientDataJson = clientDataJson,
            authenticatorData = authData,
            signature = WebAuthn.sign(privateKey, authData, clientDataHash),
            userHandle = userHandle,
        )
    }

    private fun randomCredentialId(): ByteArray =
        ByteArray(CREDENTIAL_ID_BYTES).also { SecureRandom().nextBytes(it) }
}
