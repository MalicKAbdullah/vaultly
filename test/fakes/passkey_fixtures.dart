import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/passkeys/models/passkey_credential.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

VaultEntry storedPasskey({
  String id = 'pk-1',
  String rpId = 'webauthn.io',
  String credentialId = 'c3RvcmVk',
  String userHandle = 'dXNlci00Mg',
  bool favorite = false,
}) =>
    VaultEntry(
      id: id,
      title: rpId,
      username: 'alice',
      url: rpId,
      category: EntryCategory.passkey,
      favorite: favorite,
      passkey: PasskeyCredential(
        rpId: rpId,
        rpName: rpId,
        userName: 'alice',
        userDisplayName: 'Alice',
        credentialId: credentialId,
        userHandle: userHandle,
        publicKey: 'cHVi',
        privateKey: 'cHJpdg',
      ),
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      passwordChangedAt: DateTime(2026, 9, 1),
    );

const registration = PasskeyRegistrationRequest(
  rpId: 'webauthn.io',
  rpName: 'WebAuthn.io',
  userName: 'alice',
  userDisplayName: 'Alice',
  userHandle: 'dXNlci00Mg',
  excludeCredentialIds: [],
  caller: 'webauthn.io',
);
