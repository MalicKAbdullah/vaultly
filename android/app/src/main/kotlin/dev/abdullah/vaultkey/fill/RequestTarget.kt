package dev.abdullah.vaultkey.fill

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import dev.abdullah.vaultkey.R
import dev.abdullah.vaultkey.passkey.AppSigning
import org.json.JSONObject

/**
 * Who a fill request is for.
 *
 * Any app can put a web domain into its view structure, so a domain is
 * believed only from a browser on [BrowserAllowlist] whose signing
 * certificate matches; every other request is an [App], however its views
 * describe themselves.
 */
sealed class RequestTarget {
    /** A page shown by a trusted browser. */
    data class Web(val host: String, val browserPackage: String) : RequestTarget()

    /**
     * A native app. [certSha256] identifies its signer(s) (null when the
     * package's signing info cannot be read); [claimedDomain] is a domain
     * its views report, never trusted.
     */
    data class App(
        val packageName: String,
        val certSha256: String?,
        val claimedDomain: String?,
    ) : RequestTarget()

    companion object {
        /** [signers] are the package's current signing certificates, null when unreadable. */
        fun resolve(
            packageName: String,
            signers: List<ByteArray>?,
            webDomain: String?,
            allowlist: BrowserAllowlist,
        ): RequestTarget {
            val fingerprints = signers?.map { AppSigning.sha256Fingerprint(it) }
            if (webDomain != null && fingerprints != null &&
                allowlist.isTrusted(packageName, fingerprints)
            ) {
                return Web(webDomain, packageName)
            }
            return App(
                packageName = packageName,
                certSha256 = fingerprints?.sorted()?.joinToString(","),
                claimedDomain = webDomain,
            )
        }
    }
}

/**
 * Browsers trusted to report the site they show: Google's privileged-apps
 * list (gstatic.com/gpm-passkeys-privileged-apps/apps.json), bundled as
 * `res/raw/privileged_browsers.json` and shared with the passkey provider.
 */
class BrowserAllowlist(private val fingerprintsByPackage: Map<String, Set<String>>) {

    /** True when every one of the package's signers is listed for it. */
    fun isTrusted(packageName: String, signerFingerprints: List<String>): Boolean {
        val listed = fingerprintsByPackage[packageName] ?: return false
        return signerFingerprints.isNotEmpty() && signerFingerprints.all { it in listed }
    }

    companion object {
        @Volatile private var json: String? = null
        @Volatile private var loaded: BrowserAllowlist? = null

        /** The bundled list as text, read once per process. Reads a resource: keep it off the main thread. */
        fun rawJson(context: Context): String =
            json ?: synchronized(this) {
                json ?: context.resources.openRawResource(R.raw.privileged_browsers)
                    .bufferedReader().use { it.readText() }
                    .also { json = it }
            }

        /** Parsed once per process. Reads a resource: keep it off the main thread. */
        fun get(context: Context): BrowserAllowlist =
            loaded ?: synchronized(this) {
                loaded ?: parse(rawJson(context)).also { loaded = it }
            }

        fun parse(json: String): BrowserAllowlist {
            val apps = JSONObject(json).getJSONArray("apps")
            val map = HashMap<String, MutableSet<String>>()
            for (i in 0 until apps.length()) {
                val app = apps.getJSONObject(i)
                if (app.optString("type") != "android") continue
                val info = app.getJSONObject("info")
                val signatures = info.getJSONArray("signatures")
                val set = map.getOrPut(info.getString("package_name")) { HashSet() }
                for (j in 0 until signatures.length()) {
                    set.add(signatures.getJSONObject(j).getString("cert_fingerprint_sha256").uppercase())
                }
            }
            return BrowserAllowlist(map)
        }
    }
}

/** Current signing certificates of installed packages. */
object AppSigners {
    /** Null when the package is not visible to Vaultly or not installed. */
    @Suppress("DEPRECATION")
    fun of(context: Context, packageName: String): List<ByteArray>? {
        val pm = context.packageManager
        return try {
            val signatures: Array<Signature>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo?.apkContentsSigners
            } else {
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
            }
            signatures?.map { it.toByteArray() }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }
}
