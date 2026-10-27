package dev.abdullah.vaultkey

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Answers one Credential Manager request (see [CredentialRequestSession]).
 *
 * It runs its own Flutter engine, so the vault always starts locked here:
 * every passkey created or used went through a fresh unlock, which is what
 * lets the authenticator data claim user verification (UV).
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class CredentialProviderActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, BiometricKeyVault.CHANNEL)
            .setMethodCallHandler(BiometricKeyVault(this))
        MethodChannel(messenger, CredentialChannel.CHANNEL)
            .setMethodCallHandler(CredentialChannel(this, CredentialRequestSession(this)))
    }
}
