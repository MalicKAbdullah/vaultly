import 'package:vaultkey/src/core/background_worker.dart';
import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// The three findings the health dashboard reports for one entry.
enum HealthIssue { weak, reused, old }

final class VaultHealthReport {
  const VaultHealthReport({
    required this.score,
    required this.analyzedCount,
    required this.strongCount,
    required this.weak,
    required this.reused,
    required this.old,
  });

  /// Overall vault score, 0–100. 100 when there is nothing to analyze.
  final int score;

  /// Number of entries that carry a password and were analyzed.
  final int analyzedCount;

  /// Analyzed entries whose password is [StrengthLevel.strong].
  final int strongCount;

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
  }) =>
      _HealthFindings.compute(_HealthInput.of(entries, now)).reportFor(entries);

  /// [analyze] on [worker]. Only passwords and timestamps travel to the
  /// worker and only positions come back, so neither direction copies the
  /// entries themselves.
  static Future<VaultHealthReport> analyzeOn(
    IBackgroundWorker worker,
    List<VaultEntry> entries, {
    required DateTime now,
  }) async {
    final findings = await _findingsOn(worker, _HealthInput.of(entries, now));
    return findings.reportFor(entries);
  }

  // Separate from [analyzeOn] so the task closure captures only [input],
  // not the entries in the caller's frame.
  static Future<_HealthFindings> _findingsOn(
    IBackgroundWorker worker,
    _HealthInput input,
  ) =>
      worker.run(() => _HealthFindings.compute(input));
}

final class _HealthInput {
  _HealthInput.of(List<VaultEntry> entries, DateTime now)
      : passwords = [for (final e in entries) e.password],
        changedAt = [
          for (final e in entries) e.passwordChangedAt.microsecondsSinceEpoch,
        ],
        now = now.microsecondsSinceEpoch;

  final List<String> passwords;

  /// `passwordChangedAt` per entry, in microseconds since the epoch.
  final List<int> changedAt;
  final int now;
}

/// Analysis results as positions in the analyzed entry list.
final class _HealthFindings {
  const _HealthFindings({
    required this.score,
    required this.analyzedCount,
    required this.strongCount,
    required this.weak,
    required this.reused,
    required this.old,
  });

  factory _HealthFindings.compute(_HealthInput input) {
    final passwords = input.passwords;
    final passwordCounts = <String, int>{};
    var analyzedCount = 0;
    for (final password in passwords) {
      if (password.isEmpty) continue;
      analyzedCount++;
      passwordCounts.update(password, (c) => c + 1, ifAbsent: () => 1);
    }
    if (analyzedCount == 0) {
      return const _HealthFindings(
        score: 100,
        analyzedCount: 0,
        strongCount: 0,
        weak: [],
        reused: [],
        old: [],
      );
    }

    // Reused passwords are estimated once.
    final levels = <String, StrengthLevel>{};
    final oldAfter = VaultHealthAnalyzer.oldAfter.inMicroseconds;
    final weak = <int>[];
    final reused = <int>[];
    final old = <int>[];
    var strongCount = 0;
    var totalPenalty = 0.0;

    for (var i = 0; i < passwords.length; i++) {
      final password = passwords[i];
      if (password.isEmpty) continue;
      var penalty = 0.0;
      final level =
          levels[password] ??= StrengthEstimator.estimate(password).level;
      if (level == StrengthLevel.strong) strongCount++;
      if (level == StrengthLevel.weak || level == StrengthLevel.fair) {
        weak.add(i);
        penalty += VaultHealthAnalyzer._weakPenalty;
      }
      if (passwordCounts[password]! > 1) {
        reused.add(i);
        penalty += VaultHealthAnalyzer._reusedPenalty;
      }
      if (input.now - input.changedAt[i] > oldAfter) {
        old.add(i);
        penalty += VaultHealthAnalyzer._oldPenalty;
      }
      totalPenalty += penalty > 1.0 ? 1.0 : penalty;
    }

    final score = (100 * (1 - totalPenalty / analyzedCount)).round();
    return _HealthFindings(
      score: score.clamp(0, 100),
      analyzedCount: analyzedCount,
      strongCount: strongCount,
      weak: weak,
      reused: reused,
      old: old,
    );
  }

  final int score;
  final int analyzedCount;
  final int strongCount;
  final List<int> weak;
  final List<int> reused;
  final List<int> old;

  VaultHealthReport reportFor(List<VaultEntry> entries) => VaultHealthReport(
        score: score,
        analyzedCount: analyzedCount,
        strongCount: strongCount,
        weak: [for (final i in weak) entries[i]],
        reused: [for (final i in reused) entries[i]],
        old: [for (final i in old) entries[i]],
      );
}
