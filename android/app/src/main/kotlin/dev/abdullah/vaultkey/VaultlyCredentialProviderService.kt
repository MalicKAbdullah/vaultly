package dev.abdullah.vaultkey

import android.os.Build
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.provider.AuthenticationAction
import androidx.credentials.provider.BeginCreateCredentialRequest
import androidx.credentials.provider.BeginCreateCredentialResponse
import androidx.credentials.provider.BeginCreatePublicKeyCredentialRequest
import androidx.credentials.provider.BeginGetCredentialRequest
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPasswordOption
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.CreateEntry
import androidx.credentials.provider.CredentialProviderService
import androidx.credentials.provider.ProviderClearCredentialStateRequest

/**
 * Vaultly as an Android 14+ Credential Manager provider for passkeys and
 * saved passwords.
 *
 * The service never sees the vault: it is encrypted and only Flutter holds
 * the key after an unlock. So every answer here is a pointer into
 * [CredentialProviderActivity] — "Save in Vaultly" for a new passkey, and
 * "Unlock Vaultly" for sign-in, which unlocks and replies with the matching
 * credentials.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class VaultlyCredentialProviderService : CredentialProviderService() {

    override fun onBeginCreateCredentialRequest(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>,
    ) {
        // Saving new passwords through Credential Manager is not offered;
        // only passkeys are created here.
        if (request !is BeginCreatePublicKeyCredentialRequest) {
            callback.onResult(BeginCreateCredentialResponse.Builder().build())
            return
        }
        val entry = CreateEntry.Builder(
            getString(R.string.credential_account_name),
            CredentialRequestSession.pendingIntent(this, CredentialRequestSession.KIND_CREATE),
        ).setDescription(getString(R.string.credential_create_description)).build()
        callback.onResult(BeginCreateCredentialResponse.Builder().addCreateEntry(entry).build())
    }

    override fun onBeginGetCredentialRequest(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>,
    ) {
        val answerable = request.beginGetCredentialOptions.any {
            it is BeginGetPublicKeyCredentialOption || it is BeginGetPasswordOption
        }
        val response = BeginGetCredentialResponse.Builder()
        if (answerable) {
            response.addAuthenticationAction(
                AuthenticationAction(
                    getString(R.string.credential_unlock_action),
                    CredentialRequestSession.pendingIntent(this, CredentialRequestSession.KIND_UNLOCK),
                ),
            )
        }
        callback.onResult(response.build())
    }

    override fun onClearCredentialStateRequest(
        request: ProviderClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, ClearCredentialException>,
    ) {
        // Vaultly keeps no sign-in session state to clear.
        callback.onResult(null)
    }
}
