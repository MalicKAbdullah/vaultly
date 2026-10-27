import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/startup_timeline.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

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

/// What the unlock screen waits on before it raises the biometric prompt.
/// Started by [SessionNotifier] at launch and on every lock, so all of it is
/// in flight before the unlock screen is built.
final class UnlockPrerequisites {
  UnlockPrerequisites._({
    required this.cooldown,
    required this.biometricEnabled,
    required this.biometricSupported,
  });

  final Future<Duration> cooldown;
  final Future<bool> biometricEnabled;

  /// The hardware probe. Platform-plugin work, not secure storage, so it
  /// runs alongside the storage reads instead of queueing behind them.
  final Future<bool> biometricSupported;
}

/// Holds the session status. The decrypted vault key lives only inside this
/// notifier (never in widget state) and is zeroed on lock.
///
/// While locked it keeps the encrypted vault file read ahead (ciphertext and
/// its header only — nothing secret), so an unlock is: key in, decrypt and
/// parse on a worker isolate, then the status flips. The vault is therefore
/// decrypted before anything observes [AuthStatus.unlocked], and the vault
/// list's first frame already has its data.
final class SessionNotifier extends Notifier<AuthStatus> {
  Uint8List? _key;
  Uint8List? _salt;
  bool _viaBiometric = false;

  /// The vault file read ahead at launch or lock. A write queued after it
  /// (a recovery reset re-keys the file while locked) makes [_open] read
  /// the file again; see [VaultRepository.current].
  late Future<StoredVault> _payload;

  UnlockPrerequisites? _prerequisites;

  /// The vault decrypted by the latest unlock, until [VaultNotifier] takes
  /// it. An error here is a vault that failed to decrypt or parse.
  AsyncValue<List<VaultEntry>>? _opened;

  @override
  AuthStatus build() {
    // flutter_secure_storage serves calls one at a time, in call order: the
    // verifier is queued first because it decides between setup and unlock.
    final hasPassword = _auth.hasMasterPassword();
    final prerequisites = _prerequisites = _startPrerequisites();
    _prefetchVault();
    if (!kReleaseMode) _logLaunchReads(hasPassword, prerequisites);
    hasPassword.then(
      (has) => state = has ? AuthStatus.locked : AuthStatus.needsSetup,
    );
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

  /// The reads started when the session last locked (or at launch), handed
  /// to the unlock screen once. A screen built again within the same lock
  /// gets fresh reads, since the cooldown may have changed since.
  UnlockPrerequisites unlockPrerequisites() {
    final started = _prerequisites ?? _startPrerequisites();
    _prerequisites = null;
    return started;
  }

  /// Hands the vault decrypted by the latest unlock to its one owner,
  /// [VaultNotifier], and drops this reference. Rethrows a decrypt failure.
  List<VaultEntry> takeOpenedVault() {
    final opened = _opened;
    if (opened == null) {
      throw StateError('No freshly opened vault: it was already taken');
    }
    _opened = null;
    return opened.requireValue;
  }

  void _prepareUnlock() {
    _prerequisites = _startPrerequisites();
    _prefetchVault();
  }

  UnlockPrerequisites _startPrerequisites() {
    final biometrics = ref.read(biometricServiceProvider);
    return UnlockPrerequisites._(
      cooldown: _auth.cooldownRemaining(),
      biometricEnabled: biometrics.isEnabled(),
      biometricSupported: biometrics.isSupported(),
    );
  }

  void _prefetchVault() =>
      _payload = ref.read(vaultRepositoryProvider).readPayload();

  void _logLaunchReads(Future<bool> hasPassword, UnlockPrerequisites p) {
    Future.wait<Object>([
      hasPassword,
      p.cooldown,
      p.biometricEnabled,
      p.biometricSupported,
    ]).then(
      (_) => StartupTimeline.markOnce('launch reads ready'),
      onError: (_) {},
    );
  }

  Future<void> setup(String password) async {
    final result = await _auth.setup(password);
    await _open(result);
    _prompt(RecoveryPrompt.show);
  }

  Future<UnlockResult> unlock(String password) async {
    final result = await _auth.unlock(password);
    if (result is UnlockSuccess) {
      await _open(result);
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
      await _open(result);
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
    StartupTimeline.markOnce('prompt shown');
    final key = await ref.read(biometricServiceProvider).tryUnlock();
    if (key != null) StartupTimeline.markOnce('key released');
    final saltRaw = await salt;
    if (key == null || saltRaw == null) return false;
    await _open(
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
          !await ref.read(biometricAuthenticatorProvider).authenticate(
              'Confirm it’s you to change your master password')) {
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
    if (state == AuthStatus.unlocked) {
      // Read ahead for the unlock screen that comes next. The file read
      // waits for any save still in flight.
      _prepareUnlock();
      state = AuthStatus.locked;
    }
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

  /// Opens a locked session: decrypts the read-ahead vault with the new
  /// key, then flips to unlocked. A vault that fails to decrypt still
  /// unlocks, and surfaces as [VaultNotifier]'s error state.
  Future<void> _open(UnlockSuccess result, {bool viaBiometric = false}) async {
    final timer = Stopwatch()..start();
    final repository = ref.read(vaultRepositoryProvider);
    final vault = await AsyncValue.guard(() async {
      final stored = await repository.current(await _payload);
      return repository.open(stored.payload, result.key);
    });
    StartupTimeline.mark('vault decrypted in ${timer.elapsedMilliseconds} ms');
    _adopt(result, viaBiometric: viaBiometric);
    _opened = vault;
    state = AuthStatus.unlocked;
  }

  /// Takes over [result]'s key for this session, zeroing the previous one.
  void _adopt(UnlockSuccess result, {bool viaBiometric = false}) {
    _wipe();
    _key = result.key;
    _salt = result.salt;
    _viaBiometric = viaBiometric;
  }

  void _wipe() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _salt = null;
    _viaBiometric = false;
    _opened = null;
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

/// The first-run flag, loaded only once the session knows setup is needed.
/// On every other launch, reading it would only queue one more secure
/// storage call ahead of the reads the unlock prompt waits on.
final setupOnboardingSeenProvider = Provider<AsyncValue<bool>?>(
  (ref) => ref.watch(sessionProvider) == AuthStatus.needsSetup
      ? ref.watch(onboardingSeenProvider)
      : null,
);
