import 'package:flutter/foundation.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';

/// Hash algorithm for TOTP code generation (RFC 6238).
enum TotpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256');

  const TotpAlgorithm(this.label);

  final String label;

  static TotpAlgorithm parse(String? raw) {
    final needle = (raw ?? '').trim().toUpperCase().replaceAll('-', '');
    return TotpAlgorithm.values.firstWhere(
      (a) => a.label == needle,
      orElse: () => TotpAlgorithm.sha1,
    );
  }
}

/// Everything needed to generate two-factor codes for one entry:
/// the shared secret plus its parameters.
@immutable
final class TotpConfig {
  const TotpConfig({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = defaultDigits,
    this.period = defaultPeriod,
  });

  factory TotpConfig.fromJson(Map<String, dynamic> json) => TotpConfig(
        secret: json['secret'] as String,
        algorithm: TotpAlgorithm.parse(json['algorithm'] as String?),
        digits: json['digits'] as int? ?? defaultDigits,
        period: json['period'] as int? ?? defaultPeriod,
      );

  static const int defaultDigits = 6;
  static const int defaultPeriod = 30;

  /// The base32-encoded shared secret, stored as the user provided it
  /// (normalized on use, not on storage).
  final String secret;
  final TotpAlgorithm algorithm;

  /// Code length; 6 or 8 in practice.
  final int digits;

  /// Seconds each code is valid for.
  final int period;

  /// Whether the secret decodes and the parameters are sane.
  bool get isValid =>
      Base32.isValid(secret) && digits >= 6 && digits <= 8 && period > 0;

  Map<String, dynamic> toJson() => {
        'secret': secret,
        'algorithm': algorithm.label,
        'digits': digits,
        'period': period,
      };

  @override
  bool operator ==(Object other) =>
      other is TotpConfig &&
      other.secret == secret &&
      other.algorithm == algorithm &&
      other.digits == digits &&
      other.period == period;

  @override
  int get hashCode => Object.hash(secret, algorithm, digits, period);
}
