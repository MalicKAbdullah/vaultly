import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/otpauth_parser.dart';

void main() {
  group('OtpauthParser.parse', () {
    test('parses a full URI with issuer, digits, period, and algorithm', () {
      final result = OtpauthParser.parse(
        'otpauth://totp/ACME%20Co:john.doe@email.com'
        '?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co'
        '&algorithm=SHA256&digits=8&period=60',
      );
      expect(result.config.secret, 'JBSWY3DPEHPK3PXP');
      expect(result.config.algorithm, TotpAlgorithm.sha256);
      expect(result.config.digits, 8);
      expect(result.config.period, 60);
      expect(result.issuer, 'ACME Co');
      expect(result.account, 'john.doe@email.com');
    });

    test('defaults to SHA1, 6 digits, 30 s when parameters are omitted', () {
      final result =
          OtpauthParser.parse('otpauth://totp/Site?secret=JBSWY3DPEHPK3PXP');
      expect(result.config.algorithm, TotpAlgorithm.sha1);
      expect(result.config.digits, 6);
      expect(result.config.period, 30);
      expect(result.account, 'Site');
      expect(result.issuer, '');
    });

    test('reads the issuer from an "Issuer:account" label prefix', () {
      final result = OtpauthParser.parse(
        'otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP',
      );
      expect(result.issuer, 'GitHub');
      expect(result.account, 'octocat');
    });

    test('the issuer query parameter wins over the label prefix', () {
      final result = OtpauthParser.parse(
        'otpauth://totp/LabelIssuer:me?secret=JBSWY3DPEHPK3PXP'
        '&issuer=ParamIssuer',
      );
      expect(result.issuer, 'ParamIssuer');
      expect(result.account, 'me');
    });

    test('trims stray spaces after the label colon', () {
      final result = OtpauthParser.parse(
        'otpauth://totp/GitHub:%20octocat?secret=JBSWY3DPEHPK3PXP',
      );
      expect(result.account, 'octocat');
    });

    test('normalizes lowercase secrets from the URI', () {
      final result =
          OtpauthParser.parse('otpauth://totp/x?secret=jbswy3dpehpk3pxp');
      expect(result.config.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('rejects non-otpauth schemes', () {
      expect(
        () => OtpauthParser.parse('https://totp/x?secret=JBSWY3DPEHPK3PXP'),
        throwsFormatException,
      );
    });

    test('rejects hotp (counter-based) URIs', () {
      expect(
        () => OtpauthParser.parse('otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP'),
        throwsFormatException,
      );
    });

    test('rejects a URI without a usable secret', () {
      expect(
        () => OtpauthParser.parse('otpauth://totp/x?secret='),
        throwsFormatException,
      );
      expect(
        () => OtpauthParser.parse('otpauth://totp/x'),
        throwsFormatException,
      );
      expect(
        () => OtpauthParser.parse('otpauth://totp/x?secret=11111'),
        throwsFormatException,
      );
    });

    test('rejects unusable digits/period values', () {
      expect(
        () => OtpauthParser.parse(
          'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=4',
        ),
        throwsFormatException,
      );
      expect(
        () => OtpauthParser.parse(
          'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=0',
        ),
        throwsFormatException,
      );
    });
  });

  group('OtpauthParser.parseUserInput', () {
    test('accepts a bare base32 secret with spaces and lowercase', () {
      final config = OtpauthParser.parseUserInput('jbsw y3dp ehpk 3pxp');
      expect(config.secret, 'JBSWY3DPEHPK3PXP');
      expect(config.digits, 6);
      expect(config.period, 30);
    });

    test('accepts a full otpauth URI', () {
      final config = OtpauthParser.parseUserInput(
        'otpauth://totp/Site?secret=JBSWY3DPEHPK3PXP&digits=8',
      );
      expect(config.digits, 8);
    });

    test('rejects empty input and non-base32 text', () {
      expect(() => OtpauthParser.parseUserInput(''), throwsFormatException);
      expect(
        () => OtpauthParser.parseUserInput('password123!'),
        throwsFormatException,
      );
    });
  });

  group('OtpauthParser.toUri', () {
    test('round-trips config with custom parameters', () {
      const config = TotpConfig(
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.sha256,
        digits: 8,
        period: 60,
      );
      final uri =
          OtpauthParser.toUri(config, issuer: 'ACME Co', account: 'jo@ex.com');
      final parsed = OtpauthParser.parse(uri);
      expect(parsed.config, config);
      expect(parsed.issuer, 'ACME Co');
      expect(parsed.account, 'jo@ex.com');
    });

    test('omits default parameters from the URI', () {
      const config = TotpConfig(secret: 'JBSWY3DPEHPK3PXP');
      final uri = OtpauthParser.toUri(config);
      expect(uri.contains('digits'), isFalse);
      expect(uri.contains('period'), isFalse);
      expect(uri.contains('algorithm'), isFalse);
      expect(OtpauthParser.parse(uri).config, config);
    });
  });
}
