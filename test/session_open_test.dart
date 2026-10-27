import 'dart:async';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/core/background_worker.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/biometric_key_vault.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import 'fakes/fakes.dart';

void main() {
  const password = 'correct horse';
  final entries = [
    makeEntry(id: 'a', title: 'GitHub'),
    makeEntry(id: 'b', title: 'Email'),
  ];

  late FakeSecureStorage storage;
  late InMemoryFileStore fileStore;
  late FakeBiometricAuthenticator biometrics;
  late UnlockSuccess setup;

  MasterAuthService auth() => MasterAuthService(
        storage: storage,
        keyDerivation: FakeKeyDerivation(),
        cipher: const CipherService(),
        fileStore: fileStore,
        clock: FixedClock(DateTime(2026, 7, 5)),
      );

  setUp(() async {
    storage = FakeSecureStorage();
    fileStore = InMemoryFileStore();
    biometrics = FakeBiometricAuthenticator();
    setup = await auth().setup(password);
    await VaultRepository(
      file: VaultFile(fileStore),
      cipher: const CipherService(),
      worker: const InlineWorker(),
    ).save(entries, setup.key, setup.salt);
    storage.reads.clear();
    fileStore.readCount = 0;
  });

  ProviderContainer launch() {
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        fileStoreProvider.overrideWithValue(fileStore),
        keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
        backgroundWorkerProvider.overrideWithValue(const IsolateWorker()),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
        systemClipboardProvider.overrideWithValue(FakeClipboard()),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
        biometricKeyVaultProvider.overrideWithValue(
          SecureStorageKeyVault(storage: storage, authenticator: biometrics),
        ),
      ],
    );
    addTearDown(container.dispose);
    // What the router listens to at launch.
    container
      ..listen(sessionProvider, (_, __) {})
      ..listen(setupOnboardingSeenProvider, (_, __) {});
    return container;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  SessionNotifier session(ProviderContainer c) =>
      c.read(sessionProvider.notifier);

  test(
      'a locked launch reads the verifier first and never the onboarding '
      'flag', () async {
    final c = launch();
    await settle();
    expect(c.read(sessionProvider), AuthStatus.locked);
    expect(storage.reads.first, VaultKeyKeys.verifier);
    expect(
      storage.reads,
      containsAll([VaultKeyKeys.lockoutUntil, VaultKeyKeys.biometricEnabled]),
    );
    expect(storage.reads, isNot(contains(VaultKeyKeys.onboardingDone)));
    // The vault file is read ahead while locked.
    expect(fileStore.readCount, 1);
  });

  test('a first launch reads the onboarding flag once setup is needed',
      () async {
    storage = FakeSecureStorage();
    final c = launch();
    await settle();
    expect(c.read(sessionProvider), AuthStatus.needsSetup);
    expect(storage.reads, contains(VaultKeyKeys.onboardingDone));
  });

  test('password unlock: the vault is decrypted before the session flips',
      () async {
    final c = launch();
    await settle();
    AsyncValue<List<VaultEntry>>? atUnlock;
    c.listen(sessionProvider, (_, next) {
      if (next == AuthStatus.unlocked) atUnlock = c.read(vaultEntriesProvider);
    });
    await session(c).unlock(password);

    expect(atUnlock, isA<AsyncData<List<VaultEntry>>>());
    expect(atUnlock!.value, entries);
  });

  test('biometric unlock: the vault file is read before the prompt', () async {
    final service = BiometricUnlockService(
      storage: storage,
      authenticator: biometrics,
      vault: SecureStorageKeyVault(storage: storage, authenticator: biometrics),
    );
    await service.enable(Uint8List.fromList(setup.key));
    final c = launch();
    await settle();
    late int fileReadsAtPrompt;
    biometrics.onPrompt = () => fileReadsAtPrompt = fileStore.readCount;
    AsyncValue<List<VaultEntry>>? atUnlock;
    c.listen(sessionProvider, (_, next) {
      if (next == AuthStatus.unlocked) atUnlock = c.read(vaultEntriesProvider);
    });

    expect(await session(c).unlockWithBiometrics(), isTrue);
    expect(fileReadsAtPrompt, 1);
    expect(fileStore.readCount, 1);
    expect(atUnlock!.value, entries);
  });

  test('a vault that fails to decrypt is an error, and nothing overwrites it',
      () async {
    final tampered = Uint8List.fromList(fileStore.bytes!);
    tampered[tampered.length - 1] ^= 0xff;
    fileStore.bytes = tampered;
    final c = launch();
    await settle();

    await session(c).unlock(password);
    expect(c.read(sessionProvider), AuthStatus.unlocked);
    expect(c.read(vaultEntriesProvider).hasError, isTrue);

    await expectLater(
      c.read(vaultEntriesProvider.notifier).delete('a'),
      throwsA(anything),
    );
    expect(fileStore.bytes, tampered);
  });

  test('a lock during a save reads the saved file for the next unlock',
      () async {
    final c = launch();
    await settle();
    await session(c).unlock(password);
    c.listen(vaultEntriesProvider, (_, __) {});

    final gate = Completer<void>();
    fileStore.writeGate = gate.future;
    final saving = c.read(vaultEntriesProvider.notifier).delete('a');
    await settle();
    session(c).lock();
    gate.complete();
    await saving;
    await settle();

    await session(c).unlock(password);
    expect(c.read(vaultEntriesProvider).requireValue.map((e) => e.id), ['b']);
  });

  test('a file re-keyed after the read-ahead is read again before opening',
      () async {
    final c = launch();
    await settle();
    // Locked, with the old file already read ahead. Re-keying while locked
    // is what a recovery reset does; a password change takes the same
    // write path without the recovery key's Argon2id.
    final changed =
        await c.read(masterAuthServiceProvider).changeMasterPassword(
              oldPassword: password,
              newPassword: 'a brand new password',
            );
    expect(changed, isA<UnlockSuccess>());
    expect(fileStore.readCount, 2);

    expect(
      await session(c).unlock('a brand new password'),
      isA<UnlockSuccess>(),
    );
    c.listen(vaultEntriesProvider, (_, __) {});
    expect(c.read(vaultEntriesProvider).requireValue, entries);
    expect(fileStore.readCount, 3);
  });

  test('the unlock prerequisites started at launch are handed over once',
      () async {
    final c = launch();
    await settle();
    final first = session(c).unlockPrerequisites();
    final readsBefore = storage.reads.length;
    expect(await first.biometricEnabled, isFalse);
    expect(await first.cooldown, Duration.zero);
    expect(storage.reads.length, readsBefore);

    // A second screen in the same lock reads afresh.
    final second = session(c).unlockPrerequisites();
    await second.cooldown;
    expect(storage.reads.length, greaterThan(readsBefore));
  });
}
