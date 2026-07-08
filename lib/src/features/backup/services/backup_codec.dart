import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:vaultkey/src/core/app_info.dart';
import 'package:vaultkey/src/core/interfaces/key_derivation.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The `.vkbackup` file is malformed or not a Vaultly backup.
final class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The passphrase does not decrypt the backup.
final class BackupPassphraseException implements Exception {
  const BackupPassphraseException();

  @override
  String toString() => 'Wrong passphrase for this backup.';
}

/// Metadata readable without the passphrase.
final class BackupPreview {
  const BackupPreview({
    required this.formatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.entryCount,
  });

  final int formatVersion;
  final String appVersion;
  final DateTime createdAt;
  final int entryCount;
}

/// Encodes/decodes the encrypted `.vkbackup` envelope:
/// a JSON object carrying Argon2id salt + AES-GCM nonce/ciphertext of the
/// canonical vault JSON, keyed by a separate backup passphrase.
final class BackupCodec {
  const BackupCodec({
    required IKeyDerivation keyDerivation,
    required CipherService cipher,
  })  : _kdf = keyDerivation,
        _cipher = cipher;

  final IKeyDerivation _kdf;
  final CipherService _cipher;

  static const String format = 'vaultkey.backup';
  static const int formatVersion = 1;
  static const int minPassphraseLength = 8;

  Future<String> encode({
    required List<VaultEntry> entries,
    required String passphrase,
    required DateTime createdAt,
  }) async {
    final salt = await _cipher.generateSalt();
    final key = await _kdf.deriveKey(password: passphrase, salt: salt);
    final payload = await _cipher.encrypt(
      plaintext: VaultRepository.encodeEntries(entries),
      keyBytes: key,
      salt: salt,
    );
    key.fillRange(0, key.length, 0);

    return jsonEncode({
      'format': format,
      'formatVersion': formatVersion,
      'appVersion': AppInfo.version,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'entryCount': entries.length,
      'kdf': 'argon2id',
      'salt': base64Encode(salt),
      'nonce': base64Encode(payload.nonce),
      'ciphertext': base64Encode(payload.ciphertext),
    });
  }

  /// Reads envelope metadata without needing the passphrase.
  BackupPreview peek(String content) {
    final doc = _envelope(content);
    return BackupPreview(
      formatVersion: doc['formatVersion'] as int,
      appVersion: doc['appVersion'] as String? ?? 'unknown',
      createdAt: DateTime.parse(doc['createdAt'] as String),
      entryCount: doc['entryCount'] as int? ?? 0,
    );
  }

  Future<List<VaultEntry>> decode({
    required String content,
    required String passphrase,
  }) async {
    final doc = _envelope(content);
    if ((doc['formatVersion'] as int) > formatVersion) {
      throw const BackupFormatException(
        'This backup was made by a newer version of Vaultly.',
      );
    }

    final salt = Uint8List.fromList(base64Decode(doc['salt'] as String));
    final nonce = Uint8List.fromList(base64Decode(doc['nonce'] as String));
    final ciphertext =
        Uint8List.fromList(base64Decode(doc['ciphertext'] as String));

    final key = await _kdf.deriveKey(password: passphrase, salt: salt);
    try {
      final plaintext = await _cipher.decrypt(
        payload:
            EncryptedPayload(ciphertext: ciphertext, nonce: nonce, salt: salt),
        keyBytes: key,
      );
      return VaultRepository.decodeEntries(plaintext);
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      // AES-GCM MAC verification failed: wrong passphrase (or tampering).
      throw const BackupPassphraseException();
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Map<String, dynamic> _envelope(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const BackupFormatException('This is not a Vaultly backup file.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['formatVersion'] is! int ||
        decoded['salt'] is! String ||
        decoded['nonce'] is! String ||
        decoded['ciphertext'] is! String) {
      throw const BackupFormatException('This is not a Vaultly backup file.');
    }
    return decoded;
  }
}
