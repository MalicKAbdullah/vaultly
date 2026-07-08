import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_storage/core_storage.dart';
import 'package:vaultkey/src/core/clock.dart';
import 'package:vaultkey/src/core/interfaces/key_derivation.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/core/storage_keys.dart';

/// Result of an unlock attempt.
sealed class UnlockResult {
  const UnlockResult();
}

final class UnlockSuccess extends UnlockResult {
  const UnlockSuccess({required this.key, required this.salt});

  final Uint8List key;
  final Uint8List salt;
}

final class UnlockWrongPassword extends UnlockResult {
  const UnlockWrongPassword({required this.failedAttempts, this.cooldown});

  final int failedAttempts;

  /// Non-null when this failure triggered a lockout.
  final Duration? cooldown;
}

final class UnlockCoolingDown extends UnlockResult {
  const UnlockCoolingDown({required this.remaining});

  final Duration remaining;
}

/// Master-password authentication and key lifecycle.
///
/// The vault key is derived from the master password with Argon2id and a
/// per-user random salt. The password itself is never stored; correctness is
/// verified by decrypting a known sentinel encrypted with the derived key
/// (AES-GCM authentication makes a wrong key fail loudly).
final class MasterAuthService {
  MasterAuthService({
    required ISecureStorage storage,
    required IKeyDerivation keyDerivation,
    required CipherService cipher,
    required IVaultFileStore fileStore,
    required Clock clock,
  })  : _storage = storage,
        _kdf = keyDerivation,
        _cipher = cipher,
        _fileStore = fileStore,
        _clock = clock;

  final ISecureStorage _storage;
  final IKeyDerivation _kdf;
  final CipherService _cipher;
  final IVaultFileStore _fileStore;
  final Clock _clock;

  static const String _sentinel = 'vaultkey:verifier:v1';
  static const int minPasswordLength = 8;
  static const int maxFreeAttempts = 5;
  static const Duration baseCooldown = Duration(seconds: 30);
  static const Duration maxCooldown = Duration(minutes: 15);

  Future<bool> hasMasterPassword() async =>
      await _storage.read(key: VaultKeyKeys.verifier) != null;

  /// Creates the vault on first run. Returns the derived vault key.
  Future<UnlockSuccess> setup(String password) async {
    assert(
      password.length >= minPasswordLength,
      'Master password must be at least $minPasswordLength characters',
    );
    final salt = await _cipher.generateSalt();
    final key = await _kdf.deriveKey(password: password, salt: salt);
    await _writeVerifier(key, salt);
    await _storage.write(key: VaultKeyKeys.salt, value: base64Encode(salt));
    await _resetAttempts();
    return UnlockSuccess(key: key, salt: salt);
  }

  /// Attempts to unlock with [password], enforcing the escalating cooldown.
  Future<UnlockResult> unlock(String password) async {
    final remaining = await cooldownRemaining();
    if (remaining > Duration.zero) {
      return UnlockCoolingDown(remaining: remaining);
    }

    final saltRaw = await _storage.read(key: VaultKeyKeys.salt);
    if (saltRaw == null) {
      throw StateError('No master password configured');
    }
    final salt = Uint8List.fromList(base64Decode(saltRaw));
    final key = await _kdf.deriveKey(password: password, salt: salt);

    if (await _verifierMatches(key)) {
      await _resetAttempts();
      return UnlockSuccess(key: key, salt: salt);
    }

    _zero(key);
    final attempts = await _failedAttempts() + 1;
    await _storage.write(
      key: VaultKeyKeys.failedAttempts,
      value: attempts.toString(),
    );

    Duration? cooldown;
    if (attempts >= maxFreeAttempts) {
      cooldown = cooldownFor(attempts);
      final until = _clock.now().add(cooldown);
      await _storage.write(
        key: VaultKeyKeys.lockoutUntil,
        value: until.millisecondsSinceEpoch.toString(),
      );
    }
    return UnlockWrongPassword(failedAttempts: attempts, cooldown: cooldown);
  }

  /// Escalating cooldown: 30s at the 5th failure, doubling per extra
  /// failure, capped at 15 minutes.
  static Duration cooldownFor(int failedAttempts) {
    if (failedAttempts < maxFreeAttempts) return Duration.zero;
    final exponent = failedAttempts - maxFreeAttempts;
    var seconds = baseCooldown.inSeconds;
    for (var i = 0; i < exponent; i++) {
      seconds *= 2;
      if (seconds >= maxCooldown.inSeconds) return maxCooldown;
    }
    return Duration(seconds: seconds);
  }

  Future<Duration> cooldownRemaining() async {
    final raw = await _storage.read(key: VaultKeyKeys.lockoutUntil);
    if (raw == null) return Duration.zero;
    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
    final diff = until.difference(_clock.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Changes the master password: verifies [oldPassword], derives a fresh
  /// salt + key, and re-encrypts the vault file and verifier with the new
  /// key. The old key can no longer decrypt anything afterwards.
  Future<UnlockResult> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final result = await unlock(oldPassword);
    if (result is! UnlockSuccess) return result;

    final oldKey = result.key;
    final newSalt = await _cipher.generateSalt();
    final newKey = await _kdf.deriveKey(password: newPassword, salt: newSalt);

    // Re-encrypt the vault blob in memory first, then persist.
    final existing = await _fileStore.read();
    if (existing != null) {
      final plaintext = await _cipher.decrypt(
        payload: EncryptedPayload.fromBytes(existing),
        keyBytes: oldKey,
      );
      final reEncrypted = await _cipher.encrypt(
        plaintext: plaintext,
        keyBytes: newKey,
        salt: newSalt,
      );
      await _fileStore.write(reEncrypted.toBytes());
    }

    await _writeVerifier(newKey, newSalt);
    await _storage.write(key: VaultKeyKeys.salt, value: base64Encode(newSalt));
    // A wrapped biometric key would still be the old one — drop it.
    await _storage.delete(key: VaultKeyKeys.biometricKey);
    await _storage.delete(key: VaultKeyKeys.biometricEnabled);
    _zero(oldKey);
    return UnlockSuccess(key: newKey, salt: newSalt);
  }

  /// Erases the vault file and all Vaultly secure-storage keys.
  Future<void> eraseAll() async {
    await _fileStore.delete();
    for (final key in VaultKeyKeys.all) {
      await _storage.delete(key: key);
    }
  }

  Future<int> _failedAttempts() async {
    final raw = await _storage.read(key: VaultKeyKeys.failedAttempts);
    return raw == null ? 0 : int.parse(raw);
  }

  Future<void> _resetAttempts() async {
    await _storage.delete(key: VaultKeyKeys.failedAttempts);
    await _storage.delete(key: VaultKeyKeys.lockoutUntil);
  }

  Future<void> _writeVerifier(Uint8List key, Uint8List salt) async {
    final payload = await _cipher.encrypt(
      plaintext: _sentinel,
      keyBytes: key,
      salt: salt,
    );
    await _storage.write(
      key: VaultKeyKeys.verifier,
      value: base64Encode(payload.toBytes()),
    );
  }

  Future<bool> _verifierMatches(Uint8List key) async {
    final raw = await _storage.read(key: VaultKeyKeys.verifier);
    if (raw == null) return false;
    try {
      final plaintext = await _cipher.decrypt(
        payload: EncryptedPayload.fromBytes(base64Decode(raw)),
        keyBytes: key,
      );
      return plaintext == _sentinel;
    } catch (_) {
      // AES-GCM MAC verification failed: wrong key.
      return false;
    }
  }

  static void _zero(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}
