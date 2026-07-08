import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Abstraction over the encrypted vault file so tests can inject an
/// in-memory fake (no platform channels needed).
abstract interface class IVaultFileStore {
  /// Returns the raw encrypted bytes, or null when no vault exists yet.
  Future<Uint8List?> read();

  Future<void> write(Uint8List bytes);

  Future<void> delete();
}

/// Stores the vault as a single file in the app documents directory.
final class DocumentsVaultFileStore implements IVaultFileStore {
  const DocumentsVaultFileStore();

  static const String _fileName = 'vaultkey_vault.enc';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  Future<Uint8List?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final file = await _file();
    // Write to a temp file then rename for a crash-safe replace.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
