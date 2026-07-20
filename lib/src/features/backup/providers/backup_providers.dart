import 'dart:convert';
import 'dart:typed_data';

import 'package:core_backup/core_backup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Auto-backup status for the vault-list banner, and the entry point the vault
/// loader calls after each unlock. Thin glue over the shared [AutoBackupService]
/// (core_backup); the Settings UI drives the service directly via
/// [AutoBackupSection].
final autoBackupControllerProvider =
    AsyncNotifierProvider<AutoBackupController, AutoBackupConfig>(
  AutoBackupController.new,
);

class AutoBackupController extends AsyncNotifier<AutoBackupConfig> {
  AutoBackupService get _service => ref.read(autoBackupServiceProvider);

  @override
  Future<AutoBackupConfig> build() => _service.loadConfig();

  /// Runs a scheduled backup of [entries] if one is due; refreshes status.
  Future<AutoBackupRunResult> runIfDue(List<VaultEntry> entries) async {
    final result = await _service.runIfDue(_encode(entries));
    if (result is! BackupSkipped) {
      state = AsyncData(await _service.loadConfig());
    }
    return result;
  }

  /// Encodes [entries] into the app's encrypted `.vkbackup` bytes.
  BackupProducer _encode(List<VaultEntry> entries) => (passphrase) async {
        final raw = await ref.read(backupCodecProvider).encode(
              entries: entries,
              passphrase: passphrase!,
              createdAt: ref.read(clockProvider).now(),
            );
        return Uint8List.fromList(utf8.encode(raw));
      };
}

/// Non-blocking banner text shown on the vault list when the most recent
/// scheduled backup failed.
final backupBannerProvider = Provider<String?>((ref) {
  final config = ref.watch(autoBackupControllerProvider).valueOrNull;
  if (config == null) return null;
  if (config.interval == BackupInterval.off) return null;
  return config.lastError;
});
