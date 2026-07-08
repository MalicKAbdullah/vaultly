import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';

import 'fakes/fakes.dart';

void main() {
  final now = DateTime(2026, 7, 5);
  const strongA = 'kV9#mQ2x!pW7zR4t';
  const strongB = 'Xt3\$nB8y?qL5wA6u';

  group('VaultHealthAnalyzer', () {
    test('empty vault scores 100 with no findings', () {
      final report = VaultHealthAnalyzer.analyze(const [], now: now);
      expect(report.score, 100);
      expect(report.analyzedCount, 0);
      expect(report.isHealthy, isTrue);
    });

    test('entries without passwords are not analyzed', () {
      final report = VaultHealthAnalyzer.analyze(
        [makeEntry(id: 'note', password: '')],
        now: now,
      );
      expect(report.analyzedCount, 0);
      expect(report.score, 100);
    });

    test('healthy vault: strong, unique, fresh passwords', () {
      final report = VaultHealthAnalyzer.analyze(
        [
          makeEntry(id: 'a', password: strongA, passwordChangedAt: now),
          makeEntry(id: 'b', password: strongB, passwordChangedAt: now),
        ],
        now: now,
      );
      expect(report.score, 100);
      expect(report.isHealthy, isTrue);
      expect(report.issueCount, 0);
    });

    group('weak detection', () {
      test('flags weak and fair passwords (below good)', () {
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(id: 'weak', password: 'abc12345'),
            makeEntry(id: 'fair', password: 'abcdefghijk'),
            makeEntry(id: 'good', password: 'abcdefghijklmnop'),
            makeEntry(id: 'strong', password: strongA),
          ],
          now: now,
        );
        expect(report.weak.map((e) => e.id), ['weak', 'fair']);
      });
    });

    group('reused detection', () {
      test('flags every entry sharing a password', () {
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(id: 'a', password: strongA),
            makeEntry(id: 'b', password: strongA),
            makeEntry(id: 'c', password: strongB),
          ],
          now: now,
        );
        expect(report.reused.map((e) => e.id), ['a', 'b']);
      });

      test('same password three times flags all three', () {
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(id: 'a', password: strongA),
            makeEntry(id: 'b', password: strongA),
            makeEntry(id: 'c', password: strongA),
          ],
          now: now,
        );
        expect(report.reused.length, 3);
      });
    });

    group('old detection', () {
      test('flags passwords unchanged for more than a year', () {
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(
              id: 'old',
              password: strongA,
              passwordChangedAt: now.subtract(const Duration(days: 366)),
            ),
            makeEntry(
              id: 'fresh',
              password: strongB,
              passwordChangedAt: now.subtract(const Duration(days: 200)),
            ),
          ],
          now: now,
        );
        expect(report.old.map((e) => e.id), ['old']);
      });

      test('exactly 365 days is not old yet', () {
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(
              id: 'edge',
              password: strongA,
              passwordChangedAt: now.subtract(const Duration(days: 365)),
            ),
          ],
          now: now,
        );
        expect(report.old, isEmpty);
      });
    });

    group('score', () {
      test('one weak entry among four costs a quarter', () {
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(id: 'a', password: 'abc12345'),
            makeEntry(id: 'b', password: strongA),
            makeEntry(id: 'c', password: strongB),
            makeEntry(id: 'd', password: 'Xq7&vC2m!fD9jK1s'),
          ],
          now: now,
        );
        expect(report.score, 75);
      });

      test('per-entry penalty is capped even with multiple findings', () {
        // Weak + reused + old on both entries: capped at 1.0 each → 0.
        final report = VaultHealthAnalyzer.analyze(
          [
            makeEntry(
              id: 'a',
              password: 'abc',
              passwordChangedAt: now.subtract(const Duration(days: 400)),
            ),
            makeEntry(
              id: 'b',
              password: 'abc',
              passwordChangedAt: now.subtract(const Duration(days: 400)),
            ),
          ],
          now: now,
        );
        expect(report.score, 0);
        expect(report.weak.length, 2);
        expect(report.reused.length, 2);
        expect(report.old.length, 2);
      });

      test('old alone costs less than weak alone', () {
        final oldOnly = VaultHealthAnalyzer.analyze(
          [
            makeEntry(
              id: 'a',
              password: strongA,
              passwordChangedAt: now.subtract(const Duration(days: 400)),
            ),
            makeEntry(id: 'b', password: strongB),
          ],
          now: now,
        );
        final weakOnly = VaultHealthAnalyzer.analyze(
          [
            makeEntry(id: 'a', password: 'abc12345'),
            makeEntry(id: 'b', password: strongB),
          ],
          now: now,
        );
        expect(oldOnly.score, greaterThan(weakOnly.score));
        expect(oldOnly.score, 80); // 100 × (1 − 0.4/2)
        expect(weakOnly.score, 50); // 100 × (1 − 1.0/2)
      });
    });
  });
}
