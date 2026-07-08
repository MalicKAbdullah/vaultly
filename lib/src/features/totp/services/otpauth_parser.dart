import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';

/// A parsed `otpauth://totp/...` URI: the [config] plus the label parts
/// (issuer and account) that identify where the code belongs.
final class OtpauthResult {
  const OtpauthResult({
    required this.config,
    this.issuer = '',
    this.account = '',
  });

  final TotpConfig config;
  final String issuer;
  final String account;
}

/// Parses `otpauth://totp/...` URIs from authenticator QR codes and
/// "can't scan?" setup pages.
abstract final class OtpauthParser {
  /// Whether [input] looks like an otpauth URI (vs. a bare secret).
  static bool looksLikeUri(String input) =>
      input.trim().toLowerCase().startsWith('otpauth://');

  /// Parses [input] into an [OtpauthResult].
  /// Throws [FormatException] with a friendly message when it can't.
  static OtpauthResult parse(String input) {
    final Uri uri;
    try {
      uri = Uri.parse(input.trim());
    } catch (_) {
      throw const FormatException('That does not look like a valid link.');
    }
    if (uri.scheme.toLowerCase() != 'otpauth') {
      throw const FormatException(
        'That does not look like an otpauth:// link.',
      );
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw const FormatException(
        'Only time-based (TOTP) codes are supported.',
      );
    }

    final params = uri.queryParameters;
    final secret = params['secret'] ?? '';
    if (!Base32.isValid(secret)) {
      throw const FormatException('This link has no usable secret in it.');
    }

    // Label: "Issuer:account" or just "account" (pathSegments arrive
    // percent-decoded), possibly with stray spaces after the colon.
    final label = uri.pathSegments.join('/').trim();
    var issuer = (params['issuer'] ?? '').trim();
    var account = label;
    final colon = label.indexOf(':');
    if (colon != -1) {
      final labelIssuer = label.substring(0, colon).trim();
      account = label.substring(colon + 1).trim();
      if (issuer.isEmpty) issuer = labelIssuer;
    }

    final digits = int.tryParse(params['digits'] ?? '');
    final period = int.tryParse(params['period'] ?? '');
    final config = TotpConfig(
      secret: Base32.normalize(secret),
      algorithm: TotpAlgorithm.parse(params['algorithm']),
      digits: digits ?? TotpConfig.defaultDigits,
      period: period ?? TotpConfig.defaultPeriod,
    );
    if (!config.isValid) {
      throw const FormatException('This link has settings Vaultly '
          'cannot handle (unusual code length or timing).');
    }
    return OtpauthResult(config: config, issuer: issuer, account: account);
  }

  /// Builds an otpauth URI for [config] (used by CSV export so other
  /// apps can import the two-factor secret).
  static String toUri(
    TotpConfig config, {
    String issuer = '',
    String account = '',
  }) {
    final label = [
      if (issuer.isNotEmpty) issuer,
      if (account.isNotEmpty) account,
    ].join(':');
    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      path: '/${label.isEmpty ? 'Vaultly' : label}',
      queryParameters: {
        'secret': Base32.normalize(config.secret),
        if (issuer.isNotEmpty) 'issuer': issuer,
        if (config.algorithm != TotpAlgorithm.sha1)
          'algorithm': config.algorithm.label,
        if (config.digits != TotpConfig.defaultDigits)
          'digits': config.digits.toString(),
        if (config.period != TotpConfig.defaultPeriod)
          'period': config.period.toString(),
      },
    ).toString();
  }

  /// Interprets user input that is either an otpauth URI or a bare base32
  /// secret. Throws [FormatException] when neither works.
  static TotpConfig parseUserInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter a secret or paste a setup link.');
    }
    if (looksLikeUri(trimmed)) return parse(trimmed).config;
    if (!Base32.isValid(trimmed)) {
      throw const FormatException(
        'This secret has characters that do not belong. Check for typos — '
        'secrets use letters A–Z and digits 2–7.',
      );
    }
    return TotpConfig(secret: Base32.normalize(trimmed));
  }
}
