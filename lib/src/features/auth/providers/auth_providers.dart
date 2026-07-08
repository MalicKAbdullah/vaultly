import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';

enum AuthStatus { unknown, needsSetup, locked, unlocked }

final sessionProvider = NotifierProvider<SessionNotifier, AuthStatus>(
  SessionNotifier.new,
);

/// Holds the session status. The decrypted vault key lives only inside this
/// notifier (never in widget state) and is zeroed on lock.
final class SessionNotifier extends Notifier<AuthStatus> {
  Uint8List? _key;
  Uint8List? _salt;

  @override
  AuthStatus build() {
    Future.microtask(_init);
    return AuthStatus.unknown;
  }

  MasterAuthService get _auth => ref.read(masterAuthServiceProvider);

  /// The vault key for the current unlocked session.
  Uint8List get vaultKey {
    final key = _key;
    if (key == null) throw StateError('Session is locked');
    return key;
  }

  Uint8List get salt {
    final salt = _salt;
    if (salt == null) throw StateError('Session is locked');
    return salt;
  }

  Future<void> _init() async {
    final hasPassword = await _auth.hasMasterPassword();
    state = hasPassword ? AuthStatus.locked : AuthStatus.needsSetup;
  }

  Future<void> setup(String password) async {
    final result = await _auth.setup(password);
    _adopt(result);
  }

  Future<UnlockResult> unlock(String password) async {
    final result = await _auth.unlock(password);
    if (result is UnlockSuccess) _adopt(result);
    return result;
  }

  /// Biometric unlock path: the wrapped key is released by the platform
  /// prompt; the salt comes from secure storage.
  Future<bool> unlockWithBiometrics() async {
    final bio = ref.read(biometricServiceProvider);
    final key = await bio.tryUnlock();
    if (key == null) return false;
    final saltRaw =
        await ref.read(secureStorageProvider).read(key: VaultKeyKeys.salt);
    if (saltRaw == null) return false;
    _adopt(
      UnlockSuccess(
        key: key,
        salt: Uint8List.fromList(base64Decode(saltRaw)),
      ),
    );
    return true;
  }

  Future<UnlockResult> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final result = await _auth.changeMasterPassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    if (result is UnlockSuccess) _adopt(result);
    return result;
  }

  /// Zeroes the in-memory key and returns to the locked state. Any pending
  /// sensitive clipboard copy is cleared as part of locking.
  void lock() {
    _wipe();
    unawaited(ref.read(clipboardGuardProvider).clearIfUnchanged());
    if (state == AuthStatus.unlocked) state = AuthStatus.locked;
  }

  Future<void> eraseAll() async {
    _wipe();
    await _auth.eraseAll();
    // The onboarding flag was erased with everything else — reload it so
    // the fresh start begins at the intro again.
    ref.invalidate(onboardingSeenProvider);
    state = AuthStatus.needsSetup;
  }

  void _adopt(UnlockSuccess result) {
    _wipe();
    _key = result.key;
    _salt = result.salt;
    state = AuthStatus.unlocked;
  }

  void _wipe() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _salt = null;
  }
}

/// Whether the first-run intro pages were already shown. Loaded from
/// storage; null-ish while loading (the router waits on the splash).
final onboardingSeenProvider =
    AsyncNotifierProvider<OnboardingSeenNotifier, bool>(
  OnboardingSeenNotifier.new,
);

final class OnboardingSeenNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final raw = await ref
        .read(secureStorageProvider)
        .read(key: VaultKeyKeys.onboardingDone);
    return raw == 'true';
  }

  /// Stores the flag; the router then moves on to master-password setup.
  Future<void> markSeen() async {
    await ref
        .read(secureStorageProvider)
        .write(key: VaultKeyKeys.onboardingDone, value: 'true');
    state = const AsyncData(true);
  }
}
