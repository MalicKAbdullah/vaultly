package dev.abdullah.vaultkey

import android.content.Context
import android.content.pm.Signature
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.credentials.provider.CallingAppInfo
import dev.abdullah.vaultkey.passkey.AppSigning
import dev.abdullah.vaultkey.passkey.AssetLinks
import dev.abdullah.vaultkey.passkey.RpIdRules
import dev.abdullah.vaultkey.passkey.VerifiedCaller
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** A credential request Vaultly refuses to answer; [message] is shown to the user. */
class RejectedRequest(message: String) : Exception(message)

/** The app or website behind a Credential Manager request. */
sealed class CredentialCaller {
    abstract val origin: String

    /** A website, with the origin a privileged (allowlisted) browser reported. */
    class Web(override val origin: String, val host: String) : CredentialCaller()

    /** A native app, identified by its package and signing certificates. */
    class App(
        val packageName: String,
        override val origin: String,
        val fingerprints: List<String>,
    ) : CredentialCaller()

    /** What the user sees as "who is asking". */
    val label: String
        get() = when (this) {
            is Web -> host
            is App -> packageName
        }

    /** The RP id WebAuthn defaults to when the request names none. */
    val defaultRpId: String?
        get() = (this as? Web)?.host

    fun toVerified(clientDataHash: ByteArray?): VerifiedCaller =
        VerifiedCaller(
            origin = origin,
            androidPackageName = (this as? App)?.packageName,
            clientDataHash = clientDataHash,
        )

    companion object {
        private const val ASSET_LINKS_TIMEOUT_MS = 5_000
        private const val ASSET_LINKS_MAX_BYTES = 256 * 1024
        private val HOSTNAME = Regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")

        private var allowlist: String? = null

        /**
         * Google's list of browsers trusted to report a web origin
         * (gstatic.com/gpm-passkeys-privileged-apps/apps.json), bundled so
         * the check works offline.
         */
        private fun privilegedAllowlist(context: Context): String =
            allowlist ?: context.resources.openRawResource(R.raw.privileged_browsers)
                .bufferedReader()
                .use { it.readText() }
                .also { allowlist = it }

        /**
         * Identifies the caller. A web origin is accepted only from a browser
         * on the privileged allowlist; any other app gets its
         * `android:apk-key-hash` origin.
         */
        @RequiresApi(Build.VERSION_CODES.P)
        fun resolve(context: Context, info: CallingAppInfo): CredentialCaller {
            val origin = try {
                info.getOrigin(privilegedAllowlist(context))
            } catch (_: IllegalStateException) {
                throw RejectedRequest("${info.packageName} is not a recognised browser.")
            }
            if (origin != null) {
                val trimmed = origin.trimEnd('/')
                val host = RpIdRules.secureOriginHost(trimmed)
                    ?: throw RejectedRequest("$origin is not a secure website.")
                return Web(trimmed, host)
            }
            val signers = info.signingInfo.apkContentsSigners
            if (signers.isEmpty()) throw RejectedRequest("${info.packageName} is not signed.")
            val history: Array<Signature> = if (info.signingInfo.hasMultipleSigners()) {
                emptyArray()
            } else {
                info.signingInfo.signingCertificateHistory ?: emptyArray()
            }
            return App(
                packageName = info.packageName,
                origin = AppSigning.apkKeyHashOrigin(signers.first().toByteArray()),
                fingerprints = (signers + history)
                    .map { AppSigning.sha256Fingerprint(it.toByteArray()) }
                    .distinct(),
            )
        }

        /**
         * Throws unless [caller] may use [rpId]: a website must sit on the RP
         * id's domain; an app must be delegated by the RP's Digital Asset
         * Links file. Blocks on the network for apps — call off the main
         * thread.
         */
        fun verifyRpId(caller: CredentialCaller, rpId: String) {
            when (caller) {
                is Web -> if (!RpIdRules.isValidForOrigin(rpId, caller.origin)) {
                    throw RejectedRequest("${caller.host} cannot use a passkey for $rpId.")
                }
                is App -> {
                    if (!HOSTNAME.matches(rpId)) throw RejectedRequest("$rpId is not a valid site.")
                    val statements = fetchAssetLinks(rpId)
                        ?: throw RejectedRequest("Could not confirm that $rpId trusts ${caller.packageName}. Check your connection.")
                    if (!AssetLinks.delegatesLogin(statements, caller.packageName, caller.fingerprints)) {
                        throw RejectedRequest("$rpId does not list ${caller.packageName} as one of its apps.")
                    }
                }
            }
        }

        private fun fetchAssetLinks(rpId: String): String? {
            val connection = URL(AssetLinks.url(rpId)).openConnection() as HttpURLConnection
            return try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = ASSET_LINKS_TIMEOUT_MS
                connection.readTimeout = ASSET_LINKS_TIMEOUT_MS
                if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
                connection.inputStream.use { stream ->
                    val bytes = stream.readNBytesCompat(ASSET_LINKS_MAX_BYTES + 1)
                    if (bytes.size > ASSET_LINKS_MAX_BYTES) null else String(bytes, Charsets.UTF_8)
                }
            } catch (_: IOException) {
                null
            } finally {
                connection.disconnect()
            }
        }

        private fun java.io.InputStream.readNBytesCompat(limit: Int): ByteArray {
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8 * 1024)
            while (out.size() < limit) {
                val read = read(buffer, 0, minOf(buffer.size, limit - out.size()))
                if (read < 0) break
                out.write(buffer, 0, read)
            }
            return out.toByteArray()
        }
    }
}
