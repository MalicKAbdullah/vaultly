import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:vaultkey/src/core/interfaces/vault_file_store.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Persists the vault as one AES-GCM-encrypted JSON document.
///
/// The whole entry list is serialized, encrypted with the session vault key,
/// and written atomically to a single file. Decrypted data exists only in
/// memory. Any tampering with the file fails AES-GCM authentication.
final class VaultRepository {
  const VaultRepository({
    required IVaultFileStore fileStore,
    required CipherService cipher,
  })  : _fileStore = fileStore,
        _cipher = cipher;

  final IVaultFileStore _fileStore;
  final CipherService _cipher;

  static const int _formatVersion = 1;

  Future<List<VaultEntry>> load(Uint8List key) async {
    final bytes = await _fileStore.read();
    if (bytes == null) return const [];

    final plaintext = await _cipher.decrypt(
      payload: EncryptedPayload.fromBytes(bytes),
      keyBytes: key,
    );
    return decodeEntries(plaintext);
  }

  Future<void> save(
    List<VaultEntry> entries,
    Uint8List key,
    Uint8List salt,
  ) async {
    final payload = await _cipher.encrypt(
      plaintext: encodeEntries(entries),
      keyBytes: key,
      salt: salt,
    );
    await _fileStore.write(payload.toBytes());
  }

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
