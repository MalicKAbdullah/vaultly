import 'dart:convert';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/core/clock.dart';
import 'package:vaultkey/src/core/interfaces/backup_folder.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_policy.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Current auto-backup configuration and status, as shown in Settings.
@immutable
final class AutoBackupConfig {
  const AutoBackupConfig({
    required this.interval,
    required this.folderUri,
    required this.folderName,
    required this.hasPassphrase,
    required this.lastBackupAt,
    required this.lastError,
  });

  static const AutoBackupConfig empty = AutoBackupConfig(
    interval: BackupInterval.off,
    folderUri: null,
    folderName: null,
    hasPassphrase: false,
    lastBackupAt: null,
    lastError: null,
  );

  final BackupInterval interval;
  final String? folderUri;
  final String? folderName;
  final bool hasPassphrase;
  final DateTime? lastBackupAt;
  final String? lastError;

  bool get isReady =>
      interval != BackupInterval.off && folderUri != null && hasPassphrase;
}

sealed class AutoBackupRunResult {
  const AutoBackupRunResult();
}

final class BackupSkipped extends AutoBackupRunResult {
  const BackupSkipped();
}

final class BackupWritten extends AutoBackupRunResult {
  const BackupWritten({required this.fileName});

  final String fileName;
}

final class BackupFailed extends AutoBackupRunResult {
  const BackupFailed({required this.message});

  final String message;
}

/// Runs scheduled backups: checks [AutoBackupPolicy] on unlock and writes an
/// encrypted `.vkbackup` into the user's chosen folder. Failures never block
/// unlock — they are recorded and surfaced as a gentle banner.
final class AutoBackupService {
  AutoBackupService({
    required ISecureStorage storage,
    required BackupCodec codec,
    required IBackupFolder folder,
    required Clock clock,
  })  : _storage = storage,
        _codec = codec,
        _folder = folder,
        _clock = clock;

  final ISecureStorage _storage;
  final BackupCodec _codec;
  final IBackupFolder _folder;
  final Clock _clock;

  Future<AutoBackupConfig> loadConfig() async {
    final lastAtRaw = await _storage.read(key: VaultKeyKeys.backupLastAt);
    return AutoBackupConfig(
      interval: BackupInterval.parse(
        await _storage.read(key: VaultKeyKeys.backupInterval),
      ),
      folderUri: await _storage.read(key: VaultKeyKeys.backupFolderUri),
      folderName: await _storage.read(key: VaultKeyKeys.backupFolderName),
      hasPassphrase:
          await _storage.read(key: VaultKeyKeys.backupPassphrase) != null,
      lastBackupAt: lastAtRaw == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(int.parse(lastAtRaw)),
      lastError: await _storage.read(key: VaultKeyKeys.backupLastError),
    );
  }

  Future<void> setInterval(BackupInterval interval) => _storage.write(
        key: VaultKeyKeys.backupInterval,
        value: interval.name,
      );

  Future<void> setFolder(BackupFolderSelection folder) async {
    await _storage.write(
      key: VaultKeyKeys.backupFolderUri,
      value: folder.uri,
    );
    await _storage.write(
      key: VaultKeyKeys.backupFolderName,
      value: folder.name,
    );
  }

  Future<void> setPassphrase(String passphrase) => _storage.write(
        key: VaultKeyKeys.backupPassphrase,
        value: passphrase,
      );

  /// Runs a backup if one is due per the schedule. Never throws.
  Future<AutoBackupRunResult> runIfDue(List<VaultEntry> entries) async {
    final config = await loadConfig();
    if (!config.isReady) return const BackupSkipped();
    final due = AutoBackupPolicy.isDue(
      interval: config.interval,
      lastBackupAt: config.lastBackupAt,
      now: _clock.now(),
    );
    if (!due) return const BackupSkipped();
    return _run(entries, config);
  }

  /// Runs a backup immediately (Settings → "Back up now"). Never throws.
  Future<AutoBackupRunResult> backupNow(List<VaultEntry> entries) async {
    final config = await loadConfig();
    if (config.folderUri == null || !config.hasPassphrase) {
      return const BackupFailed(
        message: 'Choose a backup folder and passphrase first.',
      );
    }
    return _run(entries, config);
  }

  Future<AutoBackupRunResult> _run(
    List<VaultEntry> entries,
    AutoBackupConfig config,
  ) async {
    try {
      final passphrase =
          await _storage.read(key: VaultKeyKeys.backupPassphrase);
      if (passphrase == null) {
        return const BackupFailed(message: 'Backup passphrase is not set.');
      }
      final now = _clock.now();
      final content = await _codec.encode(
        entries: entries,
        passphrase: passphrase,
        createdAt: now,
      );
      final fileName = fileNameFor(now);
      await _folder.writeFile(
        folderUri: config.folderUri!,
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      await _storage.write(
        key: VaultKeyKeys.backupLastAt,
        value: now.millisecondsSinceEpoch.toString(),
      );
      await _storage.delete(key: VaultKeyKeys.backupLastError);
      return BackupWritten(fileName: fileName);
    } catch (e) {
      const message = 'Could not write the backup. '
          'Check that the folder is still available.';
      await _storage.write(key: VaultKeyKeys.backupLastError, value: message);
      return const BackupFailed(message: message);
    }
  }

  static String fileNameFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'Vaultly-backup-${date.year}-$month-$day.vkbackup';
  }
}
