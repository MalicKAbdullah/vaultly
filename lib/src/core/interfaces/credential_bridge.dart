import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultkey/src/features/passkeys/models/passkey_credential.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// A Credential Manager request (Android 14+) this launch was opened to
/// answer. The Kotlin side has already checked who is asking: a website's
/// origin against the RP id, an app against the site's Digital Asset Links.
@immutable
sealed class CredentialRequest {
  const CredentialRequest();
}

/// A website or app wants to save a new passkey in Vaultly.
final class PasskeyRegistrationRequest extends CredentialRequest {
  const PasskeyRegistrationRequest({
    required this.rpId,
    required this.rpName,
    required this.userName,
    required this.userDisplayName,
    required this.userHandle,
    required this.excludeCredentialIds,
    required this.caller,
  });

  final String rpId;
  final String rpName;
  final String userName;
  final String userDisplayName;
  final String userHandle;

  /// Passkeys the site already knows about for this account; if Vaultly
  /// holds one of them, no second passkey is made.
  final List<String> excludeCredentialIds;

  /// The website host or app package asking.
  final String caller;
}

/// The user tapped "Unlock Vaultly" in the sign-in sheet: list what the
/// vault holds for the asking site or app.
final class CredentialListingRequest extends CredentialRequest {
  const CredentialListingRequest({
    required this.rpIds,
    required this.wantsPasswords,
    this.domain,
    this.package,
  });

  /// Sites whose passkeys were asked for.
  final List<String> rpIds;

  /// Whether saved passwords were asked for too.
  final bool wantsPasswords;

  /// Website asking (browser callers).
  final String? domain;

  /// App asking (native callers).
  final String? package;
}

/// The user picked one of Vaultly's passkeys in the sign-in sheet.
final class PasskeySignInRequest extends CredentialRequest {
  const PasskeySignInRequest({
    required this.credentialId,
    required this.rpId,
    required this.caller,
  });

  final String credentialId;
  final String rpId;
  final String caller;
}

/// The user picked one of Vaultly's passwords in the sign-in sheet.
final class PasswordSignInRequest extends CredentialRequest {
  const PasswordSignInRequest({required this.entryId});

  final String entryId;
}

/// A request Vaultly refuses (wrong site for the origin, unknown browser,
/// unsupported key type…). [message] says why.
final class RejectedCredentialRequest extends CredentialRequest {
  const RejectedCredentialRequest(this.message);

  final String message;
}

/// A freshly generated passkey key pair, still to be saved in the vault.
typedef GeneratedPasskey = ({
  String credentialId,
  String publicKey,
  String privateKey,
});

/// Platform seam for Credential Manager. The real implementation talks to
/// the Android activity over a MethodChannel; tests use a fake.
abstract interface class ICredentialBridge {
  /// The request this launch answers, or null on a normal launch.
  Future<CredentialRequest?> pendingRequest();

  /// Generates the key pair for a [PasskeyRegistrationRequest].
  Future<GeneratedPasskey> register();

  /// Hands the new passkey to the website or app; call once it is saved.
  Future<void> finishRegistration();

  /// Answers a [CredentialListingRequest] with what the vault holds.
  Future<void> list({
    required List<PasskeyCredential> passkeys,
    required List<VaultEntry> passwords,
  });

  /// Signs the [PasskeySignInRequest] challenge with [passkey].
  Future<void> signIn(PasskeyCredential passkey);

  /// Answers a [PasswordSignInRequest] with [entry]'s credentials.
  Future<void> fillPassword(VaultEntry entry);

  /// Ends the request without a credential. [excluded] reports that the
  /// vault already holds a passkey the site listed as excluded.
  Future<void> cancel({bool excluded = false});

  /// Whether this device has Credential Manager providers (Android 14+).
  Future<bool> isSupported();

  /// Whether Vaultly is turned on as a passkey provider.
  Future<bool> isEnabled();

  /// Opens the system screen where providers are turned on.
  Future<bool> openSettings();
}

final class MethodChannelCredentialBridge implements ICredentialBridge {
  const MethodChannelCredentialBridge();

  static const MethodChannel _channel = MethodChannel('vaultly/credentials');

  @override
  Future<CredentialRequest?> pendingRequest() async {
    final Map<Object?, Object?>? map;
    try {
      map = await _channel.invokeMethod('getPendingRequest');
    } on MissingPluginException {
      return null; // Not on Android.
    }
    if (map == null) return null;
    return switch (map['kind']) {
      'register' => PasskeyRegistrationRequest(
          rpId: map['rpId']! as String,
          rpName: map['rpName']! as String,
          userName: map['userName']! as String,
          userDisplayName: map['userDisplayName']! as String,
          userHandle: map['userHandle']! as String,
          excludeCredentialIds:
              (map['excludeCredentialIds']! as List<Object?>).cast<String>(),
          caller: map['caller']! as String,
        ),
      'list' => CredentialListingRequest(
          rpIds: (map['rpIds']! as List<Object?>).cast<String>(),
          wantsPasswords: map['passwords']! as bool,
          domain: map['domain'] as String?,
          package: map['package'] as String?,
        ),
      'passkey' => PasskeySignInRequest(
          credentialId: map['credentialId']! as String,
          rpId: map['rpId']! as String,
          caller: map['caller']! as String,
        ),
      'password' => PasswordSignInRequest(entryId: map['entryId']! as String),
      'invalid' => RejectedCredentialRequest(map['message']! as String),
      final kind => throw StateError('Unknown credential request $kind'),
    };
  }

  @override
  Future<GeneratedPasskey> register() async {
    final map = (await _channel.invokeMapMethod<String, String>('register'))!;
    return (
      credentialId: map['credentialId']!,
      publicKey: map['publicKey']!,
      privateKey: map['privateKey']!,
    );
  }

  @override
  Future<void> finishRegistration() =>
      _channel.invokeMethod<bool>('finishRegistration');

  @override
  Future<void> list({
    required List<PasskeyCredential> passkeys,
    required List<VaultEntry> passwords,
  }) =>
      _channel.invokeMethod<bool>('list', {
        'passkeys': [
          for (final p in passkeys)
            {
              'credentialId': p.credentialId,
              'rpId': p.rpId,
              'userName': p.userName,
              'displayName': p.userDisplayName,
            },
        ],
        'passwords': [
          for (final e in passwords)
            {'entryId': e.id, 'username': e.username, 'title': e.title},
        ],
      });

  @override
  Future<void> signIn(PasskeyCredential passkey) =>
      _channel.invokeMethod<bool>('assert', {
        'credentialId': passkey.credentialId,
        'rpId': passkey.rpId,
        'userHandle': passkey.userHandle,
        'privateKey': passkey.privateKey,
      });

  @override
  Future<void> fillPassword(VaultEntry entry) =>
      _channel.invokeMethod<bool>('fillPassword', {
        'username': entry.username,
        'password': entry.password,
      });

  @override
  Future<void> cancel({bool excluded = false}) =>
      _channel.invokeMethod<void>('cancel', {
        if (excluded) 'reason': 'excluded',
      });

  @override
  Future<bool> isSupported() => _status('isSupported');

  @override
  Future<bool> isEnabled() => _status('isEnabled');

  @override
  Future<bool> openSettings() => _status('openSettings');

  Future<bool> _status(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false; // Not on Android.
    }
  }
}
