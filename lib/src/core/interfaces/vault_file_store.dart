import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Abstraction over the encrypted vault file so tests can inject an
/// in-memory fake (no platform channels needed).
abstract interface class IVaultFileStore {
  /// Returns the raw encrypted bytes, or null when no vault exists yet.
  Future<Uint8List?> read();

  /// The first [length] bytes of the file, or null when no vault exists.
  Future<Uint8List?> readHead(int length);

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
  Future<Uint8List?> readHead(int length) async {
    final file = await _file();
    final RandomAccessFile handle;
    try {
      handle = await file.open();
    } on PathNotFoundException {
      return null;
    }
    try {
      return await handle.read(length);
    } finally {
      await handle.close();
    }
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

/// The vault file as one Flutter engine sees it: every read, write and
/// delete in one queue, so a read queued after a write sees that write.
/// All code in an engine that touches the file shares the one instance
/// (`vaultFileProvider`).
///
/// Other engines in the process (the Credential Manager activity runs its
/// own) have their own queue over the same file, so this queue alone cannot
/// tell whether a read taken earlier is still current; see
/// `VaultRepository.current`, which asks the file itself.
final class VaultFile implements IVaultFileStore {
  VaultFile(this._store);

  final IVaultFileStore _store;
  Future<void> _tail = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<Uint8List?> read() => _enqueue(_store.read);

  @override
  Future<Uint8List?> readHead(int length) =>
      _enqueue(() => _store.readHead(length));

  /// Takes the write's place in the queue now, even while [bytes] are still
  /// being produced (encrypted), so no later read can see the older file.
  @override
  Future<void> write(FutureOr<Uint8List> bytes) {
    final pending = Future.value(bytes)..ignore();
    return _enqueue(() async => _store.write(await pending));
  }

  @override
  Future<void> delete() => _enqueue(_store.delete);
}
