package dev.abdullah.vaultkey.fill

import android.content.Context
import dev.abdullah.vaultkey.R
import org.json.JSONObject

/**
 * Sites that share one sign-in across several domains (an identity
 * provider's own hops). A bundled, curated table: a session that covers one
 * member covers the others.
 */
class EquivalentDomains(private val groups: List<Set<String>>) {

    /** [host] itself plus every member of each group it belongs to. */
    fun expand(host: String): Set<String> {
        val out = linkedSetOf(host)
        for (group in groups) {
            if (group.any { host == it || host.endsWith(".$it") }) out.addAll(group)
        }
        return out
    }

    companion object {
        @Volatile private var loaded: EquivalentDomains? = null

        /** Parsed once per process. Reads a resource: keep it off the main thread. */
        fun get(context: Context): EquivalentDomains =
            loaded ?: synchronized(this) {
                loaded ?: parse(
                    context.resources.openRawResource(R.raw.equivalent_domains)
                        .bufferedReader().use { it.readText() },
                ).also { loaded = it }
            }

        fun parse(json: String): EquivalentDomains {
            val groups = JSONObject(json).getJSONArray("groups")
            return EquivalentDomains(
                List(groups.length()) { i ->
                    val g = groups.getJSONArray(i)
                    List(g.length()) { g.getString(it) }.toSet()
                },
            )
        }
    }
}
