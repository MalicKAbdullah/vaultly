import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import 'fakes/fakes.dart';

void main() {
  final codec = BackupCodec(
    keyDerivation: FakeKeyDerivation(),
    cipher: const CipherService(),
    appVersion: () async => '9.9.9',
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
      expect(preview.formatVersion, 2);
      expect(preview.createdAt, createdAt);
      expect(preview.entryCount, 2);
      expect(preview.appVersion, '9.9.9');
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

    test('a format 1 backup from Vaultly 1.10 still restores', () async {
      // Exactly what Vaultly 1.10 wrote: envelope format 1 around a format 1
      // vault document, which has no card or identity keys.
      const v1Vault = '{"version":1,"entries":[{"id":"legacy-card",'
          '"title":"Old card","username":"Jo Bloggs",'
          '"password":"4111111111111111","url":"","notes":"Expires: 7/2030",'
          '"category":"card","favorite":false,'
          '"createdAt":"2026-01-10T09:00:00.000",'
          '"updatedAt":"2026-03-02T10:30:00.000",'
          '"passwordChangedAt":"2026-03-02T10:30:00.000","history":[]}]}';
      const cipher = CipherService();
      final salt = await cipher.generateSalt();
      final key = await FakeKeyDerivation()
          .deriveKey(password: 'correct horse battery', salt: salt);
      final payload =
          await cipher.encrypt(plaintext: v1Vault, keyBytes: key, salt: salt);
      final content = jsonEncode({
        'format': 'vaultkey.backup',
        'formatVersion': 1,
        'appVersion': '1.10.0',
        'createdAt': createdAt.toIso8601String(),
        'entryCount': 1,
        'kdf': 'argon2id',
        'salt': base64Encode(salt),
        'nonce': base64Encode(payload.nonce),
        'ciphertext': base64Encode(payload.ciphertext),
      });

      expect(codec.peek(content).formatVersion, 1);
      final restored = await codec.decode(
        content: content,
        passphrase: 'correct horse battery',
      );
      final entry = restored.single;
      expect(entry.category, EntryCategory.card);
      expect(entry.username, 'Jo Bloggs');
      expect(entry.password, '4111111111111111');
      expect(entry.notes, 'Expires: 7/2030');
      expect(entry.card, isNull);
      expect(entry.identity, isNull);
    });

    test('cards and identities survive a backup round-trip', () async {
      final entries = [
        makeEntry(
          id: 'c',
          category: EntryCategory.card,
          card: const CardDetails(
            holder: 'Jo',
            number: '4242424242424242',
            expMonth: '01',
            expYear: '2031',
            cvc: '999',
          ),
        ),
        makeEntry(
          id: 'i',
          category: EntryCategory.identity,
          identity: const IdentityDetails(fullName: 'Jo', city: 'Leeds'),
        ),
      ];
      final content = await codec.encode(
        entries: entries,
        passphrase: 'correct horse battery',
        createdAt: createdAt,
      );
      expect(content, isNot(contains('4242424242424242')));
      expect(
        await codec.decode(
          content: content,
          passphrase: 'correct horse battery',
        ),
        entries,
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
