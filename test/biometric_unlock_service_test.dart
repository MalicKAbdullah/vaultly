import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/interfaces/biometric_key_vault.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';

import 'fakes/fakes.dart';

/// Scripted hardware-bound vault: holds at most one key, and every store or
/// release "prompts" by consulting [promptSucceeds].
final class _FakeHardwareVault implements IBiometricKeyVault {
  Uint8List? held;
  bool invalidated = false;
  bool promptSucceeds = true;
  int prompts = 0;

  @override
  bool get hardwareBound => true;

  @override
  Future<bool> store(Uint8List key, {required String reason}) async {
    prompts++;
    if (!promptSucceeds) return false;
    held = Uint8List.fromList(key);
    invalidated = false;
    return true;
  }

  @override
  Future<KeyRelease> release({required String reason}) async {
    final key = held;
    if (key == null) return const KeyMissing();
    if (invalidated) return const KeyInvalidated();
    prompts++;
    if (!promptSucceeds) return const KeyReleaseCancelled();
    return KeyReleased(Uint8List.fromList(key));
  }

  @override
  Future<void> delete() async => held = null;
}

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  late FakeSecureStorage storage;
  late _FakeHardwareVault vault;
  late BiometricUnlockService service;

  setUp(() {
    storage = FakeSecureStorage();
    vault = _FakeHardwareVault();
    service = BiometricUnlockService(
      storage: storage,
      authenticator: FakeBiometricAuthenticator(),
      vault: vault,
    );
  });

  test('enable hands the key to the vault, never to secure storage', () async {
    expect(await service.enable(key), isTrue);
    expect(vault.held, key);
    expect(storage.store[VaultKeyKeys.biometricKey], isNull);
    expect(await service.isEnabled(), isTrue);
  });

  test('a dismissed enable prompt leaves biometrics off', () async {
    vault.promptSucceeds = false;
    expect(await service.enable(key), isFalse);
    expect(await service.isEnabled(), isFalse);
  });

  test('unlock releases the key from the vault', () async {
    await service.enable(key);
    expect(await service.tryUnlock(), key);
  });

  test('a cancelled prompt releases nothing', () async {
    await service.enable(key);
    vault.promptSucceeds = false;
    expect(await service.tryUnlock(), isNull);
    expect(await service.isEnabled(), isTrue);
  });

  test('an invalidated key turns biometric unlock off', () async {
    await service.enable(key);
    vault.invalidated = true;
    expect(await service.tryUnlock(), isNull);
    expect(await service.isEnabled(), isFalse);
    expect(vault.held, isNull);
  });

  group('an install that kept the key in secure storage', () {
    setUp(() {
      storage.store[VaultKeyKeys.biometricKey] = base64Encode(key);
      storage.store[VaultKeyKeys.biometricEnabled] = 'true';
    });

    test(
      'one prompt unlocks, re-wraps the key and deletes the plain copy',
      () async {
        expect(await service.tryUnlock(), key);
        expect(vault.prompts, 1);
        expect(vault.held, key);
        expect(storage.store[VaultKeyKeys.biometricKey], isNull);
        // Next unlock comes from the vault.
        expect(await service.tryUnlock(), key);
      },
    );

    test('a dismissed prompt keeps the plain copy for the next try', () async {
      vault.promptSucceeds = false;
      expect(await service.tryUnlock(), isNull);
      expect(vault.held, isNull);
      expect(storage.store[VaultKeyKeys.biometricKey], base64Encode(key));
    });
  });

  test('disable wipes the vault and any plain copy', () async {
    await service.enable(key);
    storage.store[VaultKeyKeys.biometricKey] = base64Encode(key);
    await service.disable();
    expect(vault.held, isNull);
    expect(storage.store, isEmpty);
  });
}
