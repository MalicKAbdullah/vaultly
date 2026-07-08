import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_policy.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_service.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Auto-backup configuration + status for the Settings screen, and the
/// entry point the vault loader calls after each unlock.
final autoBackupControllerProvider =
    AsyncNotifierProvider<AutoBackupController, AutoBackupConfig>(
  AutoBackupController.new,
);

class AutoBackupController extends AsyncNotifier<AutoBackupConfig> {
  AutoBackupService get _service => ref.read(autoBackupServiceProvider);

  @override
  Future<AutoBackupConfig> build() => _service.loadConfig();

  Future<void> setInterval(BackupInterval interval) async {
    await _service.setInterval(interval);
    await _reload();
  }

  /// Opens the system folder picker; returns false when cancelled.
  Future<bool> pickFolder() async {
    final selection = await ref.read(backupFolderProvider).pickFolder();
    if (selection == null) return false;
    await _service.setFolder(selection);
    await _reload();
    return true;
  }

  Future<void> setPassphrase(String passphrase) async {
    await _service.setPassphrase(passphrase);
    await _reload();
  }

  Future<AutoBackupRunResult> runIfDue(List<VaultEntry> entries) async {
    final result = await _service.runIfDue(entries);
    if (result is! BackupSkipped) await _reload();
    return result;
  }

  Future<AutoBackupRunResult> backupNow(List<VaultEntry> entries) async {
    final result = await _service.backupNow(entries);
    await _reload();
    return result;
  }

  Future<void> _reload() async {
    state = AsyncData(await _service.loadConfig());
  }
}

/// Non-blocking banner text shown on the vault list when the most recent
/// scheduled backup failed.
final backupBannerProvider = Provider<String?>((ref) {
  final config = ref.watch(autoBackupControllerProvider).valueOrNull;
  if (config == null) return null;
  if (config.interval == BackupInterval.off) return null;
  return config.lastError;
});
