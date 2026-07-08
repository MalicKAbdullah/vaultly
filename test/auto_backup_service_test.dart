import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/storage_keys.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_policy.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_service.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';

import 'fakes/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late FakeBackupFolder folder;
  late FixedClock clock;
  late BackupCodec codec;
  late AutoBackupService service;

  setUp(() {
    storage = FakeSecureStorage();
    folder = FakeBackupFolder();
    clock = FixedClock(DateTime(2026, 7, 5, 9));
    codec = BackupCodec(
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
    );
    service = AutoBackupService(
      storage: storage,
      codec: codec,
      folder: folder,
      clock: clock,
    );
  });

  Future<void> configureDaily() async {
    await service.setInterval(BackupInterval.daily);
    await service.setFolder(folder.selection!);
    await service.setPassphrase('backup passphrase');
  }

  group('AutoBackupService.runIfDue', () {
    test('skips when auto-backup is not configured', () async {
      expect(await service.runIfDue([makeEntry()]), isA<BackupSkipped>());
      expect(folder.files, isEmpty);
    });

    test('first run writes a dated backup and records the time', () async {
      await configureDaily();
      final result = await service.runIfDue([makeEntry()]);
      expect(result, isA<BackupWritten>());
      expect(
        (result as BackupWritten).fileName,
        'Vaultly-backup-2026-07-05.vkbackup',
      );
      expect(folder.files.keys.single, 'Vaultly-backup-2026-07-05.vkbackup');

      final config = await service.loadConfig();
      expect(config.lastBackupAt, clock.current);
      expect(config.lastError, isNull);
    });

    test('written backup decrypts with the configured passphrase', () async {
      await configureDaily();
      final entry = makeEntry(id: 'roundtrip');
      await service.runIfDue([entry]);
      final content = utf8.decode(folder.files.values.single);
      final decoded = await codec.decode(
        content: content,
        passphrase: 'backup passphrase',
      );
      expect(decoded.single.id, 'roundtrip');
    });

    test('a second unlock the same day is skipped', () async {
      await configureDaily();
      await service.runIfDue([makeEntry()]);
      clock.advance(const Duration(hours: 3));
      expect(await service.runIfDue([makeEntry()]), isA<BackupSkipped>());
      expect(folder.files.length, 1);
    });

    test('runs again once the interval has passed', () async {
      await configureDaily();
      await service.runIfDue([makeEntry()]);
      clock.advance(const Duration(days: 1));
      final result = await service.runIfDue([makeEntry()]);
      expect(result, isA<BackupWritten>());
      expect(folder.files.length, 2);
      expect(
        folder.files.containsKey('Vaultly-backup-2026-07-06.vkbackup'),
        isTrue,
      );
    });

    test('write failures surface as BackupFailed and persist a message',
        () async {
      await configureDaily();
      folder.failWrites = true;
      final result = await service.runIfDue([makeEntry()]);
      expect(result, isA<BackupFailed>());
      final config = await service.loadConfig();
      expect(config.lastError, isNotNull);
      expect(config.lastBackupAt, isNull);
    });

    test('a later successful run clears the recorded error', () async {
      await configureDaily();
      folder.failWrites = true;
      await service.runIfDue([makeEntry()]);
      folder.failWrites = false;
      await service.runIfDue([makeEntry()]);
      final config = await service.loadConfig();
      expect(config.lastError, isNull);
      expect(config.lastBackupAt, isNotNull);
    });
  });

  group('AutoBackupService.backupNow', () {
    test('fails gracefully without folder or passphrase', () async {
      final result = await service.backupNow([makeEntry()]);
      expect(result, isA<BackupFailed>());
    });

    test('runs immediately even when nothing is due', () async {
      await configureDaily();
      await service.runIfDue([makeEntry()]);
      expect(await service.runIfDue([makeEntry()]), isA<BackupSkipped>());
      expect(await service.backupNow([makeEntry()]), isA<BackupWritten>());
    });
  });

  group('config persistence', () {
    test('loadConfig reflects everything that was set', () async {
      await configureDaily();
      final config = await service.loadConfig();
      expect(config.interval, BackupInterval.daily);
      expect(config.folderUri, 'fake://backups');
      expect(config.folderName, 'Backups');
      expect(config.hasPassphrase, isTrue);
      expect(config.isReady, isTrue);
    });

    test('the passphrase itself is stored, not exposed via config', () async {
      await service.setPassphrase('backup passphrase');
      expect(
        storage.store[VaultKeyKeys.backupPassphrase],
        'backup passphrase',
      );
      final config = await service.loadConfig();
      expect(config.hasPassphrase, isTrue);
    });
  });
}
