import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/services/autofill_matcher.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/totp_generator.dart';
import 'package:vaultkey/src/features/vault/data/vault_repository.dart';

import 'fakes/fakes.dart';
import 'fakes/passkey_fixtures.dart';

/// The Dart ↔ Kotlin contract: the native fill path reads the vault file
/// Dart writes and ranks entries like Dart does. Both sides test against
/// the files in `test/fixtures/contract/`; the Kotlin tests read them as
/// test resources.
///
/// `VAULTLY_WRITE_CONTRACT=1 flutter test test/contract_fixtures_test.dart`
/// rewrites the files after a deliberate format change.
void main() {
  const dir = 'test/fixtures/contract';
  final write = Platform.environment['VAULTLY_WRITE_CONTRACT'] == '1';

  final key = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
  final salt = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  final entries = [
    makeEntry(
      id: 'a1',
      title: 'GitHub',
      username: 'ali@example.com',
      password: 'gh-Pässwörd "quoted" \\ ✓',
      url: 'https://github.com/login',
      totp: const TotpConfig(
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.sha256,
        digits: 8,
        period: 30,
      ),
    ),
    makeEntry(
      id: 'a2',
      title: 'Google work',
      username: 'work@gmail.com',
      password: 'g-work',
      url: 'accounts.google.com',
    ),
    makeEntry(
      id: 'a3',
      title: 'Google personal',
      username: 'me@gmail.com',
      password: 'g-me',
      url: 'google.com',
    ),
    makeEntry(id: 'a4', title: 'Bank', username: 'u', password: 'p', url: ''),
    storedPasskey(id: 'a5'),
  ];

  File file(String name) => File('$dir/$name');

  test('the canonical vault JSON', () {
    final json = VaultRepository.encodeEntries(entries);
    if (write) file('vault.json').writeAsStringSync(json);
    expect(json, file('vault.json').readAsStringSync());
  });

  test('the encrypted vault opens with its key', () async {
    if (write) {
      final payload = await const CipherService().encrypt(
        plaintext: VaultRepository.encodeEntries(entries),
        keyBytes: key,
        salt: salt,
      );
      file('vault.enc').writeAsBytesSync(payload.toBytes());
      file('vault.key.hex').writeAsStringSync(_hex(key));
    }
    expect(file('vault.key.hex').readAsStringSync(), _hex(key));
    final payload =
        EncryptedPayload.fromBytes(file('vault.enc').readAsBytesSync());
    expect(payload.salt, salt);
    final plaintext =
        await const CipherService().decrypt(payload: payload, keyBytes: key);
    expect(VaultRepository.decodeEntries(plaintext), entries);
  });

  test('matcher vectors', () {
    final cases = [
      for (final request in const [
        AutofillFillRequest(domain: 'github.com'),
        AutofillFillRequest(domain: 'accounts.google.com'),
        AutofillFillRequest(domain: 'google.com'),
        AutofillFillRequest(domain: 'mail.google.com'),
        AutofillFillRequest(domain: 'notgithub.com'),
        AutofillFillRequest(domain: 'webauthn.io'),
        AutofillFillRequest(package: 'com.github.android'),
        AutofillFillRequest(package: 'com.google.android.gm'),
        AutofillFillRequest(package: 'com.example.bank'),
        AutofillFillRequest(),
      ])
        {
          if (request.domain != null) 'domain': request.domain,
          if (request.package != null) 'package': request.package,
          'ranked': [
            for (final e in AutofillMatcher.rank(entries, request)) e.id,
          ],
        },
    ];
    final json = const JsonEncoder.withIndent('  ').convert(cases);
    if (write) file('matcher_vectors.json').writeAsStringSync('$json\n');
    expect('$json\n', file('matcher_vectors.json').readAsStringSync());
  });

  test('TOTP codes match the RFC 6238 vectors both sides read', () {
    final vectors = jsonDecode(file('totp_vectors.json').readAsStringSync())
        as List<dynamic>;
    for (final v in vectors.cast<Map<String, dynamic>>()) {
      final config = TotpConfig(
        secret: v['secret'] as String,
        algorithm: TotpAlgorithm.parse(v['algorithm'] as String),
        digits: v['digits'] as int,
        period: v['period'] as int,
      );
      final time = DateTime.fromMillisecondsSinceEpoch(
        (v['unixSeconds'] as int) * 1000,
        isUtc: true,
      );
      expect(TotpGenerator.codeAt(config, time), v['code'], reason: '$v');
    }
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
