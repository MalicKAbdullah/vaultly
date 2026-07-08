import 'dart:convert';
import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:local_auth/local_auth.dart';
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
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Optional biometric unlock. When enabled, the derived vault key is kept
/// (wrapped in secure storage) and only released after a successful
/// biometric prompt. Disabling wipes the stored key. The master password
/// always remains the fallback.
final class BiometricUnlockService {
  BiometricUnlockService({
    required ISecureStorage storage,
    required IBiometricAuthenticator authenticator,
  })  : _storage = storage,
        _authenticator = authenticator;

  final ISecureStorage _storage;
  final IBiometricAuthenticator _authenticator;

  Future<bool> isSupported() => _authenticator.isSupported();

  Future<bool> isEnabled() async =>
      await _storage.read(key: VaultKeyKeys.biometricEnabled) == 'true';

  /// Stores the current session key for biometric unlock.
  Future<void> enable(Uint8List key) async {
    await _storage.write(
      key: VaultKeyKeys.biometricKey,
      value: base64Encode(key),
    );
    await _storage.write(key: VaultKeyKeys.biometricEnabled, value: 'true');
  }

  /// Wipes the wrapped key.
  Future<void> disable() async {
    await _storage.delete(key: VaultKeyKeys.biometricKey);
    await _storage.delete(key: VaultKeyKeys.biometricEnabled);
  }

  /// Shows the biometric prompt and, on success, returns the vault key.
  /// Returns null when cancelled, failed, or not enabled.
  Future<Uint8List?> tryUnlock() async {
    if (!await isEnabled()) return null;
    final ok = await _authenticator.authenticate('Unlock your vault');
    if (!ok) return null;
    final raw = await _storage.read(key: VaultKeyKeys.biometricKey);
    if (raw == null) return null;
    return Uint8List.fromList(base64Decode(raw));
  }
}
