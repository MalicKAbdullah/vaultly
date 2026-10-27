package dev.abdullah.vaultkey.passkey

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

/** Relying-party id rules for callers whose web origin the platform vouches for. */
object RpIdRules {
    /**
     * The host of a secure web origin, or null when [origin] is not one:
     * `https://host[:port]`, or `http://localhost[:port]` for development.
     */
    fun secureOriginHost(origin: String): String? {
        val uri = try {
            URI(origin.trimEnd('/'))
        } catch (_: Exception) {
            return null
        }
        val host = uri.host?.lowercase() ?: return null
        if (uri.rawUserInfo != null) return null
        if (!uri.rawPath.isNullOrEmpty() || uri.rawQuery != null || uri.rawFragment != null) return null
        return when (uri.scheme?.lowercase()) {
            "https" -> host
            "http" -> host.takeIf { it == "localhost" }
            else -> null
        }
    }

    /**
     * Whether [rpId] may be used from [origin] (WebAuthn §5.1.3 / §5.1.4):
     * the origin's host must equal the RP id or be a subdomain of it.
     *
     * Without the Public Suffix List on the device, a bare public suffix is
     * only rejected when it has no dot (`com`); multi-label suffixes such as
     * `co.uk` are not caught here.
     */
    fun isValidForOrigin(rpId: String, origin: String): Boolean {
        val host = secureOriginHost(origin) ?: return false
        val id = rpId.lowercase()
        if (id.isEmpty() || id.startsWith('.') || id.endsWith('.')) return false
        if (!id.contains('.') && id != "localhost") return false
        return host == id || host.endsWith(".$id")
    }
}

/** Identity of a native Android app, as WebAuthn and Digital Asset Links name it. */
object AppSigning {
    /** The origin Android apps use in clientDataJSON: `android:apk-key-hash:<b64url(SHA-256(cert))>`. */
    fun apkKeyHashOrigin(signingCert: ByteArray): String =
        "android:apk-key-hash:" + Base64Url.encode(WebAuthn.sha256(signingCert))

    /** `AB:CD:…` — the form `sha256_cert_fingerprints` uses in assetlinks.json. */
    fun sha256Fingerprint(signingCert: ByteArray): String =
        WebAuthn.sha256(signingCert).joinToString(":") { "%02X".format(it) }
}

/**
 * Digital Asset Links check for native apps: the RP's
 * `https://<rpId>/.well-known/assetlinks.json` must delegate sign-in
 * credentials to the calling app's package and signing certificate.
 */
object AssetLinks {
    const val LOGIN_RELATION = "delegate_permission/common.get_login_creds"

    fun url(rpId: String): String = "https://$rpId/.well-known/assetlinks.json"

    /**
     * Whether the statement list in [json] grants [LOGIN_RELATION] to the
     * Android app [packageName] signed by any of [fingerprints]. `include`
     * statements are not followed.
     */
    fun delegatesLogin(json: String, packageName: String, fingerprints: Collection<String>): Boolean {
        val wanted = fingerprints.map { it.uppercase() }.toSet()
        val statements = try {
            JSONArray(json)
        } catch (_: Exception) {
            return false
        }
        for (i in 0 until statements.length()) {
            val statement = statements.optJSONObject(i) ?: continue
            if (!hasRelation(statement)) continue
            val target = statement.optJSONObject("target") ?: continue
            if (target.optString("namespace") != "android_app") continue
            if (target.optString("package_name") != packageName) continue
            val prints = target.optJSONArray("sha256_cert_fingerprints") ?: continue
            for (j in 0 until prints.length()) {
                if (prints.optString(j).uppercase() in wanted) return true
            }
        }
        return false
    }

    private fun hasRelation(statement: JSONObject): Boolean {
        val relations = statement.optJSONArray("relation") ?: return false
        return (0 until relations.length()).any { relations.optString(it) == LOGIN_RELATION }
    }
}
