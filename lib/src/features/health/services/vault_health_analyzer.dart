import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The three findings the health dashboard reports for one entry.
enum HealthIssue { weak, reused, old }

final class VaultHealthReport {
  const VaultHealthReport({
    required this.score,
    required this.analyzedCount,
    required this.weak,
    required this.reused,
    required this.old,
  });

  /// Overall vault score, 0–100. 100 when there is nothing to analyze.
  final int score;

  /// Number of entries that carry a password and were analyzed.
  final int analyzedCount;

  final List<VaultEntry> weak;
  final List<VaultEntry> reused;
  final List<VaultEntry> old;

  bool get isHealthy => weak.isEmpty && reused.isEmpty && old.isEmpty;

  int get issueCount => weak.length + reused.length + old.length;
}

/// Pure-Dart analysis of the vault's password hygiene.
///
/// - **Weak**: estimated strength below [StrengthLevel.good].
/// - **Reused**: the exact same password appears on more than one entry.
/// - **Old**: the password was last changed more than [oldAfter] ago.
///
/// Score: every entry starts perfect; each finding subtracts a weighted
/// penalty (weak 1.0, reused 0.8, old 0.4 — capped at 1.0 per entry), and
/// the score is the remaining fraction of the analyzed entries.
abstract final class VaultHealthAnalyzer {
  static const Duration oldAfter = Duration(days: 365);

  static const double _weakPenalty = 1.0;
  static const double _reusedPenalty = 0.8;
  static const double _oldPenalty = 0.4;

  static VaultHealthReport analyze(
    List<VaultEntry> entries, {
    required DateTime now,
  }) {
    final analyzed = entries.where((e) => e.password.isNotEmpty).toList();
    if (analyzed.isEmpty) {
      return const VaultHealthReport(
        score: 100,
        analyzedCount: 0,
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
        penalty += _weakPenalty;
      }
      if (passwordCounts[entry.password]! > 1) {
        reused.add(entry);
        penalty += _reusedPenalty;
      }
      if (now.difference(entry.passwordChangedAt) > oldAfter) {
        old.add(entry);
        penalty += _oldPenalty;
      }
      totalPenalty += penalty > 1.0 ? 1.0 : penalty;
    }

    final score = (100 * (1 - totalPenalty / analyzed.length)).round();
    return VaultHealthReport(
      score: score.clamp(0, 100),
      analyzedCount: analyzed.length,
      weak: weak,
      reused: reused,
      old: old,
    );
  }
}
