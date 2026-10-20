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

/// The master password — or, for [MasterAuthService.resetWithRecoveryKey],
/// the recovery key — was not right.
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
///
/// A recovery key (see [RecoveryKey]) is the way back in when the password is
/// forgotten: the vault key is also stored wrapped under it with
/// [SecretWrapper]. The recovery key itself is never stored. Changing the
/// password changes the vault key, so the old wrap is deleted and the caller
/// creates a fresh recovery key from the new session key.
final class MasterAuthService {
  MasterAuthService({
    required ISecureStorage storage,
    required IKeyDerivation keyDerivation,
    required CipherService cipher,
    required IVaultFileStore fileStore,
    required Clock clock,
    SecretWrapper wrapper = const SecretWrapper(),
  })  : _wrapper = wrapper,
        _storage = storage,
        _kdf = keyDerivation,
        _cipher = cipher,
        _fileStore = fileStore,
        _clock = clock;

  final ISecureStorage _storage;
  final IKeyDerivation _kdf;
  final CipherService _cipher;
  final IVaultFileStore _fileStore;
  final Clock _clock;
  final SecretWrapper _wrapper;

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
    return _recordFailure();
  }

  Future<UnlockWrongPassword> _recordFailure() async {
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
  /// key. The old key can no longer decrypt anything afterwards, and the
  /// recovery key (which wrapped the old key) stops working.
  Future<UnlockResult> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final result = await unlock(oldPassword);
    if (result is! UnlockSuccess) return result;
    final changed = await _rekey(result.key, newPassword);
    await _storage.delete(key: VaultKeyKeys.recoveryWrap);
    return changed;
  }

  /// [changeMasterPassword] for a session whose identity was just proven
  /// another way (a fresh biometric prompt): [currentKey] is the unlocked
  /// vault key. It is copied, so the caller's buffer is left as it is.
  Future<UnlockSuccess> changeMasterPasswordWithKey({
    required Uint8List currentKey,
    required String newPassword,
  }) async {
    final key = Uint8List.fromList(currentKey);
    if (!await _verifierMatches(key)) {
      throw StateError('Session key does not match the vault');
    }
    final changed = await _rekey(key, newPassword);
    await _storage.delete(key: VaultKeyKeys.recoveryWrap);
    return changed;
  }

  Future<bool> hasRecoveryKey() async =>
      await _storage.read(key: VaultKeyKeys.recoveryWrap) != null;

  /// Whether to offer a recovery key once: none exists and none was offered.
  Future<bool> recoveryOfferDue() async =>
      !await hasRecoveryKey() &&
      await _storage.read(key: VaultKeyKeys.recoveryOffered) != 'true';

  /// Records that the one-time offer was shown (taken or declined).
  Future<void> markRecoveryOffered() =>
      _storage.write(key: VaultKeyKeys.recoveryOffered, value: 'true');

  /// Wraps [vaultKey] under a new recovery key, replacing any earlier wrap so
  /// the previous recovery key stops working. Returns the key in display form
  /// for the user to save; it is not stored.
  Future<String> createRecoveryKey(Uint8List vaultKey) async {
    if (!await _verifierMatches(vaultKey)) {
      throw StateError('Session key does not match the vault');
    }
    final recoveryKey = RecoveryKey.generate();
    final wrap = await _wrapper.wrap(
      secret: vaultKey,
      passphrase: RecoveryKey.normalize(recoveryKey)!,
    );
    await _storage.write(key: VaultKeyKeys.recoveryWrap, value: wrap);
    await markRecoveryOffered();
    return recoveryKey;
  }

  /// Forgotten master password: unwraps the vault key with [recoveryKey],
  /// re-encrypts the vault under [newPassword] and re-wraps the new key
  /// under the same recovery key. Wrong keys count toward the same cooldown
  /// as wrong passwords.
  Future<UnlockResult> resetWithRecoveryKey({
    required String recoveryKey,
    required String newPassword,
  }) async {
    assert(
      newPassword.length >= minPasswordLength,
      'Master password must be at least $minPasswordLength characters',
    );
    final remaining = await cooldownRemaining();
    if (remaining > Duration.zero) {
      return UnlockCoolingDown(remaining: remaining);
    }
    final wrap = await _storage.read(key: VaultKeyKeys.recoveryWrap);
    final normalized = RecoveryKey.normalize(recoveryKey);
    final oldKey = wrap == null || normalized == null
        ? null
        : await _wrapper.unwrap(wrapped: wrap, passphrase: normalized);
    if (oldKey == null || !await _verifierMatches(oldKey)) {
      if (oldKey != null) _zero(oldKey);
      return _recordFailure();
    }
    await _resetAttempts();
    final changed = await _rekey(oldKey, newPassword);
    await _storage.write(
      key: VaultKeyKeys.recoveryWrap,
      value: await _wrapper.wrap(secret: changed.key, passphrase: normalized!),
    );
    return changed;
  }

  /// Re-encrypts the vault and verifier from [oldKey] to a key derived from
  /// [newPassword] with a fresh salt, then zeroes [oldKey].
  Future<UnlockSuccess> _rekey(Uint8List oldKey, String newPassword) async {
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
