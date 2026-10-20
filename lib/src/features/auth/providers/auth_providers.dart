import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';

enum AuthStatus { unknown, needsSetup, locked, unlocked }

/// What the recovery-key screen should do next: nothing, offer to create a
/// key (once, for vaults without one), or create and show one now (after
/// setup, a password change, or a regenerate from Settings).
enum RecoveryPrompt { none, offer, show }

final recoveryPromptProvider =
    StateProvider<RecoveryPrompt>((_) => RecoveryPrompt.none);

/// Whether a recovery key exists; re-read whenever a prompt starts or ends.
final hasRecoveryKeyProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(recoveryPromptProvider);
  return ref.read(masterAuthServiceProvider).hasRecoveryKey();
});

final sessionProvider = NotifierProvider<SessionNotifier, AuthStatus>(
  SessionNotifier.new,
);

/// Holds the session status. The decrypted vault key lives only inside this
/// notifier (never in widget state) and is zeroed on lock.
final class SessionNotifier extends Notifier<AuthStatus> {
  Uint8List? _key;
  Uint8List? _salt;
  bool _viaBiometric = false;

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

  /// Whether this session was opened with biometrics, which lets the master
  /// password be changed after a fresh biometric prompt instead.
  bool get unlockedWithBiometrics => _viaBiometric;

  Future<void> _init() async {
    final hasPassword = await _auth.hasMasterPassword();
    state = hasPassword ? AuthStatus.locked : AuthStatus.needsSetup;
  }

  Future<void> setup(String password) async {
    final result = await _auth.setup(password);
    _adopt(result);
    _prompt(RecoveryPrompt.show);
  }

  Future<UnlockResult> unlock(String password) async {
    final result = await _auth.unlock(password);
    if (result is UnlockSuccess) {
      _adopt(result);
      await _offerRecoveryIfDue();
    }
    return result;
  }

  /// Forgotten password: the recovery key re-keys the vault under
  /// [newPassword] and unlocks it.
  Future<UnlockResult> resetWithRecoveryKey({
    required String recoveryKey,
    required String newPassword,
  }) async {
    final result = await _auth.resetWithRecoveryKey(
      recoveryKey: recoveryKey,
      newPassword: newPassword,
    );
    if (result is UnlockSuccess) {
      // The held biometric key is the old one — drop it.
      await ref.read(biometricServiceProvider).disable();
      _adopt(result);
    }
    return result;
  }

  /// Wraps the session key under a new recovery key (replacing any earlier
  /// one) and returns it for one-time display.
  Future<String> createRecoveryKey() => _auth.createRecoveryKey(vaultKey);

  /// Biometric unlock path: the wrapped key is released by the platform
  /// prompt; the salt comes from secure storage.
  Future<bool> unlockWithBiometrics() async {
    // The salt is not secret: fetch it while the prompt is up so only the
    // key read is left once the fingerprint matches.
    final salt = ref.read(secureStorageProvider).read(key: VaultKeyKeys.salt);
    final key = await ref.read(biometricServiceProvider).tryUnlock();
    final saltRaw = await salt;
    if (key == null || saltRaw == null) return false;
    _adopt(
      UnlockSuccess(key: key, salt: Uint8List.fromList(base64Decode(saltRaw))),
      viaBiometric: true,
    );
    await _offerRecoveryIfDue();
    return true;
  }

  /// Changes the master password. Proof of identity is [oldPassword], or —
  /// when it is null in a session opened with biometrics — a fresh biometric
  /// prompt. Null when that prompt was not passed. The vault key changes, so
  /// a new recovery key is shown afterwards.
  Future<UnlockResult?> changeMasterPassword({
    required String? oldPassword,
    required String newPassword,
  }) async {
    final UnlockResult result;
    if (oldPassword == null) {
      if (!_viaBiometric ||
          !await ref
              .read(biometricAuthenticatorProvider)
              .authenticate('Confirm it’s you to change your master password')) {
        return null;
      }
      result = await _auth.changeMasterPasswordWithKey(
        currentKey: vaultKey,
        newPassword: newPassword,
      );
    } else {
      result = await _auth.changeMasterPassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    }
    if (result is UnlockSuccess) {
      // The held biometric key is the old one — drop it.
      await ref.read(biometricServiceProvider).disable();
      _adopt(result);
      _prompt(RecoveryPrompt.show);
    }
    return result;
  }

  Future<void> _offerRecoveryIfDue() async {
    if (await _auth.recoveryOfferDue()) _prompt(RecoveryPrompt.offer);
  }

  void _prompt(RecoveryPrompt prompt) =>
      ref.read(recoveryPromptProvider.notifier).state = prompt;

  /// Zeroes the in-memory key and returns to the locked state. Any pending
  /// sensitive clipboard copy is cleared as part of locking.
  void lock() {
    _wipe();
    unawaited(ref.read(clipboardGuardProvider).clearIfUnchanged());
    _prompt(RecoveryPrompt.none);
    if (state == AuthStatus.unlocked) state = AuthStatus.locked;
  }

  Future<void> eraseAll() async {
    _wipe();
    await ref.read(biometricServiceProvider).disable();
    await _auth.eraseAll();
    // The onboarding flag was erased with everything else — reload it so
    // the fresh start begins at the intro again.
    ref.invalidate(onboardingSeenProvider);
    state = AuthStatus.needsSetup;
  }

  void _adopt(UnlockSuccess result, {bool viaBiometric = false}) {
    _wipe();
    _key = result.key;
    _salt = result.salt;
    _viaBiometric = viaBiometric;
    state = AuthStatus.unlocked;
  }

  void _wipe() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _salt = null;
    _viaBiometric = false;
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
