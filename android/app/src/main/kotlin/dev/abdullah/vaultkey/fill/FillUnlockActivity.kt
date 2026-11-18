package dev.abdullah.vaultkey.fill

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.annotation.RequiresApi
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import dev.abdullah.vaultkey.vault.BiometricGate
import dev.abdullah.vaultkey.vault.VaultFileReader
import dev.abdullah.vaultkey.vault.VaultKeyWrap
import dev.abdullah.vaultkey.vault.VaultRecord
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The sheet behind Vaultly's autofill chip: a fingerprint prompt over the
 * page, then either the one confirmed login filled straight away or a short
 * list to pick from. It runs without Flutter: the wrapped vault key is
 * released by the prompt and the vault file is decrypted here.
 *
 * The vault key lives only between the fingerprint and the end of
 * decryption and is zeroed there. Decrypted records are dropped in
 * [onDestroy]; the Strings in them cannot be zeroed, as in any autofill
 * service.
 */
@RequiresApi(Build.VERSION_CODES.O)
class FillUnlockActivity : FragmentActivity() {

    private lateinit var target: RequestTarget
    private lateinit var usernameIds: ArrayList<AutofillId>
    private lateinit var passwordIds: ArrayList<AutofillId>
    private lateinit var targetLabel: String
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private var records: List<VaultRecord> = emptyList()
    private var list: LinearLayout? = null
    private var done = false
    private var onSurface = Color.BLACK
    private var muted = Color.GRAY

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        target = FillRequestIntents.target(intent)
        usernameIds = intent.getParcelableArrayListExtra(FillRequestIntents.EXTRA_USERNAME_IDS)!!
        passwordIds = intent.getParcelableArrayListExtra(FillRequestIntents.EXTRA_PASSWORD_IDS)!!
        targetLabel = when (target) {
            is RequestTarget.Web -> (target as RequestTarget.Web).host
            is RequestTarget.App -> appLabel((target as RequestTarget.App).packageName)
        }
        val wrap = VaultKeyWrap(this)
        when (val unwrap = wrap.prepareUnwrap()) {
            // Dart owns cleaning up a key that can no longer be used.
            VaultKeyWrap.Unwrap.Missing, VaultKeyWrap.Unwrap.Invalidated -> openFullApp()
            is VaultKeyWrap.Unwrap.Ready -> {
                // The file is not secret; read it while the prompt is up.
                val encrypted = worker.submit<ByteArray?> { VaultFileReader.readEncrypted(VaultFileReader.file(this)) }
                BiometricGate.prompt(
                    this, "Unlock Vaultly", "Fill on $targetLabel", unwrap.cipher,
                    onCancel = { code ->
                        if (code == BiometricPrompt.ERROR_NEGATIVE_BUTTON) openFullApp() else cancel()
                    },
                ) { authorized -> unlock(wrap, unwrap, authorized, encrypted.get()) }
            }
        }
    }

    private fun unlock(
        wrap: VaultKeyWrap,
        unwrap: VaultKeyWrap.Unwrap.Ready,
        authorized: javax.crypto.Cipher,
        encrypted: ByteArray?,
    ) {
        val key = wrap.unwrap(unwrap, authorized)
        worker.execute {
            val opened = try {
                encrypted?.let { VaultFileReader.decrypt(it, key) }
            } finally {
                key.fill(0)
            }
            runOnUiThread { if (!isDestroyed) show(opened) }
        }
    }

    private fun show(opened: List<VaultRecord>?) {
        if (opened == null) return cancel()
        records = opened
        val remembered = RememberedChoices(this).get(target)
        when (val plan = FillPlan.of(records, target, remembered)) {
            is FillPlan.Fill -> fill(plan.record, remember = false, keepReady = true)
            is FillPlan.Choose -> showList(plan.ranked)
        }
    }

    private fun fill(record: VaultRecord, remember: Boolean, keepReady: Boolean) {
        if (done) return
        done = true
        if (remember) RememberedChoices(this).put(target, record.id)
        val values = LinkedHashMap<AutofillId, String>()
        usernameIds.forEach { values[it] = record.username }
        passwordIds.forEach { values[it] = record.password }
        val dataset = DatasetFactory.filled(this, "Vaultly", values)
        // Later pages of this sign-in (a password after the email, a code
        // after the password) continue from one tap.
        val moreToFill = passwordIds.isEmpty() || record.totp != null
        if (keepReady && moreToFill && FillSettings(this).sessionEnabled) {
            FillSession.arm(
                this, record.id, record.username.ifEmpty { record.title },
                record.username.toCharArray(), record.password.toCharArray(), record.totp,
                SessionScope.begunOn(target, record.url, EquivalentDomains.get(this)),
            )
        }
        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, true)
                }
            },
        )
        finish()
    }

    private fun cancel() {
        if (done) return
        done = true
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    /** Master-password users, and a key that no longer unlocks, continue in the app. */
    private fun openFullApp() {
        if (done) return
        done = true
        val main = FillRequestIntents.mainActivity(this, target, usernameIds, passwordIds)
        main.addFlags(Intent.FLAG_ACTIVITY_FORWARD_RESULT)
        startActivity(main)
        finish()
    }

    // The list sheet. Plain views: nothing here may pull in Flutter or AppCompat.

    private fun showList(ranked: List<VaultRecord>) {
        val dark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val surface = if (dark) Color.parseColor("#1E1E24") else Color.WHITE
        onSurface = if (dark) Color.parseColor("#ECECF1") else Color.parseColor("#1B1B1F")
        muted = if (dark) Color.parseColor("#A6A6B0") else Color.parseColor("#5F5F68")
        val dp = resources.displayMetrics.density

        val root = FrameLayout(this)
        root.setBackgroundColor(Color.parseColor("#66000000"))
        root.setOnClickListener { cancel() }

        val sheet = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(surface)
                cornerRadii = floatArrayOf(24 * dp, 24 * dp, 24 * dp, 24 * dp, 0f, 0f, 0f, 0f)
            }
            setPadding((20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt(), (12 * dp).toInt())
            isClickable = true
        }
        sheet.addView(
            TextView(this).apply {
                text = "Fill on $targetLabel"
                textSize = 18f
                setTextColor(onSurface)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            },
        )
        val search = EditText(this).apply {
            hint = "Search your vault"
            setSingleLine()
            setTextColor(onSurface)
            setHintTextColor(muted)
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
        }
        sheet.addView(search, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = (12 * dp).toInt()
        })
        val rows = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        list = rows
        val scroll = ScrollView(this).apply { addView(rows) }
        sheet.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (320 * dp).toInt()))

        fun render(items: List<VaultRecord>) {
            rows.removeAllViews()
            if (items.isEmpty()) {
                rows.addView(TextView(this).apply {
                    text = "Nothing saved for this yet. Search your vault."
                    setTextColor(muted)
                    setPadding(0, (16 * dp).toInt(), 0, (16 * dp).toInt())
                })
            }
            items.take(MAX_ROWS).forEach { rows.addView(row(it, dp)) }
        }
        render(ranked)
        search.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(s: Editable?) {
                val q = s?.toString().orEmpty().trim().lowercase()
                render(if (q.isEmpty()) ranked else records.filter { matchesQuery(it, q) }.sortedBy { it.title.lowercase() })
            }
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
        })

        root.addView(
            sheet,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM),
        )
        setContentView(root)
        sheet.setOnApplyWindowInsetsListener { v, insets ->
            @Suppress("DEPRECATION")
            v.setPadding(v.paddingLeft, v.paddingTop, v.paddingRight, (12 * dp).toInt() + insets.systemWindowInsetBottom)
            insets
        }
    }

    private fun matchesQuery(record: VaultRecord, q: String): Boolean =
        record.title.lowercase().contains(q) || record.username.lowercase().contains(q) ||
            record.url.lowercase().contains(q)

    private fun row(record: VaultRecord, dp: Float): View =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
            isClickable = true
            val outValue = android.util.TypedValue()
            if (theme.resolveAttribute(android.R.attr.selectableItemBackground, outValue, true)) {
                setBackgroundResource(outValue.resourceId)
            }
            addView(TextView(context).apply {
                text = record.title.ifEmpty { record.url }
                textSize = 16f
                setTextColor(onSurface)
            })
            addView(TextView(context).apply {
                text = record.username
                textSize = 13f
                setTextColor(muted)
            })
            setOnClickListener { pick(record) }
        }

    private fun pick(record: VaultRecord) {
        if (FillPlan.matches(record, target)) return fill(record, remember = true, keepReady = true)
        val host = EntryHost.of(record)
        val rows = list ?: return
        rows.removeAllViews()
        rows.addView(TextView(this).apply {
            text = if (host.isEmpty()) "${record.title} is not saved for this." else "${record.title} is saved for $host."
            textSize = 15f
            setTextColor(onSurface)
            setPadding(0, 16, 0, 16)
        })
        rows.addView(android.widget.Button(this).apply {
            text = "Fill anyway"
            setOnClickListener { fill(record, remember = false, keepReady = false) }
        })
    }

    private fun appLabel(packageName: String): String =
        try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
        } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
            // The app is gone or hidden from us; its package name still names it.
            packageName
        }

    override fun onDestroy() {
        records = emptyList()
        list = null
        worker.shutdownNow()
        super.onDestroy()
    }

    private companion object {
        const val MAX_ROWS = 30
    }
}

/** The host an entry is saved for, for display. */
object EntryHost {
    fun of(record: VaultRecord): String = dev.abdullah.vaultkey.vault.EntryMatcher.normalizeHost(record.url)
}
