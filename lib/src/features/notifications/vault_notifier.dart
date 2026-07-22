import 'package:core_backup/core_backup.dart';
import 'package:core_notify/core_notify.dart';
import 'package:core_storage/core_storage.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// On-device Vaultly notifications: a backup alert (auto-backup failed, or no
/// backup in over a week) and a monthly vault-health digest. All computed
/// locally — nothing leaves the device.
class VaultNotifier {
  VaultNotifier({required INotify notify, required ISecureStorage storage})
      : _notify = notify,
        _storage = storage;

  final INotify _notify;
  final ISecureStorage _storage;

  static const List<NotifyChannel> channels = [
    NotifyChannel(
      id: 'backup_alerts',
      name: 'Backup alerts',
      description: 'When an auto-backup fails or is overdue',
      importance: NotifyImportance.high,
    ),
    NotifyChannel(
      id: 'health_digest',
      name: 'Vault health',
      description: 'A monthly summary of weak or reused passwords',
    ),
  ];

  static const Duration _staleAfter = Duration(days: 8);
  static const String _backupShownKey = 'vaultkey_backup_alert_shown';
  static const String _healthMonthKey = 'vaultkey_health_digest_month';

  Future<void> checkOnOpen({
    required AutoBackupConfig? config,
    required List<VaultEntry> entries,
    required DateTime now,
  }) async {
    if (!await _notify.isPermitted()) return;
    await _checkBackup(config, now);
    await _monthlyHealth(entries, now);
  }

  Future<void> _checkBackup(AutoBackupConfig? config, DateTime now) async {
    if (config == null || config.interval == BackupInterval.off) return;

    String? message;
    if (config.lastError != null && config.lastError!.isNotEmpty) {
      message = 'Your last automatic backup failed. Open Settings to fix it.';
    } else if (config.isReady) {
      final last = config.lastBackupAt;
      if (last == null || now.difference(last) > _staleAfter) {
        message = "It's been a while since your vault was backed up.";
      }
    }
    if (message == null) return;

    // Once per day at most.
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (await _storage.read(key: _backupShownKey) == todayKey) return;
    await _notify.show(
      NotifyRequest(
        id: 700001,
        channelId: 'backup_alerts',
        title: 'Backup needs attention',
        body: message,
        payload: 'settings',
      ),
    );
    await _storage.write(key: _backupShownKey, value: todayKey);
  }

  Future<void> _monthlyHealth(List<VaultEntry> entries, DateTime now) async {
    final monthKey = '${now.year}-${now.month}';
    if (await _storage.read(key: _healthMonthKey) == monthKey) return;

    final report = VaultHealthAnalyzer.analyze(entries, now: now);
    // Record the month regardless, so we check at most once per month.
    await _storage.write(key: _healthMonthKey, value: monthKey);
    if (report.issueCount == 0) return;

    final parts = <String>[
      if (report.weak.isNotEmpty) '${report.weak.length} weak',
      if (report.reused.isNotEmpty) '${report.reused.length} reused',
      if (report.old.isNotEmpty) '${report.old.length} old',
    ];
    await _notify.show(
      NotifyRequest(
        id: 700002,
        channelId: 'health_digest',
        title: 'Vault health check',
        body: '${parts.join(' · ')}. Tap to review in Vault Health.',
        payload: 'health',
      ),
    );
  }
}
