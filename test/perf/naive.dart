import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The straightforward implementations the optimised code paths must match,
/// kept here as the reference for equivalence tests and benchmarks.
abstract final class Naive {
  /// Health analysis: every entry estimated, entry lists built directly.
  static VaultHealthReport analyze(
    List<VaultEntry> entries, {
    required DateTime now,
  }) {
    final analyzed = entries.where((e) => e.password.isNotEmpty).toList();
    if (analyzed.isEmpty) {
      return const VaultHealthReport(
        score: 100,
        analyzedCount: 0,
        strongCount: 0,
        weak: [],
        reused: [],
        old: [],
      );
    }
    final passwordCounts = <String, int>{};
    for (final entry in analyzed) {
      passwordCounts.update(entry.password, (c) => c + 1, ifAbsent: () => 1);
    }
    final weak = <VaultEntry>[];
    final reused = <VaultEntry>[];
    final old = <VaultEntry>[];
    var totalPenalty = 0.0;
    for (final entry in analyzed) {
      var penalty = 0.0;
      final level = StrengthEstimator.estimate(entry.password).level;
      if (level == StrengthLevel.weak || level == StrengthLevel.fair) {
        weak.add(entry);
        penalty += 1.0;
      }
      if (passwordCounts[entry.password]! > 1) {
        reused.add(entry);
        penalty += 0.8;
      }
      if (now.difference(entry.passwordChangedAt) >
          VaultHealthAnalyzer.oldAfter) {
        old.add(entry);
        penalty += 0.4;
      }
      totalPenalty += penalty > 1.0 ? 1.0 : penalty;
    }
    final score = (100 * (1 - totalPenalty / analyzed.length)).round();
    return VaultHealthReport(
      score: score.clamp(0, 100),
      analyzedCount: analyzed.length,
      // The overview's per-build count.
      strongCount: analyzed
          .where(
            (e) =>
                StrengthEstimator.estimate(e.password).level ==
                StrengthLevel.strong,
          )
          .length,
      weak: weak,
      reused: reused,
      old: old,
    );
  }

  /// A-to-Z sort lower-casing both titles in every comparison.
  static List<VaultEntry> sortAlphabetical(List<VaultEntry> entries) =>
      List.of(entries)
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
}
