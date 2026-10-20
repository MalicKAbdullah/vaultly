import 'dart:convert';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/services.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';

/// Outcome of asking the vault to release the biometric-unlock key.
sealed class KeyRelease {
  const KeyRelease();
}

final class KeyReleased extends KeyRelease {
  const KeyReleased(this.key);
  final Uint8List key;
}

/// The prompt was dismissed or failed; nothing changed.
final class KeyReleaseCancelled extends KeyRelease {
  const KeyReleaseCancelled();
}

/// No key is held (never stored, or stored by an install that predates the
/// hardware-bound vault).
final class KeyMissing extends KeyRelease {
  const KeyMissing();
}

/// Biometric enrollment changed, so the held key can never be released.
final class KeyInvalidated extends KeyRelease {
  const KeyInvalidated();
}

/// Holds the vault key for biometric unlock and releases it only from a
/// successful biometric prompt.
abstract interface class IBiometricKeyVault {
  /// Whether the key is bound to the biometric prompt in secure hardware
  /// (true) or only gated by the app showing the prompt first (false).
  bool get hardwareBound;

  /// Prompts with [reason], then stores [key]. False when the prompt was
  /// dismissed.
  Future<bool> store(Uint8List key, {required String reason});

  /// Prompts with [reason], then returns the stored key.
  Future<KeyRelease> release({required String reason});

  Future<void> delete();
}

/// Android: the key is AES-GCM-wrapped by a Keystore key that requires a
/// Class 3 biometric for every use (see BiometricKeyVault.kt).
final class AndroidKeystoreKeyVault implements IBiometricKeyVault {
  const AndroidKeystoreKeyVault();

  static const _channel = MethodChannel('vaultly/biometric_key');

  @override
  bool get hardwareBound => true;

  @override
  Future<bool> store(Uint8List key, {required String reason}) async =>
      await _channel.invokeMethod<bool>('store', {
        'key': key,
        'reason': reason,
      }) ??
      false;

  @override
  Future<KeyRelease> release({required String reason}) async {
    final reply = await _channel.invokeMapMethod<String, Object?>('release', {
      'reason': reason,
    });
    return switch (reply?['status']) {
      'released' => KeyReleased(reply!['key']! as Uint8List),
      'cancelled' => const KeyReleaseCancelled(),
      'missing' => const KeyMissing(),
      'invalidated' => const KeyInvalidated(),
      final status => throw StateError('Unknown key release status $status'),
    };
  }

  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');
}

/// Platforms without the native vault (iOS): the key sits in secure storage
/// and the app shows the biometric prompt before reading it.
final class SecureStorageKeyVault implements IBiometricKeyVault {
  const SecureStorageKeyVault({
    required ISecureStorage storage,
    required IBiometricAuthenticator authenticator,
  })  : _storage = storage,
        _authenticator = authenticator;

  final ISecureStorage _storage;
  final IBiometricAuthenticator _authenticator;

  @override
  bool get hardwareBound => false;

  @override
  Future<bool> store(Uint8List key, {required String reason}) async {
    if (!await _authenticator.authenticate(reason)) return false;
    await _storage.write(
      key: VaultKeyKeys.biometricKey,
      value: base64Encode(key),
    );
    return true;
  }

  @override
  Future<KeyRelease> release({required String reason}) async {
    if (!await _authenticator.authenticate(reason)) {
      return const KeyReleaseCancelled();
    }
    final raw = await _storage.read(key: VaultKeyKeys.biometricKey);
    if (raw == null) return const KeyMissing();
    return KeyReleased(Uint8List.fromList(base64Decode(raw)));
  }

  @override
  Future<void> delete() => _storage.delete(key: VaultKeyKeys.biometricKey);
}
