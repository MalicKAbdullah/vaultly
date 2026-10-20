import 'dart:math' as math;

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

final vaultHealthProvider = Provider<VaultHealthReport>((ref) {
  final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
  return VaultHealthAnalyzer.analyze(
    entries,
    now: ref.read(clockProvider).now(),
  );
});

/// The semantic colour of a health score.
Color healthTone(int score, SuiteColors c) {
  if (score >= 90) return c.positive;
  if (score >= 70) return c.info;
  if (score >= 50) return c.warning;
  return c.negative;
}

/// The one-word verdict for a health score.
String healthLabel(int score) {
  if (score >= 90) return 'Excellent';
  if (score >= 70) return 'Good';
  if (score >= 50) return 'Fair';
  return 'At risk';
}

/// The score in hero type with a quiet "/100".
class HealthScoreFigure extends StatelessWidget {
  const HealthScoreFigure({required this.score, this.style, super.key});

  final int score;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final big = (style ?? AppTextStyles.hero).copyWith(color: c.textPrimary);
    return Semantics(
      label: 'Health score $score out of 100',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$score', style: big),
            TextSpan(
              text: ' /100',
              style: AppTextStyles.h3.copyWith(
                color: c.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft pill carrying a status word in its semantic colour.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelStrong.copyWith(
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Security tab: the health score as a ring, the three kinds of finding
/// as a breakdown, then each affected item linking to its entry.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(vaultHealthProvider);
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
    final now = ref.watch(clockProvider).now();
    final c = SuiteColors.of(context);

    final counts = <String, int>{};
    for (final e in entries) {
      if (e.password.isEmpty) continue;
      counts.update(e.password, (n) => n + 1, ifAbsent: () => 1);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            TabHeader(
              eyebrow: report.analyzedCount == 0
                  ? 'Password health'
                  : '${report.analyzedCount} passwords checked',
              title: 'Security',
            ),
            if (report.analyzedCount == 0)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.xxl,
                  AppSpacing.gutter,
                  0,
                ),
                child: AppEmptyState(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Nothing to check yet',
                  message: 'Add entries with passwords and Vaultly will '
                      'check how healthy they are.',
                ),
              )
            else
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ScoreCard(report: report),
                    if (report.isHealthy) ...[
                      const SizedBox(height: AppSpacing.smd),
                      VaultCard(
                        child: Row(
                          children: [
                            IconBadge(
                              icon: Icons.verified_outlined,
                              color: c.positive,
                              size: 48,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Everything looks great',
                                    style: AppTextStyles.h3.copyWith(
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'No weak, reused, or old passwords found.',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _IssueSection(
                      title: 'Weak passwords',
                      subtitle: 'Easy to guess. Replace them with generated '
                          'ones.',
                      color: c.negative,
                      entries: report.weak,
                      detail: (e) => StrengthEstimator.estimate(e.password)
                          .level
                          .label,
                    ),
                    _IssueSection(
                      title: 'Reused passwords',
                      subtitle: 'One leak would unlock several accounts.',
                      color: c.warning,
                      entries: report.reused,
                      detail: (e) => 'On ${counts[e.password]} items',
                    ),
                    _IssueSection(
                      title: 'Old passwords',
                      subtitle: 'Unchanged for over a year.',
                      color: c.info,
                      entries: report.old,
                      detail: (e) => relativeAge(e.passwordChangedAt, now),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final VaultHealthReport report;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final tone = healthTone(report.score, c);
    final total = report.analyzedCount;
    final clean = total -
        {...report.weak, ...report.reused, ...report.old}
            .map((e) => e.id)
            .toSet()
            .length;

    Widget row(String label, int count, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ChartLegendRow(
            color: color,
            label: label,
            value: Text(
              '$count',
              style: AppTextStyles.number.copyWith(color: c.textPrimary),
            ),
          ),
        );

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        side: BorderSide(color: c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Vault health',
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
                const Spacer(),
                StatusPill(label: healthLabel(report.score), color: tone),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: SizedBox.square(
                dimension: 188,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: report.score / 100),
                  duration: AppMotion.slow,
                  curve: AppMotion.emphasized,
                  builder: (context, value, child) => CustomPaint(
                    painter: _RingPainter(
                      value: value,
                      color: tone,
                      track: c.surfaceAlt,
                    ),
                    child: child,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${report.score}',
                          style: AppTextStyles.hero.copyWith(
                            color: c.textPrimary,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'out of 100',
                          style: AppTextStyles.caption.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              report.isHealthy
                  ? 'All $total passwords look strong and fresh.'
                  : '${report.issueCount} thing'
                      '${report.issueCount == 1 ? '' : 's'} to fix '
                      'across $total passwords.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.mdl),
            SegmentedBar(
              values: [
                clean.toDouble(),
                report.weak.length.toDouble(),
                report.reused.length.toDouble(),
                report.old.length.toDouble(),
              ],
              colors: [c.positive, c.negative, c.warning, c.info],
            ),
            const SizedBox(height: AppSpacing.md),
            row('Healthy', clean, c.positive),
            row('Weak', report.weak.length, c.negative),
            row('Reused', report.reused.length, c.warning),
            row('Old', report.old.length, c.info),
          ],
        ),
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

class _IssueSection extends StatelessWidget {
  const _IssueSection({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.entries,
    required this.detail,
  });

  final String title;
  final String subtitle;
  final Color color;
  final List<VaultEntry> entries;
  final String Function(VaultEntry) detail;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final c = SuiteColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: StatusPill(label: '${entries.length}', color: color),
        ),
        RowGroup(
          separatorIndent: 72,
          children: [
            for (final entry in entries)
              AppListRow(
                leading: EntryAvatar(entry: entry, size: 42),
                title: entry.title,
                subtitle: entry.username.isEmpty ? null : entry.username,
                trailing: Text(
                  detail(entry),
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
                showChevron: true,
                onTap: () => context.push(AppRoutes.entryDetail(entry.id)),
              ),
          ],
        ),
      ],
    );
  }
}
