import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/identity_details.dart';
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

  group('Card and identity details', () {
    const card = CardDetails(
      holder: 'Ada Lovelace',
      number: '4242424242424242',
      expMonth: '07',
      expYear: '2030',
      cvc: '123',
    );
    const identity = IdentityDetails(
      fullName: 'Ada Lovelace',
      email: 'ada@example.com',
      phone: '+44 20 7946 0000',
      address1: '12 St James Square',
      address2: 'Flat 3',
      city: 'London',
      region: 'Greater London',
      postalCode: 'SW1Y 4JH',
      country: 'United Kingdom',
    );

    test('a format 1 entry loads with no card or identity', () {
      final entry = VaultEntry.fromJson(
        jsonDecode(jsonEncode(makeEntry().toJson())) as Map<String, dynamic>,
      );
      expect(entry.card, isNull);
      expect(entry.identity, isNull);
      expect(makeEntry().toJson().keys, isNot(contains('card')));
      expect(makeEntry().toJson().keys, isNot(contains('identity')));
    });

    test('card and identity round-trip through JSON', () {
      final entry = makeEntry(
        category: EntryCategory.card,
        card: card,
        identity: identity,
      );
      final decoded = VaultEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, entry);
      expect(decoded.card, card);
      expect(decoded.identity, identity);
    });

    test('card and identity take part in equality', () {
      expect(makeEntry(card: card) == makeEntry(), isFalse);
      expect(makeEntry(identity: identity) == makeEntry(), isFalse);
      expect(
        makeEntry(card: card) == makeEntry(card: card),
        isTrue,
      );
    });

    test('copyWith keeps, replaces and clears them', () {
      final entry = makeEntry(card: card, identity: identity);
      expect(entry.copyWith(title: 'x').card, card);
      expect(entry.copyWith(card: () => null).card, isNull);
      expect(entry.copyWith(identity: () => null).identity, isNull);
      expect(entry.copyWith(identity: () => null).card, card);
    });

    test('masked label, expiry and grouping', () {
      expect(card.brand, 'Visa');
      expect(card.maskedLabel, 'Visa •••• 4242');
      expect(card.expiry, '07/30');
      expect(card.groupedNumber, '4242 4242 4242 4242');
      expect(const CardDetails(number: '371449635398431').brand, 'Amex');
      expect(const CardDetails(number: '5555444433331111').brand, 'Mastercard');
      expect(const CardDetails(number: '2223003122003222').brand, 'Mastercard');
      expect(const CardDetails(number: '9999888877776666').maskedLabel,
          '•••• 6666');
      expect(const CardDetails().maskedLabel, '');
    });

    test('toString never shows the number or the code', () {
      expect(card.toString(), isNot(contains('4242424242424242')));
      expect(card.toString(), isNot(contains('123')));
    });

    test('expiry parsing accepts common shapes and rejects the rest', () {
      expect(CardDetails.parseExpiry('7/30'), (month: '07', year: '2030'));
      expect(CardDetails.parseExpiry('07/2030'), (month: '07', year: '2030'));
      expect(CardDetails.parseExpiry('0730'), (month: '07', year: '2030'));
      expect(CardDetails.parseExpiry('12 - 31'), (month: '12', year: '2031'));
      expect(CardDetails.parseExpiry(''), (month: '', year: ''));
      expect(CardDetails.parseExpiry('13/30'), isNull);
      expect(CardDetails.parseExpiry('00/30'), isNull);
      expect(CardDetails.parseExpiry('7/303'), isNull);
      expect(CardDetails.parseExpiry('soon'), isNull);
    });

    test('digitsOf strips spaces and dashes', () {
      expect(CardDetails.digitsOf('4242 4242-4242 4242'), '4242424242424242');
    });

    test('identity formats its address on lines', () {
      expect(
        identity.formattedAddress,
        '12 St James Square\nFlat 3\nLondon Greater London SW1Y 4JH\n'
        'United Kingdom',
      );
      expect(const IdentityDetails(email: 'a@b.c').hasAddress, isFalse);
      expect(const IdentityDetails().isEmpty, isTrue);
    });
  });
}
