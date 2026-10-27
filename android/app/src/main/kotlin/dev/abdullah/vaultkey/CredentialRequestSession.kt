package dev.abdullah.vaultkey

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPasswordOption
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PasswordCredential
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.exceptions.domerrors.InvalidStateError
import androidx.credentials.exceptions.publickeycredential.CreatePublicKeyCredentialDomException
import androidx.credentials.provider.BeginGetCredentialRequest
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPasswordOption
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.PasswordCredentialEntry
import androidx.credentials.provider.PendingIntentHandler
import androidx.credentials.provider.PublicKeyCredentialEntry
import dev.abdullah.vaultkey.passkey.AssertionOptions
import dev.abdullah.vaultkey.passkey.Base64Url
import dev.abdullah.vaultkey.passkey.CreationOptions
import dev.abdullah.vaultkey.passkey.PasskeyCeremony
import dev.abdullah.vaultkey.passkey.PasskeyRequests
import dev.abdullah.vaultkey.passkey.Registration
import dev.abdullah.vaultkey.passkey.VerifiedCaller
import dev.abdullah.vaultkey.passkey.WebAuthn
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * One Credential Manager request that [CredentialProviderActivity] was
 * launched to answer. Flutter drives it: it unlocks the vault (the user
 * verification), then calls back with what the vault holds. Every path ends
 * with exactly one result handed to Android and the activity finishing.
 *
 * Kinds:
 * - [KIND_CREATE]: register a new passkey.
 * - [KIND_UNLOCK]: the "Unlock Vaultly" authentication action; answers with
 *   the matching passkeys and passwords as credential entries.
 * - [KIND_PASSKEY]: sign in with the passkey the user picked.
 * - [KIND_PASSWORD]: hand over the password the user picked.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class CredentialRequestSession(private val activity: Activity) {

    companion object {
        const val EXTRA_KIND = "vaultly_credential_kind"
        const val EXTRA_CREDENTIAL_ID = "vaultly_credential_id"
        const val EXTRA_ENTRY_ID = "vaultly_entry_id"

        const val KIND_CREATE = "create"
        const val KIND_UNLOCK = "unlock"
        const val KIND_PASSKEY = "passkey"
        const val KIND_PASSWORD = "password"

        /** A PendingIntent that opens [CredentialProviderActivity] for one request. */
        fun pendingIntent(context: Context, kind: String, extras: Map<String, String> = emptyMap()): PendingIntent {
            val intent = Intent(context, CredentialProviderActivity::class.java).apply {
                putExtra(EXTRA_KIND, kind)
                extras.forEach { (key, value) -> putExtra(key, value) }
                // Distinct identifiers keep one PendingIntent per entry
                // instead of the system merging them.
                identifier = listOf(kind, *extras.values.toTypedArray()).joinToString(":")
            }
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
    }

    private val intent: Intent = activity.intent
    private val kind: String? = intent.getStringExtra(EXTRA_KIND)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var rejection: String? = null
    private var caller: VerifiedCaller? = null
    private var rpId: String? = null
    private var creation: CreationOptions? = null
    private var registration: Registration? = null
    private var assertion: AssertionOptions? = null
    private var beginRequest: BeginGetCredentialRequest? = null
    private var finished = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (finished) {
            result.error("finished", "The request was already answered", null)
            return
        }
        try {
            when (call.method) {
                "getPendingRequest" -> pendingRequest(result)
                "register" -> result.success(register())
                "finishRegistration" -> result.success(finishRegistration())
                "list" -> result.success(list(call))
                "assert" -> result.success(assert(call))
                "fillPassword" -> result.success(fillPassword(call))
                "cancel" -> {
                    cancel(call.argument<String>("reason"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: RuntimeException) {
            // check()/require() failures: Flutter asked for something this
            // request cannot do. Reported, never answered with a credential.
            result.error("bad_state", e.message, null)
        }
    }

    private fun pendingRequest(result: MethodChannel.Result) {
        val prepare: (() -> Map<String, Any?>)? = when (kind) {
            KIND_CREATE -> ::prepareCreate
            KIND_UNLOCK -> ::prepareListing
            KIND_PASSKEY -> ::prepareAssertion
            KIND_PASSWORD -> ::preparePassword
            else -> null
        }
        if (prepare == null) {
            result.success(null)
            return
        }
        // Verifying an app caller reads the RP's assetlinks.json: off the main thread.
        worker.execute {
            val answer = try {
                prepare()
            } catch (e: RejectedRequest) {
                rejection = e.message
                mapOf("kind" to "invalid", "message" to e.message)
            } catch (e: Exception) {
                rejection = "This request could not be read."
                mapOf("kind" to "invalid", "message" to rejection)
            }
            main.post { result.success(answer) }
        }
    }

    private fun prepareCreate(): Map<String, Any?> {
        val request = PendingIntentHandler.retrieveProviderCreateCredentialRequest(intent)
            ?: throw RejectedRequest("The request is missing.")
        val call = request.callingRequest as? CreatePublicKeyCredentialRequest
            ?: throw RejectedRequest("Vaultly only saves passkeys here.")
        val options = PasskeyRequests.parseCreation(call.requestJson)
        if (!options.acceptsEs256) {
            throw RejectedRequest("This site needs a passkey type Vaultly does not support.")
        }
        val who = CredentialCaller.resolve(activity, request.callingAppInfo)
        val id = options.rpId ?: who.defaultRpId ?: throw RejectedRequest("The app did not name a website.")
        CredentialCaller.verifyRpId(who, id)
        caller = who.toVerified(call.clientDataHash)
        rpId = id
        creation = options
        return mapOf(
            "kind" to "register",
            "rpId" to id,
            "rpName" to options.rpName.ifBlank { id },
            "userName" to options.userName,
            "userDisplayName" to options.userDisplayName,
            "userHandle" to Base64Url.encode(options.userHandle),
            "excludeCredentialIds" to options.excludeCredentialIds.map(Base64Url::encode),
            "caller" to who.label,
        )
    }

    private fun prepareListing(): Map<String, Any?> {
        val request = PendingIntentHandler.retrieveBeginGetCredentialRequest(intent)
            ?: throw RejectedRequest("The request is missing.")
        beginRequest = request
        val web = request.callingAppInfo
            ?.let { runCatching { CredentialCaller.resolve(activity, it) }.getOrNull() } as? CredentialCaller.Web
        val rpIds = request.beginGetCredentialOptions
            .filterIsInstance<BeginGetPublicKeyCredentialOption>()
            .mapNotNull { option -> listingRpId(option, web) }
            .distinct()
        return mapOf(
            "kind" to "list",
            "rpIds" to rpIds,
            "passwords" to request.beginGetCredentialOptions.any { it is BeginGetPasswordOption },
            "domain" to web?.host,
            "package" to if (web == null) request.callingAppInfo?.packageName else null,
        )
    }

    private fun listingRpId(option: BeginGetPublicKeyCredentialOption, web: CredentialCaller.Web?): String? =
        runCatching { PasskeyRequests.parseAssertion(option.requestJson) }
            .getOrNull()
            ?.let { it.rpId ?: web?.host }

    private fun prepareAssertion(): Map<String, Any?> {
        val request = PendingIntentHandler.retrieveProviderGetCredentialRequest(intent)
            ?: throw RejectedRequest("The request is missing.")
        val option = request.credentialOptions.filterIsInstance<GetPublicKeyCredentialOption>().firstOrNull()
            ?: throw RejectedRequest("No passkey was requested.")
        val credentialId = intent.getStringExtra(EXTRA_CREDENTIAL_ID)
            ?: throw RejectedRequest("No passkey was chosen.")
        val options = PasskeyRequests.parseAssertion(option.requestJson)
        val who = CredentialCaller.resolve(activity, request.callingAppInfo)
        val id = options.rpId ?: who.defaultRpId ?: throw RejectedRequest("The app did not name a website.")
        CredentialCaller.verifyRpId(who, id)
        val idBytes = Base64Url.decode(credentialId)
        if (options.allowCredentialIds.isNotEmpty() && options.allowCredentialIds.none { it.contentEquals(idBytes) }) {
            throw RejectedRequest("$id did not ask for this passkey.")
        }
        caller = who.toVerified(option.clientDataHash)
        rpId = id
        assertion = options
        return mapOf(
            "kind" to "passkey",
            "credentialId" to credentialId,
            "rpId" to id,
            "caller" to who.label,
        )
    }

    private fun preparePassword(): Map<String, Any?> {
        val request = PendingIntentHandler.retrieveProviderGetCredentialRequest(intent)
            ?: throw RejectedRequest("The request is missing.")
        if (request.credentialOptions.none { it is GetPasswordOption }) {
            throw RejectedRequest("No password was requested.")
        }
        val entryId = intent.getStringExtra(EXTRA_ENTRY_ID) ?: throw RejectedRequest("No password was chosen.")
        return mapOf("kind" to "password", "entryId" to entryId)
    }

    /** Creates the key pair; Flutter stores it in the vault, then calls [finishRegistration]. */
    private fun register(): Map<String, String> {
        val reg = PasskeyCeremony.register(
            options = checkNotNull(creation) { "No registration is pending" },
            rpId = checkNotNull(rpId),
            caller = checkNotNull(caller),
        )
        registration = reg
        return mapOf(
            "credentialId" to Base64Url.encode(reg.credentialId),
            "publicKey" to Base64Url.encode(reg.publicKey),
            "privateKey" to Base64Url.encode(reg.privateKey),
        )
    }

    private fun finishRegistration(): Boolean {
        val reg = checkNotNull(registration) { "No passkey was created" }
        val data = Intent()
        PendingIntentHandler.setCreateCredentialResponse(data, CreatePublicKeyCredentialResponse(reg.responseJson))
        finish(Activity.RESULT_OK, data)
        return true
    }

    private fun list(call: MethodCall): Boolean {
        val request = checkNotNull(beginRequest) { "No listing is pending" }
        val passkeys = call.argument<List<Map<String, Any?>>>("passkeys").orEmpty()
        val passwords = call.argument<List<Map<String, Any?>>>("passwords").orEmpty()
        val web = request.callingAppInfo
            ?.let { runCatching { CredentialCaller.resolve(activity, it) }.getOrNull() } as? CredentialCaller.Web
        val response = BeginGetCredentialResponse.Builder()
        for (option in request.beginGetCredentialOptions) {
            when (option) {
                is BeginGetPublicKeyCredentialOption -> {
                    val options = runCatching { PasskeyRequests.parseAssertion(option.requestJson) }.getOrNull()
                        ?: continue
                    val wanted = options.rpId ?: web?.host ?: continue
                    for (passkey in passkeys) {
                        val credentialId = passkey["credentialId"] as String
                        if (passkey["rpId"] != wanted) continue
                        if (!isAllowed(options, credentialId)) continue
                        response.addCredentialEntry(
                            PublicKeyCredentialEntry.Builder(
                                activity,
                                passkey["userName"] as String,
                                pendingIntent(activity, KIND_PASSKEY, mapOf(EXTRA_CREDENTIAL_ID to credentialId)),
                                option,
                            ).setDisplayName(passkey["displayName"] as String?).build(),
                        )
                    }
                }
                is BeginGetPasswordOption -> for (password in passwords) {
                    val entryId = password["entryId"] as String
                    response.addCredentialEntry(
                        PasswordCredentialEntry.Builder(
                            activity,
                            password["username"] as String,
                            pendingIntent(activity, KIND_PASSWORD, mapOf(EXTRA_ENTRY_ID to entryId)),
                            option,
                        ).setDisplayName(password["title"] as String?).build(),
                    )
                }
            }
        }
        val data = Intent()
        PendingIntentHandler.setBeginGetCredentialResponse(data, response.build())
        finish(Activity.RESULT_OK, data)
        return true
    }

    private fun isAllowed(options: AssertionOptions, credentialId: String): Boolean {
        if (options.allowCredentialIds.isEmpty()) return true
        val id = Base64Url.decode(credentialId)
        return options.allowCredentialIds.any { it.contentEquals(id) }
    }

    private fun assert(call: MethodCall): Boolean {
        val options = checkNotNull(assertion) { "No sign-in is pending" }
        val expectedRpId = checkNotNull(rpId)
        val credentialId = call.argument<String>("credentialId")
        check(credentialId == intent.getStringExtra(EXTRA_CREDENTIAL_ID)) { "A different passkey was chosen" }
        check(call.argument<String>("rpId") == expectedRpId) { "The passkey belongs to another site" }
        val json = PasskeyCeremony.assert(
            options = options,
            rpId = expectedRpId,
            caller = checkNotNull(caller),
            credentialId = Base64Url.decode(credentialId!!),
            userHandle = Base64Url.decode(checkNotNull(call.argument<String>("userHandle"))),
            privateKey = WebAuthn.privateKeyFromPkcs8(
                Base64Url.decode(checkNotNull(call.argument<String>("privateKey"))),
            ),
        )
        val data = Intent()
        PendingIntentHandler.setGetCredentialResponse(data, GetCredentialResponse(PublicKeyCredential(json)))
        finish(Activity.RESULT_OK, data)
        return true
    }

    private fun fillPassword(call: MethodCall): Boolean {
        check(kind == KIND_PASSWORD) { "No password request is pending" }
        val credential = PasswordCredential(
            checkNotNull(call.argument<String>("username")),
            checkNotNull(call.argument<String>("password")),
        )
        val data = Intent()
        PendingIntentHandler.setGetCredentialResponse(data, GetCredentialResponse(credential))
        finish(Activity.RESULT_OK, data)
        return true
    }

    /**
     * Ends the request without a credential. [reason] `excluded` reports the
     * WebAuthn InvalidStateError for a create whose excludeCredentials names
     * a passkey already in the vault.
     */
    private fun cancel(reason: String?) {
        val message = rejection ?: "Cancelled in Vaultly"
        val data = Intent()
        when (kind) {
            KIND_CREATE -> PendingIntentHandler.setCreateCredentialException(
                data,
                when {
                    reason == "excluded" -> CreatePublicKeyCredentialDomException(
                        InvalidStateError(),
                        "A passkey for this account is already in Vaultly",
                    )
                    rejection != null -> CreateCredentialUnknownException(message)
                    else -> CreateCredentialCancellationException(message)
                },
            )
            KIND_PASSKEY, KIND_PASSWORD -> PendingIntentHandler.setGetCredentialException(
                data,
                if (rejection != null) GetCredentialUnknownException(message) else GetCredentialCancellationException(message),
            )
            else -> {
                finish(Activity.RESULT_CANCELED, null)
                return
            }
        }
        finish(Activity.RESULT_OK, data)
    }

    private fun finish(resultCode: Int, data: Intent?) {
        finished = true
        worker.shutdown()
        activity.setResult(resultCode, data)
        activity.finish()
    }
}
