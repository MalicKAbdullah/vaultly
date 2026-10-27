import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/parsers/otpauth_migration.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';
import 'package:vaultkey/src/features/totp/services/totp_generator.dart';

/// The widely published Google Authenticator export example: secret
/// "Hello!\xde\xad\xbe\xef" (base32 JBSWY3DPEHPK3PXP), name
/// "Example:alice@google.com", issuer "Example", type TOTP.
const _knownVector = 'otpauth-migration://offline?data='
    'CjEKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRoHRXhhbXBsZTAC';

/// Hand-encoded MigrationPayload (batch 2 of 2, id 123456789) with:
///  1. secret 0x01..0x14, "GitHub:octo@example.com", issuer GitHub, SHA1, 6
///  2. secret "1234…9012" (32 B), "alice@example.com", issuer "Sample Bank",
///     SHA256, 8 digits
///  3. secret 0x00..0x3f (64 B), "ünïcødé:用户", no issuer, SHA512, type
///     unspecified
///  4. HOTP "hotp-account" (counter 7) — unsupported
///  5. MD5 "md5-account" — unsupported
const _multiVector = 'otpauth-migration://offline?data='
    'Cj0KFAECAwQFBgcICQoLDA0ODxAREhMUEhdHaXRIdWI6b2N0b0BleGFtcGxlLmNvbRoGR2l0'
    'SHViIAEoATACCkgKIDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyEhFhbGljZUBl'
    'eGFtcGxlLmNvbRoLU2FtcGxlIEJhbmsgAigCMAIKXgpAAAECAwQFBgcICQoLDA0ODxAREhMU'
    'FRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0%2BPxISw7xuw69jw7hk'
    'w6k655So5oi3GgAgAygBMAAKIwoDYWJjEgxob3RwLWFjY291bnQaBkxlZ2FjeSABKAEwATgH'
    'Ch8KA2FiYxILbWQ1LWFjY291bnQaBVdlaXJkIAQoATACEAEYAiABKJWa7zo%3D';

void main() {
  group('OtpauthMigration', () {
    test('decodes the published example', () {
      final batch = OtpauthMigration.parse(_knownVector);
      final auth = batch.authenticators.single;
      expect(auth.issuer, 'Example');
      expect(auth.account, 'alice@google.com');
      expect(auth.config.secret, 'JBSWY3DPEHPK3PXP');
      expect(auth.config.algorithm, TotpAlgorithm.sha1);
      expect(auth.config.digits, 6);
      expect(auth.config.period, 30);
      expect(batch.batchSize, 1);
      expect(batch.warnings, isEmpty);
    });

    test('decodes several accounts with every parameter', () {
      final batch = OtpauthMigration.parse(_multiVector);
      expect(batch.batchSize, 2);
      expect(batch.batchIndex, 1);
      expect(batch.batchId, 123456789);
      expect(batch.authenticators, const [
        ImportedAuthenticator(
          config: TotpConfig(secret: 'AEBAGBAFAYDQQCIKBMGA2DQPCAIREEYU'),
          issuer: 'GitHub',
          account: 'octo@example.com',
        ),
        ImportedAuthenticator(
          config: TotpConfig(
            secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA',
            algorithm: TotpAlgorithm.sha256,
            digits: 8,
          ),
          issuer: 'Sample Bank',
          account: 'alice@example.com',
        ),
        ImportedAuthenticator(
          config: TotpConfig(
            secret: 'AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPSAIJCEM'
                'SCKJRHFAUSUKZMFUXC6MBRGIZTINJWG44DSOR3HQ6T4PY',
            algorithm: TotpAlgorithm.sha512,
          ),
          issuer: 'ünïcødé',
          account: '用户',
        ),
      ]);
    });

    test('reports HOTP and MD5 accounts instead of importing them', () {
      final warnings = OtpauthMigration.parse(_multiVector).warnings;
      expect(warnings, hasLength(2));
      expect(warnings[0], contains('Legacy'));
      expect(warnings[0], contains('HOTP'));
      expect(warnings[1], contains('Weird'));
    });

    test('decoded secrets generate RFC 6238 codes', () {
      // RFC 6238 appendix B: SHA256 seed at T=59 → 46119246.
      final sha256 =
          OtpauthMigration.parse(_multiVector).authenticators[1].config;
      expect(
        TotpGenerator.codeAt(
          sha256,
          DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
        ),
        '46119246',
      );
    });

    test('base32 encoding round-trips through decoding', () {
      final bytes = List<int>.generate(37, (i) => (i * 37) & 0xFF);
      expect(Base32.decode(Base32.encode(bytes)), bytes);
    });

    test('rejects links that are not migration exports', () {
      for (final bad in [
        'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
        'otpauth-migration://online?data=CjEK',
        'otpauth-migration://offline',
        'otpauth-migration://offline?data=%%%',
      ]) {
        expect(
          () => OtpauthMigration.parse(bad),
          throwsA(isA<ImportFormatException>()),
          reason: bad,
        );
      }
    });

    test('rejects truncated payloads', () {
      // The known vector cut short inside the secret.
      expect(
        () => OtpauthMigration.parse(
          'otpauth-migration://offline?data=CjEKCkhlbGxv',
        ),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });
}
