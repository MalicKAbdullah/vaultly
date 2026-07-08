import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';

void main() {
  group('StrengthEstimator', () {
    test('empty password is weak with zero bits', () {
      final s = StrengthEstimator.estimate('');
      expect(s.bits, 0);
      expect(s.level, StrengthLevel.weak);
    });

    test('short lowercase-only password is weak', () {
      // 8 chars × log2(26) ≈ 37.6 bits
      final s = StrengthEstimator.estimate('password');
      expect(s.bits, closeTo(37.6, 0.1));
      expect(s.level, StrengthLevel.weak);
    });

    test('longer lowercase password reaches fair', () {
      // 10 chars × log2(26) ≈ 47.0 bits
      final s = StrengthEstimator.estimate('abcdefghij');
      expect(s.level, StrengthLevel.fair);
    });

    test('mixed lowercase and digits mid-length is good', () {
      // 13 chars × log2(36) ≈ 67.2 bits
      final s = StrengthEstimator.estimate('abc123def456g');
      expect(s.level, StrengthLevel.good);
    });

    test('long full-charset password is strong', () {
      // 20 chars × log2(95) ≈ 131 bits
      final s = StrengthEstimator.estimate('kV9#mQ2x!pW7zR4t&Yc1');
      expect(s.bits, greaterThan(100));
      expect(s.level, StrengthLevel.strong);
    });

    test('charset grows per character class present', () {
      final lower = StrengthEstimator.estimate('abcdefgh').bits;
      final lowerUpper = StrengthEstimator.estimate('abcdefgH').bits;
      final lowerUpperDigit = StrengthEstimator.estimate('abcdef7H').bits;
      final all = StrengthEstimator.estimate('abcde!7H').bits;
      expect(lowerUpper, greaterThan(lower));
      expect(lowerUpperDigit, greaterThan(lowerUpper));
      expect(all, greaterThan(lowerUpperDigit));
    });

    test('repetition of a single character is capped as weak', () {
      // 24 a's would naively be ~113 bits.
      final s = StrengthEstimator.estimate('a' * 24);
      expect(s.bits, lessThanOrEqualTo(20));
      expect(s.level, StrengthLevel.weak);
    });

    test('very low variety (<=4 unique chars) is capped below fair', () {
      final s = StrengthEstimator.estimate('abababababababab1212');
      expect(s.bits, lessThanOrEqualTo(35));
      expect(s.level, StrengthLevel.weak);
    });

    test('level thresholds map bits to labels', () {
      expect(StrengthEstimator.estimate('zzzzzzz').level, StrengthLevel.weak);
      // 11 lowercase chars ≈ 51.7 bits → fair
      expect(
        StrengthEstimator.estimate('abcdefghijk').level,
        StrengthLevel.fair,
      );
      // 16 lowercase chars ≈ 75.2 bits → good
      expect(
        StrengthEstimator.estimate('abcdefghijklmnop').level,
        StrengthLevel.good,
      );
      // 18 lowercase chars ≈ 84.6 bits → strong
      expect(
        StrengthEstimator.estimate('abcdefghijklmnopqr').level,
        StrengthLevel.strong,
      );
    });

    test('ratio is clamped to 1.0', () {
      final s = StrengthEstimator.estimate('kV9#mQ2x!pW7zR4t&Yc1XX');
      expect(s.ratio, 1.0);
    });
  });
}
