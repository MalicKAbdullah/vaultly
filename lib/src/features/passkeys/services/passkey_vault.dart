import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/autofill/services/autofill_matcher.dart';
import 'package:vaultkey/src/features/passkeys/models/passkey_credential.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Pure vault operations behind the Credential Manager flows: which entries
/// answer a request, and the vault after a passkey is saved or used.
abstract final class PasskeyVault {
  /// Passkey entries for any of [rpIds].
  static List<VaultEntry> passkeysFor(
    List<VaultEntry> entries,
    Iterable<String> rpIds,
  ) {
    final wanted = rpIds.toSet();
    return [
      for (final e in entries)
        if (e.passkey != null && wanted.contains(e.passkey!.rpId)) e,
    ];
  }

  /// The passkey entry with [credentialId], if the vault still holds it.
  static VaultEntry? byCredentialId(
    List<VaultEntry> entries,
    String credentialId,
  ) {
    for (final e in entries) {
      if (e.passkey?.credentialId == credentialId) return e;
    }
    return null;
  }

  /// Whether the vault holds a passkey the site listed in
  /// `excludeCredentials` — then no second passkey may be made.
  static bool holdsExcluded(
    List<VaultEntry> entries,
    PasskeyRegistrationRequest request,
  ) =>
      entries.any(
        (e) =>
            e.passkey != null &&
            e.passkey!.rpId == request.rpId &&
            request.excludeCredentialIds.contains(e.passkey!.credentialId),
      );

  /// The passkey already saved for the same account (RP id and user
  /// handle). A new registration replaces it, as WebAuthn authenticators
  /// do for discoverable credentials.
  static VaultEntry? sameAccount(
    List<VaultEntry> entries,
    PasskeyRegistrationRequest request,
  ) {
    for (final e in entries) {
      final passkey = e.passkey;
      if (passkey != null &&
          passkey.rpId == request.rpId &&
          passkey.userHandle == request.userHandle) {
        return e;
      }
    }
    return null;
  }

  /// Saved logins that match the asking site or app and can be handed
  /// over (both a username and a password).
  static List<VaultEntry> passwordsFor(
    List<VaultEntry> entries,
    CredentialListingRequest request,
  ) {
    if (!request.wantsPasswords) return const [];
    final candidates = [
      for (final e in entries)
        if (e.passkey == null && e.username.isNotEmpty && e.password.isNotEmpty)
          e,
    ];
    return AutofillMatcher.rank(
      candidates,
      AutofillFillRequest(domain: request.domain, package: request.package),
    );
  }

  /// The vault with the new passkey added, replacing any passkey for the
  /// same account.
  static List<VaultEntry> withRegistration(
    List<VaultEntry> entries, {
    required PasskeyRegistrationRequest request,
    required GeneratedPasskey generated,
    required String id,
    required DateTime now,
  }) {
    final replaced = sameAccount(entries, request);
    final entry = VaultEntry(
      id: id,
      title: request.rpName,
      username: request.userName,
      url: request.rpId,
      category: EntryCategory.passkey,
      favorite: replaced?.favorite ?? false,
      passkey: PasskeyCredential(
        rpId: request.rpId,
        rpName: request.rpName,
        userName: request.userName,
        userDisplayName: request.userDisplayName,
        credentialId: generated.credentialId,
        userHandle: request.userHandle,
        publicKey: generated.publicKey,
        privateKey: generated.privateKey,
      ),
      createdAt: now,
      updatedAt: now,
      passwordChangedAt: now,
    );
    return [
      for (final e in entries)
        if (e.id != replaced?.id) e,
      entry,
    ];
  }

  /// The vault with [entryId]'s passkey stamped as used at [now].
  static List<VaultEntry> withUse(
    List<VaultEntry> entries,
    String entryId,
    DateTime now,
  ) =>
      [
        for (final e in entries)
          if (e.id == entryId)
            e.copyWith(passkey: e.passkey!.usedAt(now))
          else
            e,
      ];
}
