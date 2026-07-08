import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';

import 'fakes/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late InMemoryFileStore fileStore;
  late FixedClock clock;
  late MasterAuthService auth;

  const goodPassword = 'correct horse';
  const otherPassword = 'wrong stapler';

  setUp(() {
    storage = FakeSecureStorage();
    fileStore = InMemoryFileStore();
    clock = FixedClock(DateTime(2026, 7, 5, 12));
    auth = MasterAuthService(
      storage: storage,
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
      fileStore: fileStore,
      clock: clock,
    );
  });

  group('setup and unlock', () {
    test('hasMasterPassword flips after setup', () async {
      expect(await auth.hasMasterPassword(), isFalse);
      await auth.setup(goodPassword);
      expect(await auth.hasMasterPassword(), isTrue);
    });

    test('setup stores salt and verifier but never the password', () async {
      await auth.setup(goodPassword);
      expect(storage.store[VaultKeyKeys.salt], isNotNull);
      expect(storage.store[VaultKeyKeys.verifier], isNotNull);
      expect(
        storage.store.values.any((v) => v.contains(goodPassword)),
        isFalse,
      );
    });

    test('correct password unlocks with the same key as setup', () async {
      final setup = await auth.setup(goodPassword);
      final result = await auth.unlock(goodPassword);
      expect(result, isA<UnlockSuccess>());
      expect((result as UnlockSuccess).key, setup.key);
    });

    test('wrong password fails with attempt count', () async {
      await auth.setup(goodPassword);
      final result = await auth.unlock(otherPassword);
      expect(result, isA<UnlockWrongPassword>());
      expect((result as UnlockWrongPassword).failedAttempts, 1);
      expect(result.cooldown, isNull);
    });

    test('successful unlock resets the attempt counter', () async {
      await auth.setup(goodPassword);
      await auth.unlock('bad-one-1');
      await auth.unlock('bad-one-2');
      await auth.unlock(goodPassword);
      final result = await auth.unlock('bad-one-3');
      expect((result as UnlockWrongPassword).failedAttempts, 1);
    });
  });

  group('cooldown', () {
    Future<void> failTimes(int n) async {
      for (var i = 0; i < n; i++) {
        await auth.unlock('nope nope $i');
      }
    }

    test('5th failure triggers a 30s cooldown', () async {
      await auth.setup(goodPassword);
      await failTimes(4);
      final result = await auth.unlock('nope again');
      final wrong = result as UnlockWrongPassword;
      expect(wrong.failedAttempts, 5);
      expect(wrong.cooldown, const Duration(seconds: 30));
    });

    test('even the correct password is rejected while cooling down', () async {
      await auth.setup(goodPassword);
      await failTimes(5);
      final result = await auth.unlock(goodPassword);
      expect(result, isA<UnlockCoolingDown>());
      expect(
        (result as UnlockCoolingDown).remaining,
        const Duration(seconds: 30),
      );
    });

    test('cooldown expires and escalates on the next failure', () async {
      await auth.setup(goodPassword);
      await failTimes(5);
      clock.advance(const Duration(seconds: 31));
      final sixth = await auth.unlock('still wrong');
      expect((sixth as UnlockWrongPassword).failedAttempts, 6);
      expect(sixth.cooldown, const Duration(seconds: 60));
    });

    test('correct password works after the cooldown expires', () async {
      await auth.setup(goodPassword);
      await failTimes(5);
      clock.advance(const Duration(minutes: 1));
      expect(await auth.unlock(goodPassword), isA<UnlockSuccess>());
    });

    test('escalation doubles and caps at 15 minutes', () {
      expect(MasterAuthService.cooldownFor(4), Duration.zero);
      expect(
        MasterAuthService.cooldownFor(5),
        const Duration(seconds: 30),
      );
      expect(
        MasterAuthService.cooldownFor(6),
        const Duration(seconds: 60),
      );
      expect(
        MasterAuthService.cooldownFor(8),
        const Duration(seconds: 240),
      );
      expect(MasterAuthService.cooldownFor(10), const Duration(minutes: 15));
      expect(MasterAuthService.cooldownFor(50), const Duration(minutes: 15));
    });

    test('cooldown persists across service restarts', () async {
      await auth.setup(goodPassword);
      await failTimes(5);
      final restarted = MasterAuthService(
        storage: storage,
        keyDerivation: FakeKeyDerivation(),
        cipher: const CipherService(),
        fileStore: fileStore,
        clock: clock,
      );
      expect(await restarted.unlock(goodPassword), isA<UnlockCoolingDown>());
    });
  });

  group('change master password', () {
    VaultRepository repo() =>
        VaultRepository(fileStore: fileStore, cipher: const CipherService());

    test('re-encrypts the vault: old key and old password stop working',
        () async {
      final setup = await auth.setup(goodPassword);
      final entries = [makeEntry(id: 'a'), makeEntry(id: 'b', title: 'Two')];
      await repo().save(entries, setup.key, setup.salt);

      final changed = await auth.changeMasterPassword(
        oldPassword: goodPassword,
        newPassword: 'brand new secret',
      );
      expect(changed, isA<UnlockSuccess>());
      final newKey = (changed as UnlockSuccess).key;

      // Data decrypts with the new key.
      expect(await repo().load(newKey), entries);

      // New password unlocks; the old one no longer does.
      expect(await auth.unlock('brand new secret'), isA<UnlockSuccess>());
      expect(await auth.unlock(goodPassword), isA<UnlockWrongPassword>());

      // The old key can no longer decrypt the vault file.
      expect(() => repo().load(setup.key), throwsA(anything));
    });

    test('rotates the salt', () async {
      await auth.setup(goodPassword);
      final saltBefore = storage.store[VaultKeyKeys.salt];
      await auth.changeMasterPassword(
        oldPassword: goodPassword,
        newPassword: 'brand new secret',
      );
      expect(storage.store[VaultKeyKeys.salt], isNot(saltBefore));
    });

    test('drops any stored biometric key', () async {
      await auth.setup(goodPassword);
      storage.store[VaultKeyKeys.biometricKey] = 'wrapped-old-key';
      storage.store[VaultKeyKeys.biometricEnabled] = 'true';
      await auth.changeMasterPassword(
        oldPassword: goodPassword,
        newPassword: 'brand new secret',
      );
      expect(storage.store[VaultKeyKeys.biometricKey], isNull);
      expect(storage.store[VaultKeyKeys.biometricEnabled], isNull);
    });

    test('wrong old password leaves everything unchanged', () async {
      final setup = await auth.setup(goodPassword);
      await repo().save([makeEntry(id: 'a')], setup.key, setup.salt);
      final bytesBefore = fileStore.bytes;

      final result = await auth.changeMasterPassword(
        oldPassword: otherPassword,
        newPassword: 'brand new secret',
      );
      expect(result, isA<UnlockWrongPassword>());
      expect(fileStore.bytes, bytesBefore);
      expect(await auth.unlock(goodPassword), isA<UnlockSuccess>());
    });

    test('works with an empty vault', () async {
      await auth.setup(goodPassword);
      final result = await auth.changeMasterPassword(
        oldPassword: goodPassword,
        newPassword: 'brand new secret',
      );
      expect(result, isA<UnlockSuccess>());
    });
  });

  group('erase', () {
    test('eraseAll wipes the vault file and every Vaultly storage key',
        () async {
      final setup = await auth.setup(goodPassword);
      await VaultRepository(
        fileStore: fileStore,
        cipher: const CipherService(),
      ).save([makeEntry(id: 'a')], setup.key, setup.salt);
      storage.store[VaultKeyKeys.backupPassphrase] = 'secret';

      await auth.eraseAll();
      expect(fileStore.bytes, isNull);
      expect(storage.store, isEmpty);
      expect(await auth.hasMasterPassword(), isFalse);
    });
  });
}
