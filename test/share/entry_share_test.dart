import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/share/crypto/entry_share.dart';
import 'package:vaultkey/src/features/share/services/shared_entry.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/models/card_details.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import '../fakes/fakes.dart';
import '../fakes/passkey_fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 18);
  final entry = makeEntry(
    title: 'GitHub',
    username: 'octo',
    password: 'Qm7#vR2!kT9pL4xZ',
    url: 'github.com',
    notes: 'work account',
    totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
    history: [
      PasswordHistoryEntry(password: 'old-pass', replacedAt: DateTime(2026)),
    ],
  );

  group('SharedEntry', () {
    test('carries the entry but never its history; 2FA only on request', () {
      final plain = SharedEntry.encode(entry, includeTotp: false);
      expect(utf8.decode(plain), isNot(contains('old-pass')));
      expect(utf8.decode(plain), isNot(contains('JBSWY3DPEHPK3PXP')));
      final got = SharedEntry.decode(plain, id: 'new', now: now);
      expect(got.id, 'new');
      expect(got.title, 'GitHub');
      expect(got.password, 'Qm7#vR2!kT9pL4xZ');
      expect(got.notes, 'work account');
      expect(got.totp, isNull);
      expect(got.history, isEmpty);
      expect(got.createdAt, now);

      final withTotp = SharedEntry.decode(
        SharedEntry.encode(entry, includeTotp: true),
        id: 'new',
        now: now,
      );
      expect(withTotp.totp, entry.totp);
    });

    test('a card travels with its details', () {
      final card = makeEntry(
        category: EntryCategory.card,
        card: const CardDetails(number: '4242424242424242', cvc: '123'),
      );
      final got = SharedEntry.decode(
        SharedEntry.encode(card, includeTotp: false),
        id: 'c',
        now: now,
      );
      expect(got.card, card.card);
      expect(got.category, EntryCategory.card);
    });

    test('a passkey cannot be shared or received', () {
      final passkey = storedPasskey();
      expect(
        () => SharedEntry.encode(passkey, includeTotp: false),
        throwsArgumentError,
      );
      final forged = utf8.encode(jsonEncode({
        'format': 2,
        'entry': {
          'title': 'x',
          'username': '',
          'password': '',
          'url': '',
          'notes': '',
          'category': 'passkey',
        },
      }));
      expect(
        () => SharedEntry.decode(forged, id: 'x', now: now),
        throwsA(isA<ShareException>()),
      );
    });

    test('a newer format asks for an update', () {
      final newer = utf8.encode(jsonEncode({'format': 99, 'entry': {}}));
      expect(
        () => SharedEntry.decode(newer, id: 'x', now: now),
        throwsA(isA<ShareException>().having(
          (e) => e.message,
          'message',
          contains('newer Vaultly'),
        )),
      );
    });
  });

  group('QrShare', () {
    final plain = SharedEntry.encode(entry, includeTotp: false);

    test('round-trips between an invite and its sender', () async {
      final invite = await ShareInvite.create();
      final sealed = await QrShare.sealForInvite(invite.uri, plain);
      expect(sealed, startsWith('vaultly-share://v1?e='));
      expect(sealed, isNot(contains('GitHub')));
      expect(await invite.open(sealed), plain);
    });

    test('a code sealed for another invite does not open', () async {
      final mine = await ShareInvite.create();
      final other = await ShareInvite.create();
      final sealed = await QrShare.sealForInvite(other.uri, plain);
      await expectLater(mine.open(sealed), throwsA(isA<ShareException>()));
    });

    test('an altered code does not open', () async {
      final invite = await ShareInvite.create();
      final sealed = await QrShare.sealForInvite(invite.uri, plain);
      final c = sealed.indexOf('&c=') + 3;
      final flipped = sealed.substring(0, c + 5) +
          (sealed[c + 5] == 'A' ? 'B' : 'A') +
          sealed.substring(c + 6);
      await expectLater(invite.open(flipped), throwsA(isA<ShareException>()));
    });

    test('a low-order (all-zero) receiver key is refused', () async {
      final zero = base64Url.encode(List.filled(32, 0)).replaceAll('=', '');
      await expectLater(
        QrShare.sealForInvite('vaultly-recv://v1?k=$zero', plain),
        throwsA(isA<ShareException>()),
      );
    });

    test('other QR codes are refused with a hint', () async {
      await expectLater(
        QrShare.sealForInvite('https://example.com', plain),
        throwsA(isA<ShareException>()),
      );
      final invite = await ShareInvite.create();
      await expectLater(
        invite.open('vaultly-recv://v1?k=abc'),
        throwsA(isA<ShareException>()),
      );
    });

    test('an entry too long for a QR code must go as a file', () async {
      final long = SharedEntry.encode(
        makeEntry(notes: 'x' * 1200),
        includeTotp: false,
      );
      final invite = await ShareInvite.create();
      await expectLater(
        QrShare.sealForInvite(invite.uri, long),
        throwsA(isA<ShareException>().having(
          (e) => e.message,
          'message',
          contains('as a file'),
        )),
      );
    });
  });

  group('FileShare', () {
    final share = FileShare(
      keyDerivation: FakeKeyDerivation(),
      cipher: const CipherService(),
    );
    final plain = SharedEntry.encode(entry, includeTotp: false);

    test('round-trips with the code, in any formatting', () async {
      final code = FileShare.newCode();
      final file = await share.seal(plain, code);
      expect(FileShare.recognises(file), isTrue);
      expect(file, isNot(contains('GitHub')));
      expect(
        await share.open(file, code.toLowerCase().replaceAll('-', ' ')),
        plain,
      );
    });

    test('a wrong code is refused', () async {
      final file = await share.seal(plain, FileShare.newCode());
      await expectLater(
        share.open(file, FileShare.newCode()),
        throwsA(isA<ShareException>().having(
          (e) => e.message,
          'message',
          'That code does not open this file.',
        )),
      );
    });

    test('an altered file is refused', () async {
      final code = FileShare.newCode();
      final doc = jsonDecode(await share.seal(plain, code)) as Map;
      final bytes = base64Decode(doc['ciphertext'] as String);
      bytes[0] ^= 1;
      doc['ciphertext'] = base64Encode(bytes);
      await expectLater(
        share.open(jsonEncode(doc), code),
        throwsA(isA<ShareException>()),
      );
    });

    test('a newer file version and other files are refused', () async {
      final code = FileShare.newCode();
      final doc = jsonDecode(await share.seal(plain, code)) as Map;
      doc['formatVersion'] = 99;
      await expectLater(
        share.open(jsonEncode(doc), code),
        throwsA(isA<ShareException>().having(
          (e) => e.message,
          'message',
          contains('newer Vaultly'),
        )),
      );
      expect(FileShare.recognises('{"format":"vaultkey.backup"}'), isFalse);
      expect(FileShare.recognises('not json'), isFalse);
    });
  });
}
