import 'dart:io';

import 'package:core_backup/core_backup.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_storage/core_storage.dart';
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
