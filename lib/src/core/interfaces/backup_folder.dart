import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

/// A folder the user selected as the auto-backup destination.
final class BackupFolderSelection {
  const BackupFolderSelection({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// Abstraction over the backup destination folder so the auto-backup
/// pipeline is fully testable without platform channels.
abstract interface class IBackupFolder {
  /// Opens a system folder picker. Returns null when the user cancels.
  Future<BackupFolderSelection?> pickFolder();

  /// Writes (or overwrites) [fileName] inside the folder at [folderUri].
  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required Uint8List bytes,
  });
}

/// Android implementation over the Storage Access Framework. The picker is
/// ACTION_OPEN_DOCUMENT_TREE with a persisted URI permission, so any
/// provider that appears there works — including Google Drive folders.
final class SafBackupFolder implements IBackupFolder {
  SafBackupFolder();

  final SafUtil _util = SafUtil();
  final SafStream _stream = SafStream();

  @override
  Future<BackupFolderSelection?> pickFolder() async {
    final dir = await _util.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (dir == null) return null;
    return BackupFolderSelection(uri: dir.uri, name: dir.name);
  }

  @override
  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required Uint8List bytes,
  }) async {
    await _stream.writeFileBytes(
      folderUri,
      fileName,
      'application/octet-stream',
      bytes,
      overwrite: true,
    );
  }
}

/// iOS (and fallback) implementation: backups live in a `Backups/` folder
/// inside the app documents directory, which is visible in the Files app.
final class AppDocumentsBackupFolder implements IBackupFolder {
  const AppDocumentsBackupFolder();

  static const String folderToken = 'appdocuments://backups';

  @override
  Future<BackupFolderSelection?> pickFolder() async =>
      const BackupFolderSelection(
        uri: folderToken,
        name: 'On this device (Files app)',
      );

  @override
  Future<void> writeFile({
    required String folderUri,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}Backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
