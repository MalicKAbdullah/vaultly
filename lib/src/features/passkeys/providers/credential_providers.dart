import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/passkeys/services/passkey_vault.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

final credentialBridgeProvider = Provider<ICredentialBridge>(
  (_) => const MethodChannelCredentialBridge(),
);

/// The Credential Manager request this launch answers (null on a normal
/// launch). The router sends unlocked sessions to the request screen while
/// it is set; answering it closes the activity, so it is never cleared.
final credentialRequestProvider =
    AsyncNotifierProvider<CredentialRequestNotifier, CredentialRequest?>(
  CredentialRequestNotifier.new,
);

final class CredentialRequestNotifier
    extends AsyncNotifier<CredentialRequest?> {
  @override
  Future<CredentialRequest?> build() =>
      ref.read(credentialBridgeProvider).pendingRequest();

  ICredentialBridge get _bridge => ref.read(credentialBridgeProvider);

  /// Creates the key pair, saves the passkey in the vault, then hands it to
  /// the site. The vault write comes first so a passkey the site accepted
  /// always exists in Vaultly.
  Future<void> savePasskey(PasskeyRegistrationRequest request) async {
    final generated = await _bridge.register();
    final entries = await ref.read(vaultEntriesProvider.future);
    await ref.read(vaultEntriesProvider.notifier).replaceAll(
          PasskeyVault.withRegistration(
            entries,
            request: request,
            generated: generated,
            id: const Uuid().v4(),
            now: ref.read(clockProvider).now(),
          ),
        );
    await _bridge.finishRegistration();
  }

  /// Lists the passkeys and passwords the vault holds for the asker.
  Future<void> answerListing(CredentialListingRequest request) async {
    final entries = await ref.read(vaultEntriesProvider.future);
    await _bridge.list(
      passkeys: [
        for (final e in PasskeyVault.passkeysFor(entries, request.rpIds))
          e.passkey!,
      ],
      passwords: PasskeyVault.passwordsFor(entries, request),
    );
  }

  /// Signs in with the chosen passkey. Returns false when the vault no
  /// longer holds it.
  Future<bool> signIn(PasskeySignInRequest request) async {
    final entries = await ref.read(vaultEntriesProvider.future);
    final entry = PasskeyVault.byCredentialId(entries, request.credentialId);
    if (entry == null || entry.passkey!.rpId != request.rpId) return false;
    await ref.read(vaultEntriesProvider.notifier).replaceAll(
          PasskeyVault.withUse(
              entries, entry.id, ref.read(clockProvider).now()),
        );
    await _bridge.signIn(entry.passkey!);
    return true;
  }

  /// Hands over the chosen password. Returns false when the entry is gone
  /// or has no username or password left.
  Future<bool> fillPassword(PasswordSignInRequest request) async {
    final entries = await ref.read(vaultEntriesProvider.future);
    for (final e in entries) {
      if (e.id == request.entryId &&
          e.username.isNotEmpty &&
          e.password.isNotEmpty) {
        await _bridge.fillPassword(e);
        return true;
      }
    }
    return false;
  }

  Future<void> cancel({bool excluded = false}) =>
      _bridge.cancel(excluded: excluded);
}

/// Whether passkeys are available here and Vaultly is the provider
/// (drives the Settings card).
typedef PasskeyProviderStatus = ({bool supported, bool enabled});

final passkeyProviderStatusProvider =
    FutureProvider<PasskeyProviderStatus>((ref) async {
  final bridge = ref.watch(credentialBridgeProvider);
  final supported = await bridge.isSupported();
  return (supported: supported, enabled: supported && await bridge.isEnabled());
});
