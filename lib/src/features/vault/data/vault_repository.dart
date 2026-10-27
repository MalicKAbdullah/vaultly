import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:vaultkey/src/core/background_worker.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The encrypted vault file as read, tagged with the [VaultFile.generation]
/// it was read at.
final class StoredVault {
  const StoredVault({required this.payload, required this.generation});

  /// Null when no vault file exists yet.
  final EncryptedPayload? payload;
  final int generation;
}

/// Persists the vault as one AES-GCM-encrypted JSON document.
///
/// The whole entry list is serialized, encrypted with the session vault key,
/// and written atomically to a single file. Decrypted data exists only in
/// memory. Any tampering with the file fails AES-GCM authentication.
///
/// Reading is split in two so the slow half can run before the key exists:
/// [readPayload] fetches the ciphertext (non-secret) while the unlock prompt
/// is up; [open] decrypts and parses it once the key is released. Both
/// decrypt-and-parse and encode-and-encrypt run on [IBackgroundWorker].
final class VaultRepository {
  VaultRepository({
    required VaultFile file,
    required CipherService cipher,
    required IBackgroundWorker worker,
  })  : _file = file,
        _cipher = cipher,
        _worker = worker;

  final VaultFile _file;
  final CipherService _cipher;
  final IBackgroundWorker _worker;

  static const int _formatVersion = 1;

  /// The encrypted vault as stored now.
  Future<StoredVault> readPayload() async {
    final read = await _file.readVersioned();
    final bytes = read.bytes;
    return StoredVault(
      payload: bytes == null ? null : EncryptedPayload.fromBytes(bytes),
      generation: read.generation,
    );
  }

  /// [read] when nothing has been queued to write the file since; otherwise
  /// the file read again, after those writes.
  Future<StoredVault> current(StoredVault read) =>
      read.generation == _file.generation ? Future.value(read) : readPayload();

  /// Decrypts and parses [payload] with [key] off the UI isolate. Throws
  /// when the key does not match or the file was tampered with.
  Future<List<VaultEntry>> open(EncryptedPayload? payload, Uint8List key) {
    if (payload == null) return Future.value(const []);
    final keyCopy = Uint8List.fromList(key);
    return _decryptOn(_worker, _cipher, payload, keyCopy)
        .whenComplete(() => _zero(keyCopy));
  }

  Future<List<VaultEntry>> load(Uint8List key) async =>
      open((await readPayload()).payload, key);

  /// Queues the file write at once and encrypts on the worker meanwhile, so
  /// a read issued after this call (a lock mid-edit) sees the saved vault.
  Future<void> save(
    List<VaultEntry> entries,
    Uint8List key,
    Uint8List salt,
  ) {
    final keyCopy = Uint8List.fromList(key);
    return _file.write(
      _encryptOn(_worker, _cipher, entries, keyCopy, salt)
          .whenComplete(() => _zero(keyCopy)),
    );
  }

  // The worker tasks are built in static functions so their closures capture
  // only the plain data they are sent with, never the repository.

  static Future<List<VaultEntry>> _decryptOn(
    IBackgroundWorker worker,
    CipherService cipher,
    EncryptedPayload payload,
    Uint8List key,
  ) =>
      worker.run(() async {
        try {
          return decodeEntries(
            await cipher.decrypt(payload: payload, keyBytes: key),
          );
        } finally {
          // A worker isolate holds its own copy of the key; zero it rather
          // than leave it to the garbage collector.
          _zero(key);
        }
      });

  static Future<Uint8List> _encryptOn(
    IBackgroundWorker worker,
    CipherService cipher,
    List<VaultEntry> entries,
    Uint8List key,
    Uint8List salt,
  ) =>
      worker.run(() async {
        try {
          final payload = await cipher.encrypt(
            plaintext: encodeEntries(entries),
            keyBytes: key,
            salt: salt,
          );
          return payload.toBytes();
        } finally {
          _zero(key);
        }
      });

  static void _zero(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  /// Serializes entries to the canonical vault JSON document.
  static String encodeEntries(List<VaultEntry> entries) => jsonEncode({
        'version': _formatVersion,
        'entries': entries.map((e) => e.toJson()).toList(),
      });

  /// Parses the canonical vault JSON document.
  static List<VaultEntry> decodeEntries(String json) {
    final doc = jsonDecode(json) as Map<String, dynamic>;
    final list = doc['entries'] as List<dynamic>;
    return list.cast<Map<String, dynamic>>().map(VaultEntry.fromJson).toList();
  }
}
