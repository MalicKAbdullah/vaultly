package dev.abdullah.vaultkey.fill

import dev.abdullah.vaultkey.vault.EntryMatcher
import dev.abdullah.vaultkey.vault.VaultRecord

/** What to do with the unlocked vault for one fill request. */
sealed class FillPlan {
    /** One entry is confirmed for the target: fill it without asking. */
    data class Fill(val record: VaultRecord) : FillPlan()

    /** Show [ranked] first, the whole vault behind the search box. */
    data class Choose(val ranked: List<VaultRecord>) : FillPlan()

    companion object {
        fun of(records: List<VaultRecord>, target: RequestTarget, rememberedId: String?, needsCode: Boolean = false): FillPlan {
            val domain = (target as? RequestTarget.Web)?.host
            val pkg = (target as? RequestTarget.App)?.packageName
            // A page that only asks for a code can only be answered by an entry with a secret.
            val fillable = records.filter {
                if (needsCode) it.totp != null else it.username.isNotEmpty() || it.password.isNotEmpty()
            }
            EntryMatcher.confirmed(fillable, domain, pkg, rememberedId)?.let { return Fill(it) }
            return Choose(EntryMatcher.rank(fillable, domain, pkg))
        }

        /** Whether [record] has any signal for the target; a pick without one is not remembered. */
        fun matches(record: VaultRecord, target: RequestTarget): Boolean {
            val domain = (target as? RequestTarget.Web)?.host
            val pkg = (target as? RequestTarget.App)?.packageName
            return EntryMatcher.score(record, domain, pkg) > 0
        }
    }
}
