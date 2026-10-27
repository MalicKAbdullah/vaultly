import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/passkeys/models/passkey_credential.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Scripted Credential Manager bridge; records what Flutter handed back,
/// in order, in [calls].
final class FakeCredentialBridge implements ICredentialBridge {
  FakeCredentialBridge({this.request, this.supported = true});

  CredentialRequest? request;
  bool supported;
  bool enabled = false;

  final List<String> calls = [];
  List<PasskeyCredential>? listedPasskeys;
  List<VaultEntry>? listedPasswords;
  PasskeyCredential? signedWith;
  VaultEntry? filledWith;
  bool? cancelledExcluded;

  static const GeneratedPasskey generated = (
    credentialId: 'bmV3LWNyZWQ',
    publicKey: 'bmV3LXB1Yg',
    privateKey: 'bmV3LXByaXY',
  );

  @override
  Future<CredentialRequest?> pendingRequest() async => request;

  @override
  Future<GeneratedPasskey> register() async {
    calls.add('register');
    return generated;
  }

  @override
  Future<void> finishRegistration() async => calls.add('finishRegistration');

  @override
  Future<void> list({
    required List<PasskeyCredential> passkeys,
    required List<VaultEntry> passwords,
  }) async {
    calls.add('list');
    listedPasskeys = passkeys;
    listedPasswords = passwords;
  }

  @override
  Future<void> signIn(PasskeyCredential passkey) async {
    calls.add('signIn');
    signedWith = passkey;
  }

  @override
  Future<void> fillPassword(VaultEntry entry) async {
    calls.add('fillPassword');
    filledWith = entry;
  }

  @override
  Future<void> cancel({bool excluded = false}) async {
    calls.add('cancel');
    cancelledExcluded = excluded;
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> openSettings() async => true;
}
