import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/base32.dart';

/// Generates RFC 6238 time-based one-time codes (HMAC-SHA1 / HMAC-SHA256,
/// 6–8 digits, configurable period).
abstract final class TotpGenerator {
  /// The code for [config] at [time]. Throws [FormatException] when the
  /// secret is not valid base32.
  static String codeAt(TotpConfig config, DateTime time) {
    final counter =
        time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ config.period;
    return _hotp(config, counter);
  }

  /// Seconds until the code at [time] rolls over to the next one.
  static int secondsRemaining(TotpConfig config, DateTime time) {
    final elapsed = time.toUtc().millisecondsSinceEpoch ~/ 1000 % config.period;
    return config.period - elapsed;
  }

  /// Fraction of the current period already elapsed, in [0, 1).
  static double fractionElapsed(TotpConfig config, DateTime time) {
    final periodMs = config.period * 1000;
    return (time.toUtc().millisecondsSinceEpoch % periodMs) / periodMs;
  }

  /// Groups a code for display: `123456` → `123 456`, `12345678` → `1234 5678`.
  static String group(String code) {
    if (code.length.isOdd || code.length < 6) return code;
    final half = code.length ~/ 2;
    return '${code.substring(0, half)} ${code.substring(half)}';
  }

  static String _hotp(TotpConfig config, int counter) {
    final key = Base32.decode(config.secret);
    final message = Uint8List(8);
    ByteData.view(message.buffer).setUint64(0, counter);

    final hash = switch (config.algorithm) {
      TotpAlgorithm.sha1 => Hmac(sha1, key),
      TotpAlgorithm.sha256 => Hmac(sha256, key),
    }
        .convert(message)
        .bytes;

    // Dynamic truncation (RFC 4226 §5.3).
    final offset = hash[hash.length - 1] & 0x0F;
    final binary = ((hash[offset] & 0x7F) << 24) |
        ((hash[offset + 1] & 0xFF) << 16) |
        ((hash[offset + 2] & 0xFF) << 8) |
        (hash[offset + 3] & 0xFF);

    final modulus = _pow10(config.digits);
    return (binary % modulus).toString().padLeft(config.digits, '0');
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
