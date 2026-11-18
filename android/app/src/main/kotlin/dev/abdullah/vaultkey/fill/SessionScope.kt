package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.vault.EntryMatcher

/**
 * Where a fill session may be used: the same site or app it began on.
 *
 * Web: the picked host, the entry's own host and their subdomains
 * (dot-boundary, so `notgoogle.com` is not `google.com`), and the
 * equivalent domains of the entry's host. App: the same package with the
 * same signing certificate; a session begun in an app also covers the
 * entry's own site, so a sign-in that moves into a browser continues. A
 * session begun on the web is never offered to an app.
 */
class SessionScope private constructor(
    private val hosts: Set<String>,
    private val appPackage: String?,
    private val appCert: String?,
) {
    fun covers(target: RequestTarget): Boolean = when (target) {
        is RequestTarget.Web -> hosts.any { target.host == it || target.host.endsWith(".$it") }
        is RequestTarget.App -> appPackage == target.packageName && appCert == target.certSha256
    }

    companion object {
        fun begunOn(target: RequestTarget, entryUrl: String, equivalents: EquivalentDomains): SessionScope {
            val entryHost = EntryMatcher.normalizeHost(entryUrl)
            val hosts = linkedSetOf<String>()
            if (entryHost.isNotEmpty()) hosts.addAll(equivalents.expand(entryHost))
            return when (target) {
                is RequestTarget.Web -> {
                    hosts.add(target.host)
                    SessionScope(hosts, null, null)
                }
                is RequestTarget.App -> SessionScope(hosts, target.packageName, target.certSha256)
            }
        }

        /** For a session started from the app itself ("Sign in" on an entry): the entry's site. */
        fun forSite(entryUrl: String, equivalents: EquivalentDomains): SessionScope =
            SessionScope(equivalents.expand(EntryMatcher.normalizeHost(entryUrl)), null, null)
    }
}
