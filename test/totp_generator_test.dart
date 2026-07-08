import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';
import 'package:vaultkey/src/features/totp/services/totp_generator.dart';

void main() {
  group('Base32.decode', () {
    // RFC 4648 §10 test vectors.
    const vectors = {
      'MY======': 'f',
      'MZXQ====': 'fo',
      'MZXW6===': 'foo',
      'MZXW6YQ=': 'foob',
      'MZXW6YTB': 'fooba',
      'MZXW6YTBOI======': 'foobar',
    };

    test('decodes the RFC 4648 vectors', () {
      vectors.forEach((encoded, expected) {
        expect(utf8.decode(Base32.decode(encoded)), expected);
      });
    });

    test('tolerates missing padding', () {
      expect(utf8.decode(Base32.decode('MZXW6YTBOI')), 'foobar');
    });

    test('tolerates lowercase input', () {
      expect(utf8.decode(Base32.decode('mzxw6ytboi')), 'foobar');
    });

    test('tolerates spaces and dashes between groups', () {
      expect(utf8.decode(Base32.decode('mzxw 6ytb-oi')), 'foobar');
      expect(utf8.decode(Base32.decode(' MZXW\t6YTB OI ')), 'foobar');
    });

    test('rejects characters outside the alphabet', () {
      expect(() => Base32.decode('MZXW1'), throwsFormatException); // 1
      expect(() => Base32.decode('MZXW8'), throwsFormatException); // 8
      expect(() => Base32.decode('MZXW0'), throwsFormatException); // 0
      expect(() => Base32.decode('MZX!W'), throwsFormatException);
    });

    test('rejects an empty or padding-only secret', () {
      expect(() => Base32.decode(''), throwsFormatException);
      expect(() => Base32.decode('===='), throwsFormatException);
      expect(() => Base32.decode('  '), throwsFormatException);
    });

    test('isValid mirrors decode acceptance', () {
      expect(Base32.isValid('mzxw6ytboi'), isTrue);
      expect(Base32.isValid('MZXW 6YTB OI'), isTrue);
      expect(Base32.isValid('not base32!'), isFalse);
      expect(Base32.isValid(''), isFalse);
    });
  });

  group('TotpGenerator (RFC 6238 Appendix B)', () {
    // Appendix B secrets: ASCII "12345678901234567890" for SHA1 and
    // "12345678901234567890123456789012" for SHA256, base32-encoded.
    const sha1Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    const sha256Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';

    const sha1Config = TotpConfig(secret: sha1Secret, digits: 8);
    const sha256Config = TotpConfig(
      secret: sha256Secret,
      algorithm: TotpAlgorithm.sha256,
      digits: 8,
    );

    DateTime at(int unixSeconds) =>
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

    const sha1Expected = {
      59: '94287082',
      1111111109: '07081804',
      1111111111: '14050471',
      1234567890: '89005924',
      2000000000: '69279037',
      20000000000: '65353130',
    };

    const sha256Expected = {
      59: '46119246',
      1111111109: '68084774',
      1111111111: '67062674',
      1234567890: '91819424',
      2000000000: '90698825',
      20000000000: '77737706',
    };

    test('matches every SHA1 vector', () {
      sha1Expected.forEach((time, expected) {
        expect(
          TotpGenerator.codeAt(sha1Config, at(time)),
          expected,
          reason: 'T=$time',
        );
      });
    });

    test('matches every SHA256 vector', () {
      sha256Expected.forEach((time, expected) {
        expect(
          TotpGenerator.codeAt(sha256Config, at(time)),
          expected,
          reason: 'T=$time',
        );
      });
    });

    test('6-digit codes are the last 6 digits of the 8-digit vector', () {
      const config = TotpConfig(secret: sha1Secret);
      expect(TotpGenerator.codeAt(config, at(59)), '287082');
    });

    test('leading zeros are preserved', () {
      const config = TotpConfig(secret: sha1Secret, digits: 8);
      expect(TotpGenerator.codeAt(config, at(1111111109)), '07081804');
    });

    test('local (non-UTC) times give the same code as their UTC instant', () {
      const config = TotpConfig(secret: sha1Secret, digits: 8);
      final local = at(1234567890).toLocal();
      expect(TotpGenerator.codeAt(config, local), '89005924');
    });

    test('a custom period changes the counter window', () {
      const config60 = TotpConfig(secret: sha1Secret, digits: 8, period: 60);
      // With a 60 s period, T=59 and T=119 share... no: 59~/60=0, 119~/60=1.
      expect(
        TotpGenerator.codeAt(config60, at(59)),
        TotpGenerator.codeAt(config60, at(1)),
      );
      expect(
        TotpGenerator.codeAt(config60, at(59)),
        isNot(TotpGenerator.codeAt(config60, at(61))),
      );
    });

    test('secondsRemaining counts down to the period boundary', () {
      const config = TotpConfig(secret: sha1Secret);
      expect(TotpGenerator.secondsRemaining(config, at(0)), 30);
      expect(TotpGenerator.secondsRemaining(config, at(29)), 1);
      expect(TotpGenerator.secondsRemaining(config, at(30)), 30);
      expect(TotpGenerator.secondsRemaining(config, at(59)), 1);
    });

    test('fractionElapsed spans [0, 1) across the period', () {
      const config = TotpConfig(secret: sha1Secret);
      expect(TotpGenerator.fractionElapsed(config, at(0)), 0);
      expect(TotpGenerator.fractionElapsed(config, at(15)), 0.5);
      expect(TotpGenerator.fractionElapsed(config, at(30)), 0);
    });

    test('group splits codes for display', () {
      expect(TotpGenerator.group('123456'), '123 456');
      expect(TotpGenerator.group('12345678'), '1234 5678');
      expect(TotpGenerator.group('1234567'), '1234567');
    });

    test('an invalid secret throws FormatException', () {
      const config = TotpConfig(secret: 'not base32!');
      expect(
        () => TotpGenerator.codeAt(config, at(59)),
        throwsFormatException,
      );
    });
  });
}
