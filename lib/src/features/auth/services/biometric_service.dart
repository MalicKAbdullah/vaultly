import 'dart:convert';
import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultkey/src/core/interfaces/biometric_key_vault.dart';
import 'package:vaultkey/src/core/storage_keys.dart';

/// Abstraction over the platform biometric prompt so the unlock flow is
/// testable without platform channels.
abstract interface class IBiometricAuthenticator {
  Future<bool> isSupported();

  Future<bool> authenticate(String reason);
}

final class LocalAuthBiometric implements IBiometricAuthenticator {
  LocalAuthBiometric();

  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          // Unlocking is not a sensitive transaction: without this, Android
          // makes face unlock wait for an extra "Confirm" tap.
          sensitiveTransaction: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Optional biometric unlock. When enabled, the vault key is held by an
/// [IBiometricKeyVault] that releases it only from a successful biometric
/// prompt. Disabling wipes it. The master password always remains the
/// fallback.
final class BiometricUnlockService {
  BiometricUnlockService({
    required ISecureStorage storage,
    required IBiometricAuthenticator authenticator,
    required IBiometricKeyVault vault,
  })  : _storage = storage,
        _authenticator = authenticator,
        _vault = vault;

  final ISecureStorage _storage;
  final IBiometricAuthenticator _authenticator;
  final IBiometricKeyVault _vault;

  static const String _unlockReason = 'Unlock your vault';

  Future<bool> isSupported() => _authenticator.isSupported();

  Future<bool> isEnabled() async =>
      await _storage.read(key: VaultKeyKeys.biometricEnabled) == 'true';

  /// Prompts, then hands the current session key to the vault. False when
  /// the prompt was dismissed.
  Future<bool> enable(Uint8List key) async {
    if (!await _vault.store(
      key,
      reason: 'Confirm to enable biometric unlock',
    )) {
      return false;
    }
    await _storage.write(key: VaultKeyKeys.biometricEnabled, value: 'true');
    return true;
  }

  /// Wipes the held key, including one left by an older install.
  Future<void> disable() async {
    await _vault.delete();
    await _storage.delete(key: VaultKeyKeys.biometricKey);
    await _storage.delete(key: VaultKeyKeys.biometricEnabled);
  }

  /// Shows the biometric prompt and, on success, returns the vault key.
  /// Returns null when cancelled or no key can be released; an invalidated
  /// key (biometric enrollment changed) turns biometric unlock off.
  ///
  /// The caller has already read [isEnabled] to offer biometrics, so the
  /// prompt goes up without another secure-storage round trip.
  Future<Uint8List?> tryUnlock() async {
    switch (await _vault.release(reason: _unlockReason)) {
      case KeyReleased(:final key):
        return key;
      case KeyReleaseCancelled():
        return null;
      case KeyMissing():
        return _migrateLegacyKey();
      case KeyInvalidated():
        await disable();
        return null;
    }
  }

  /// Installs from before the hardware-bound vault kept the key directly in
  /// secure storage. Storing it in the vault shows the prompt, so that one
  /// prompt both unlocks and re-wraps the key, and the plain copy is deleted.
  Future<Uint8List?> _migrateLegacyKey() async {
    if (!_vault.hardwareBound) return null;
    final raw = await _storage.read(key: VaultKeyKeys.biometricKey);
    if (raw == null) return null;
    final key = Uint8List.fromList(base64Decode(raw));
    if (!await _vault.store(key, reason: _unlockReason)) {
      key.fillRange(0, key.length, 0);
      return null;
    }
    await _storage.delete(key: VaultKeyKeys.biometricKey);
    return key;
  }
}
