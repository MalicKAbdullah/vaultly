import 'dart:io';

import 'package:core_backup/core_backup.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_notify/core_notify.dart';
import 'package:core_storage/core_storage.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vaultkey/src/core/clock.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/core/interfaces/key_derivation.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/core/services/clipboard_guard.dart';
import 'package:vaultkey/src/features/auth/services/biometric_service.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/notifications/vault_notifier.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';

/// Composition root. Tests override the leaf providers (storage, file store,
/// key derivation, clock, clipboard, backup folder, biometrics) with
/// in-memory fakes — no platform channels.
final clockProvider = Provider<Clock>((_) => const SystemClock());

final secureStorageProvider = Provider<ISecureStorage>(
  (_) => const SecureStorageImpl(FlutterSecureStorage()),
);

final fileStoreProvider = Provider<IVaultFileStore>(
  (_) => const DocumentsVaultFileStore(),
);

final cipherServiceProvider = Provider<CipherService>(
  (_) => const CipherService(),
);

final keyDerivationProvider = Provider<IKeyDerivation>(
  (_) => const Argon2KeyDerivation(KeyDerivationService()),
);

final systemClipboardProvider = Provider<ISystemClipboard>(
  (_) => const FlutterSystemClipboard(),
);

final clipboardGuardProvider = Provider<ClipboardGuard>((ref) {
  final guard = ClipboardGuard(clipboard: ref.watch(systemClipboardProvider));
  ref.onDispose(guard.dispose);
  return guard;
});

final autofillBridgeProvider = Provider<IAutofillBridge>(
  (_) => const MethodChannelAutofillBridge(),
);

final biometricAuthenticatorProvider = Provider<IBiometricAuthenticator>(
  (_) => LocalAuthBiometric(),
);

final biometricServiceProvider = Provider<BiometricUnlockService>(
  (ref) => BiometricUnlockService(
    storage: ref.watch(secureStorageProvider),
    authenticator: ref.watch(biometricAuthenticatorProvider),
  ),
);

final masterAuthServiceProvider = Provider<MasterAuthService>(
  (ref) => MasterAuthService(
    storage: ref.watch(secureStorageProvider),
    keyDerivation: ref.watch(keyDerivationProvider),
    cipher: ref.watch(cipherServiceProvider),
    fileStore: ref.watch(fileStoreProvider),
    clock: ref.watch(clockProvider),
  ),
);

final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => VaultRepository(
    fileStore: ref.watch(fileStoreProvider),
    cipher: ref.watch(cipherServiceProvider),
  ),
);

final backupCodecProvider = Provider<BackupCodec>(
  (ref) => BackupCodec(
    keyDerivation: ref.watch(keyDerivationProvider),
    cipher: ref.watch(cipherServiceProvider),
  ),
);

final backupFolderProvider = Provider<IBackupFolder>(
  (_) =>
      Platform.isAndroid ? SafBackupFolder() : const AppDocumentsBackupFolder(),
);

final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(
    storage: ref.watch(secureStorageProvider),
    folder: ref.watch(backupFolderProvider),
    keyPrefix: 'vaultkey',
    fileLabel: 'Vaultly',
    fileExtension: 'vkbackup',
    now: () => ref.read(clockProvider).now(),
  ),
);

// -- In-app update (core_update) ------------------------------------------

/// Secure-storage key for the auto-check preference.
const String updateAutoCheckKey = 'vaultkey_update_autocheck';

final updateServiceProvider = Provider<IUpdateService>(
  (_) => GithubUpdateService(owner: 'MalicKAbdullah', repo: 'vaultly'),
);

/// Auto-check preference (persisted; on by default). Toggle in Settings.
final updateAutoCheckProvider = FutureProvider<bool>(
  (ref) async =>
      await ref.watch(secureStorageProvider).read(key: updateAutoCheckKey) !=
      'false',
);

/// The pending update (null when disabled, up to date, or offline).
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (!await ref.watch(updateAutoCheckProvider.future)) return null;
  return ref.watch(updateServiceProvider).check();
});

/// Session-only dismissal of the update banner.
final updateDismissedProvider = StateProvider<bool>((_) => false);

// -- Notifications (core_notify) ------------------------------------------

/// Overridden in main() with an initialized [LocalNotify].
final notifyProvider = Provider<INotify>((_) => const NoopNotify());

final vaultNotifierProvider = Provider<VaultNotifier>(
  (ref) => VaultNotifier(
    notify: ref.watch(notifyProvider),
    storage: ref.watch(secureStorageProvider),
  ),
);
