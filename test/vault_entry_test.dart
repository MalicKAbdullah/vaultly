import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import 'fakes/fakes.dart';

void main() {
  group('VaultEntry JSON compatibility', () {
    test('v1 entry JSON without the totp field still parses (totp == null)',
        () {
      // Exactly what a 1.0.0 vault on a live phone contains.
      const v1Json = '''
      {
        "id": "legacy-1",
        "title": "Personal email",
        "username": "jo@example.com",
        "password": "hunter2!",
        "url": "mail.example.com",
        "notes": "",
        "category": "login",
        "favorite": true,
        "createdAt": "2026-01-10T09:00:00.000",
        "updatedAt": "2026-03-02T10:30:00.000",
        "passwordChangedAt": "2026-03-02T10:30:00.000",
        "history": [
          {"password": "old-one", "replacedAt": "2026-03-02T10:30:00.000"}
        ]
      }
      ''';
      final entry =
          VaultEntry.fromJson(jsonDecode(v1Json) as Map<String, dynamic>);
      expect(entry.id, 'legacy-1');
      expect(entry.totp, isNull);
      expect(entry.title, 'Personal email');
      expect(entry.history, hasLength(1));
    });

    test('an entry without totp does not write a totp key', () {
      final json = makeEntry().toJson();
      expect(json.containsKey('totp'), isFalse);
    });

    test('an entry with totp round-trips through JSON', () {
      const totp = TotpConfig(
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.sha256,
        digits: 8,
        period: 60,
      );
      final entry = makeEntry(totp: totp);
      final decoded = VaultEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, entry);
      expect(decoded.totp, totp);
    });

    test('totp with missing optional params falls back to defaults', () {
      final config = TotpConfig.fromJson(const {'secret': 'ABCD2345'});
      expect(config.algorithm, TotpAlgorithm.sha1);
      expect(config.digits, 6);
      expect(config.period, 30);
    });
  });

  group('VaultEntry.copyWith totp', () {
    test('leaves totp untouched when not specified', () {
      const totp = TotpConfig(secret: 'JBSWY3DPEHPK3PXP');
      final entry = makeEntry(totp: totp);
      expect(entry.copyWith(title: 'Renamed').totp, totp);
    });

    test('can set and clear totp explicitly', () {
      const totp = TotpConfig(secret: 'JBSWY3DPEHPK3PXP');
      final entry = makeEntry();
      final withTotp = entry.copyWith(totp: () => totp);
      expect(withTotp.totp, totp);
      expect(withTotp.copyWith(totp: () => null).totp, isNull);
    });

    test('totp affects equality', () {
      final a = makeEntry();
      final b = makeEntry(totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'));
      expect(a == b, isFalse);
    });
  });
}
