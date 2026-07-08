import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import 'fakes/fakes.dart';

void main() {
  final codec = BackupCodec(
    keyDerivation: FakeKeyDerivation(),
    cipher: const CipherService(),
  );
  final createdAt = DateTime.utc(2026, 7, 5, 12);

  List<VaultEntry> sampleEntries() => [
        makeEntry(
          id: 'a',
          title: 'Email',
          totp: const TotpConfig(
            secret: 'JBSWY3DPEHPK3PXP',
            algorithm: TotpAlgorithm.sha256,
            digits: 8,
            period: 60,
          ),
          history: [
            PasswordHistoryEntry(
              password: 'old-pass',
              replacedAt: DateTime(2026, 5, 1),
            ),
          ],
        ),
        makeEntry(
          id: 'b',
          title: 'Bank',
          category: EntryCategory.card,
          favorite: true,
          notes: 'PIN hint: birthday',
        ),
      ];

  group('BackupCodec', () {
    test('round-trip: encode then decode returns identical entries', () async {
      final entries = sampleEntries();
      final content = await codec.encode(
        entries: entries,
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      final decoded = await codec.decode(
        content: content,
        passphrase: 'correct horse battery',
      );
      expect(decoded, entries);
    });

    test('envelope carries metadata readable without the passphrase', () async {
      final content = await codec.encode(
        entries: sampleEntries(),
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      final preview = codec.peek(content);
      expect(preview.formatVersion, 1);
      expect(preview.createdAt, createdAt);
      expect(preview.entryCount, 2);
    });

    test('ciphertext does not leak passwords in plaintext', () async {
      final content = await codec.encode(
        entries: sampleEntries(),
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      expect(content.contains('kV9#mQ2x!pW7zR4t'), isFalse);
      expect(content.contains('old-pass'), isFalse);
      expect(content.contains('Email'), isFalse);
      expect(content.contains('JBSWY3DPEHPK3PXP'), isFalse);
    });

    test('wrong passphrase throws BackupPassphraseException', () async {
      final content = await codec.encode(
        entries: sampleEntries(),
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      expect(
        () => codec.decode(content: content, passphrase: 'wrong passphrase'),
        throwsA(isA<BackupPassphraseException>()),
      );
    });

    test('tampered ciphertext fails authentication', () async {
      final content = await codec.encode(
        entries: sampleEntries(),
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      final doc = jsonDecode(content) as Map<String, dynamic>;
      final cipherBytes = base64Decode(doc['ciphertext'] as String);
      cipherBytes[0] ^= 0xFF;
      doc['ciphertext'] = base64Encode(cipherBytes);
      expect(
        () => codec.decode(
          content: jsonEncode(doc),
          passphrase: 'correct horse battery',
        ),
        throwsA(isA<BackupPassphraseException>()),
      );
    });

    test('non-JSON content throws BackupFormatException', () {
      expect(
        () => codec.peek('definitely not json'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('JSON that is not a Vaultly backup throws BackupFormatException', () {
      expect(
        () => codec.peek('{"format":"something.else"}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('backups from a newer format version are rejected', () async {
      final content = await codec.encode(
        entries: sampleEntries(),
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      final doc = jsonDecode(content) as Map<String, dynamic>;
      doc['formatVersion'] = 99;
      expect(
        () => codec.decode(
          content: jsonEncode(doc),
          passphrase: 'correct horse battery',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('empty vault round-trips', () async {
      final content = await codec.encode(
        entries: const [],
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      expect(codec.peek(content).entryCount, 0);
      expect(
        await codec.decode(
          content: content,
          passphrase: 'correct horse battery',
        ),
        isEmpty,
      );
    });
  });
}
