import 'dart:math';

enum StrengthLevel {
  weak('Weak'),
  fair('Fair'),
  good('Good'),
  strong('Strong');

  const StrengthLevel(this.label);

  final String label;
}

final class PasswordStrength {
  const PasswordStrength({required this.bits, required this.level});

  /// Estimated entropy in bits.
  final double bits;
  final StrengthLevel level;

  /// 0.0–1.0 progress value for meters.
  double get ratio => min(1.0, bits / 100.0);
}

/// Entropy-based password strength estimation.
///
/// Model: bits = length × log2(charset size), where the charset is the union
/// of character classes actually present. Passwords built from very few
/// distinct characters are capped, since repetition adds no real entropy.
abstract final class StrengthEstimator {
  static const double weakBelowBits = 40;
  static const double fairBelowBits = 60;
  static const double goodBelowBits = 80;

  static final RegExp _lower = RegExp('[a-z]');
  static final RegExp _upper = RegExp('[A-Z]');
  static final RegExp _digit = RegExp('[0-9]');
  static final RegExp _symbol = RegExp('[^a-zA-Z0-9]');

  static PasswordStrength estimate(String password) {
    if (password.isEmpty) {
      return const PasswordStrength(bits: 0, level: StrengthLevel.weak);
    }

    var charset = 0;
    if (_lower.hasMatch(password)) charset += 26;
    if (_upper.hasMatch(password)) charset += 26;
    if (_digit.hasMatch(password)) charset += 10;
    if (_symbol.hasMatch(password)) charset += 33;

    var bits = password.length * (log(charset) / ln2);

    // Repetition penalty: a password made of very few distinct characters
    // carries far less entropy than its length suggests.
    final unique = password.split('').toSet().length;
    if (unique <= 2) {
      bits = min(bits, 20);
    } else if (unique <= 4) {
      bits = min(bits, 35);
    }

    return PasswordStrength(bits: bits, level: _level(bits));
  }

  static StrengthLevel _level(double bits) {
    if (bits < weakBelowBits) return StrengthLevel.weak;
    if (bits < fairBelowBits) return StrengthLevel.fair;
    if (bits < goodBelowBits) return StrengthLevel.good;
    return StrengthLevel.strong;
  }
}
