package dev.abdullah.vaultkey.vault

import java.net.URI
import java.net.URISyntaxException

/**
 * Ranks vault entries against a fill target: a port of Dart's
 * `AutofillMatcher`, held to the same vectors
 * (`test/fixtures/contract/matcher_vectors.json`). A request carries a web
 * [domain] (trusted browsers only) or an app [packageName], never both.
 */
object EntryMatcher {

    const val EXACT_HOST = 100
    const val RELATED_HOST = 80

    /** Package segments that carry no identity ("com" in com.github.android). */
    private val genericSegments = setOf(
        "com", "org", "net", "io", "co", "de", "uk", "eu", "app", "apps", "android",
        "mobile", "client", "beta", "free", "main", "www",
    )

    /** How well [entry] matches the request. 0 means no signal at all. */
    fun score(entry: VaultRecord, domain: String?, packageName: String?): Int {
        val host = normalizeHost(domain.orEmpty())
        val entryHost = normalizeHost(entry.url)
        val title = entry.title.lowercase()

        var best = 0
        if (host.isNotEmpty()) {
            if (entryHost.isNotEmpty()) {
                if (entryHost == host) {
                    best = maxOf(best, EXACT_HOST)
                } else if (host.endsWith(".$entryHost") || entryHost.endsWith(".$host")) {
                    best = maxOf(best, RELATED_HOST)
                }
            }
            val base = baseLabel(host)
            if (base.isNotEmpty() && title.contains(base)) best = maxOf(best, 40)
        }

        val pkg = packageName.orEmpty().lowercase()
        if (pkg.isNotEmpty()) {
            for (segment in pkg.split('.')) {
                if (segment.length < 3 || segment in genericSegments) continue
                if (entryHost.contains(segment)) best = maxOf(best, 60)
                if (title.contains(segment)) best = maxOf(best, 40)
            }
        }
        return best
    }

    /** Entries that match, best first (ties by title, case-insensitive). */
    fun rank(entries: List<VaultRecord>, domain: String?, packageName: String?): List<VaultRecord> =
        entries
            .map { it to score(it, domain, packageName) }
            .filter { it.second > 0 }
            .sortedWith(compareByDescending<Pair<VaultRecord, Int>> { it.second }.thenBy { it.first.title.lowercase() })
            .map { it.first }

    /**
     * The one entry that may be filled without showing a list, or null.
     *
     * An entry is confirmed for the target when the page host equals its
     * host exactly ([domain] is only ever a trusted browser's page), or when
     * it is [rememberedId], the entry the user picked for this exact target
     * before. A fill needs exactly one confirmed entry and no other entry
     * on the same host or a parent/child domain: a title or subdomain match
     * is no evidence about the site, and one fingerprint must never send a
     * password to a look-alike.
     */
    fun confirmed(
        entries: List<VaultRecord>,
        domain: String?,
        packageName: String?,
        rememberedId: String?,
    ): VaultRecord? {
        val fillable = entries.filter { !it.hasPasskey }
        val confirmed = fillable.filter {
            it.id == rememberedId || (domain != null && score(it, domain, null) == EXACT_HOST)
        }
        if (confirmed.size != 1) return null
        val only = confirmed.single()
        val rivals = fillable.any {
            it.id != only.id && score(it, domain, packageName) >= RELATED_HOST
        }
        return if (rivals) null else only
    }

    /** Lower-cased host without scheme, path, port, or a leading `www.`. */
    fun normalizeHost(raw: String): String {
        var value = raw.trim().lowercase()
        if (value.isEmpty()) return ""
        if (!value.contains("://")) value = "https://$value"
        val host = try {
            URI(value).host
        } catch (_: URISyntaxException) {
            null
        } ?: return ""
        return host.removePrefix("www.")
    }

    private fun baseLabel(host: String): String {
        val parts = host.split('.')
        return if (parts.size < 2) host else parts[parts.size - 2]
    }
}
