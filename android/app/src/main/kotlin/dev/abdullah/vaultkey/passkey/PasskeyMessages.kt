package dev.abdullah.vaultkey.passkey

import org.json.JSONArray
import org.json.JSONObject
import java.security.PublicKey

/** The parts of `PublicKeyCredentialCreationOptionsJSON` Vaultly acts on. */
class CreationOptions(
    /** `rp.id`; null when the caller left it to default to the origin's host. */
    val rpId: String?,
    val rpName: String,
    val userHandle: ByteArray,
    val userName: String,
    val userDisplayName: String,
    val challenge: ByteArray,
    /** Whether ES256 is among the acceptable algorithms. */
    val acceptsEs256: Boolean,
    val excludeCredentialIds: List<ByteArray>,
)

/** The parts of `PublicKeyCredentialRequestOptionsJSON` Vaultly acts on. */
class AssertionOptions(
    /** `rpId`; null when the caller left it to default to the origin's host. */
    val rpId: String?,
    val challenge: ByteArray,
    /** Empty means "any discoverable credential for the RP". */
    val allowCredentialIds: List<ByteArray>,
)

/** Parses the JSON requests Credential Manager hands a provider. */
object PasskeyRequests {
    fun parseCreation(json: String): CreationOptions {
        val root = JSONObject(json)
        val rp = root.getJSONObject("rp")
        val user = root.getJSONObject("user")
        val params = root.optJSONArray("pubKeyCredParams") ?: JSONArray()
        // An empty list means the RP accepts the defaults, ES256 included.
        val acceptsEs256 = params.length() == 0 ||
            objects(params).any {
                it.optString("type") == "public-key" &&
                    it.optLong("alg") == WebAuthn.COSE_ALG_ES256
            }
        val userName = user.getString("name")
        return CreationOptions(
            rpId = rp.optString("id").ifBlank { null },
            rpName = rp.optString("name").ifBlank { rp.optString("id") },
            userHandle = Base64Url.decode(user.getString("id")),
            userName = userName,
            userDisplayName = user.optString("displayName").ifBlank { userName },
            challenge = Base64Url.decode(root.getString("challenge")),
            acceptsEs256 = acceptsEs256,
            excludeCredentialIds = credentialIds(root.optJSONArray("excludeCredentials")),
        )
    }

    fun parseAssertion(json: String): AssertionOptions {
        val root = JSONObject(json)
        return AssertionOptions(
            rpId = root.optString("rpId").ifBlank { null },
            challenge = Base64Url.decode(root.getString("challenge")),
            allowCredentialIds = credentialIds(root.optJSONArray("allowCredentials")),
        )
    }

    private fun credentialIds(array: JSONArray?): List<ByteArray> =
        if (array == null) emptyList() else objects(array).map { Base64Url.decode(it.getString("id")) }

    private fun objects(array: JSONArray): List<JSONObject> =
        (0 until array.length()).map { array.getJSONObject(it) }
}

/** Builds the JSON responses Credential Manager hands back to the caller. */
object PasskeyResponses {
    /** `RegistrationResponseJSON` for a "none"-attested ES256 credential. */
    fun registration(
        credentialId: ByteArray,
        clientDataJson: String,
        authenticatorData: ByteArray,
        attestationObject: ByteArray,
        publicKey: PublicKey,
    ): String {
        val response = JSONObject()
            .put("clientDataJSON", Base64Url.encode(clientDataJson.toByteArray(Charsets.UTF_8)))
            .put("attestationObject", Base64Url.encode(attestationObject))
            .put("authenticatorData", Base64Url.encode(authenticatorData))
            .put("transports", JSONArray().put("internal").put("hybrid"))
            .put("publicKey", Base64Url.encode(publicKey.encoded))
            .put("publicKeyAlgorithm", WebAuthn.COSE_ALG_ES256)
        return credential(credentialId, response)
            .put(
                "clientExtensionResults",
                JSONObject().put("credProps", JSONObject().put("rk", true)),
            )
            .toString()
    }

    /** `AuthenticationResponseJSON`. */
    fun assertion(
        credentialId: ByteArray,
        clientDataJson: String,
        authenticatorData: ByteArray,
        signature: ByteArray,
        userHandle: ByteArray,
    ): String {
        val response = JSONObject()
            .put("clientDataJSON", Base64Url.encode(clientDataJson.toByteArray(Charsets.UTF_8)))
            .put("authenticatorData", Base64Url.encode(authenticatorData))
            .put("signature", Base64Url.encode(signature))
            .put("userHandle", Base64Url.encode(userHandle))
        return credential(credentialId, response)
            .put("clientExtensionResults", JSONObject())
            .toString()
    }

    private fun credential(credentialId: ByteArray, response: JSONObject): JSONObject =
        JSONObject()
            .put("id", Base64Url.encode(credentialId))
            .put("rawId", Base64Url.encode(credentialId))
            .put("type", "public-key")
            .put("authenticatorAttachment", "platform")
            .put("response", response)
}
