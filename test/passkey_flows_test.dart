import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/passkeys/models/passkey_credential.dart';
import 'package:vaultkey/src/features/passkeys/providers/credential_providers.dart';
import 'package:vaultkey/src/features/passkeys/services/passkey_vault.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import 'fakes/fake_credential_bridge.dart';
import 'fakes/fakes.dart';
import 'fakes/passkey_fixtures.dart';
import 'widgets/helpers.dart';

/// Records vault writes into the bridge's call log, so tests can assert the
/// vault is written before the site is answered.
class _RecordingVault extends FakeVaultNotifier {
  _RecordingVault(super.seed, this.calls);

  final List<String> calls;

  @override
  Future<void> commit(List<VaultEntry> entries) async {
    calls.add('commit');
    await super.commit(entries);
  }
}

void main() {
  final now = DateTime(2026, 10, 27, 9);
  late FakeCredentialBridge bridge;

  ProviderContainer container(List<VaultEntry> seed) {
    bridge = FakeCredentialBridge();
    final c = ProviderContainer(
      overrides: [
        vaultEntriesProvider.overrideWith(
          () => _RecordingVault(seed, bridge.calls),
        ),
        credentialBridgeProvider.overrideWithValue(bridge),
        clockProvider.overrideWithValue(FixedClock(now)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  CredentialRequestNotifier notifier(ProviderContainer c) =>
      c.read(credentialRequestProvider.notifier);

  group('saving a passkey', () {
    test('stores the generated key in the vault before answering the site',
        () async {
      final c = container([makeEntry()]);
      await notifier(c).savePasskey(registration);

      expect(bridge.calls, ['register', 'commit', 'finishRegistration']);
      final saved = c.read(vaultEntriesProvider).requireValue.last;
      expect(saved.category, EntryCategory.passkey);
      expect(saved.title, 'WebAuthn.io');
      expect(saved.username, 'alice');
      expect(saved.password, isEmpty);
      expect(saved.createdAt, now);
      expect(
        saved.passkey,
        const PasskeyCredential(
          rpId: 'webauthn.io',
          rpName: 'WebAuthn.io',
          userName: 'alice',
          userDisplayName: 'Alice',
          credentialId: 'bmV3LWNyZWQ',
          userHandle: 'dXNlci00Mg',
          publicKey: 'bmV3LXB1Yg',
          privateKey: 'bmV3LXByaXY',
        ),
      );
    });

    test('replaces the passkey already saved for the same account', () async {
      final c = container([
        storedPasskey(favorite: true),
        storedPasskey(id: 'other', userHandle: 'b3RoZXI'),
      ]);
      await notifier(c).savePasskey(registration);

      final entries = c.read(vaultEntriesProvider).requireValue;
      expect(entries.map((e) => e.id), isNot(contains('pk-1')));
      expect(entries.where((e) => e.id == 'other'), hasLength(1));
      expect(entries.last.passkey!.credentialId, 'bmV3LWNyZWQ');
      expect(entries.last.favorite, isTrue);
    });

    test('an excluded credential already in the vault blocks a new one', () {
      final entries = [storedPasskey()];
      expect(PasskeyVault.holdsExcluded(entries, registration), isFalse);
      const excluding = PasskeyRegistrationRequest(
        rpId: 'webauthn.io',
        rpName: 'WebAuthn.io',
        userName: 'alice',
        userDisplayName: 'Alice',
        userHandle: 'bmV3',
        excludeCredentialIds: ['c3RvcmVk'],
        caller: 'webauthn.io',
      );
      expect(PasskeyVault.holdsExcluded(entries, excluding), isTrue);
    });
  });

  group('signing in', () {
    final vault = [
      storedPasskey(),
      storedPasskey(id: 'gh', rpId: 'github.com', credentialId: 'Z2g'),
      makeEntry(
        id: 'mail',
        title: 'Mail',
        username: 'jo',
        password: 'pw',
        url: 'mail.example.com',
      ),
      makeEntry(
        id: 'nouser',
        title: 'Mail PIN',
        username: '',
        password: '1234',
        url: 'mail.example.com',
      ),
    ];

    test('the listing offers only the asked-for site passkeys', () async {
      final c = container(vault);
      await notifier(c).answerListing(
        const CredentialListingRequest(
          rpIds: ['github.com'],
          wantsPasswords: false,
        ),
      );
      expect(bridge.listedPasskeys!.map((p) => p.rpId), ['github.com']);
      expect(bridge.listedPasswords, isEmpty);
    });

    test('the listing offers matching logins that have both fields', () async {
      final c = container(vault);
      await notifier(c).answerListing(
        const CredentialListingRequest(
          rpIds: [],
          wantsPasswords: true,
          domain: 'mail.example.com',
        ),
      );
      expect(bridge.listedPasskeys, isEmpty);
      expect(bridge.listedPasswords!.map((e) => e.id), ['mail']);
    });

    test('a passkey sign-in signs with the stored key and stamps its use',
        () async {
      final c = container(vault);
      final answered = await notifier(c).signIn(
        const PasskeySignInRequest(
          credentialId: 'c3RvcmVk',
          rpId: 'webauthn.io',
          caller: 'webauthn.io',
        ),
      );
      expect(answered, isTrue);
      expect(bridge.signedWith!.privateKey, 'cHJpdg');
      final used = c
          .read(vaultEntriesProvider)
          .requireValue
          .firstWhere((e) => e.id == 'pk-1');
      expect(used.passkey!.lastUsedAt, now);
    });

    test('a passkey that is gone or for another site is not used', () async {
      final c = container(vault);
      expect(
        await notifier(c).signIn(
          const PasskeySignInRequest(
            credentialId: 'Z29uZQ',
            rpId: 'webauthn.io',
            caller: 'webauthn.io',
          ),
        ),
        isFalse,
      );
      expect(
        await notifier(c).signIn(
          const PasskeySignInRequest(
            credentialId: 'Z2g',
            rpId: 'webauthn.io',
            caller: 'webauthn.io',
          ),
        ),
        isFalse,
      );
      expect(bridge.calls, isNot(contains('signIn')));
    });

    test('a password sign-in hands over the chosen login', () async {
      final c = container(vault);
      expect(
        await notifier(c)
            .fillPassword(const PasswordSignInRequest(entryId: 'mail')),
        isTrue,
      );
      expect(bridge.filledWith!.password, 'pw');
      expect(
        await notifier(c)
            .fillPassword(const PasswordSignInRequest(entryId: 'deleted')),
        isFalse,
      );
    });
  });
}
