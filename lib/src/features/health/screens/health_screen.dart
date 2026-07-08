import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

final vaultHealthProvider = Provider<VaultHealthReport>((ref) {
  final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
  return VaultHealthAnalyzer.analyze(
    entries,
    now: ref.read(clockProvider).now(),
  );
});

/// Vault Health tab: overall score plus weak / reused / old password lists,
/// each row deep-linking to its entry.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(vaultHealthProvider);
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('Vault Health')),
      body: report.analyzedCount == 0
          ? const VaultEmptyState(
              icon: Icons.favorite_outline,
              message: 'Add entries with passwords and Vaultly will '
                  'check how healthy they are.',
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _ScoreCard(report: report),
                const SizedBox(height: AppSpacing.lg),
                if (report.isHealthy)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Icon(Icons.verified_outlined,
                              size: 40, color: AppColors.success(brightness)),
                          const SizedBox(height: AppSpacing.sm),
                          const Text('Everything looks great',
                              style: AppTextStyles.h3),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'No weak, reused, or old passwords found.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: scheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                _IssueSection(
                  title: 'Weak passwords',
                  subtitle: 'Easy to guess — replace them with generated '
                      'ones.',
                  icon: Icons.warning_amber_outlined,
                  color: AppColors.error(brightness),
                  entries: report.weak,
                ),
                _IssueSection(
                  title: 'Reused passwords',
                  subtitle: 'One leak would unlock several accounts.',
                  icon: Icons.copy_all_outlined,
                  color: AppColors.warning(brightness),
                  entries: report.reused,
                ),
                _IssueSection(
                  title: 'Old passwords',
                  subtitle: 'Unchanged for over a year.',
                  icon: Icons.history,
                  color: AppColors.info(brightness),
                  entries: report.old,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final VaultHealthReport report;

  Color _scoreColor(Brightness brightness) {
    if (report.score >= 90) return AppColors.success(brightness);
    if (report.score >= 70) return AppColors.info(brightness);
    if (report.score >= 50) return AppColors.warning(brightness);
    return AppColors.error(brightness);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final color = _scoreColor(brightness);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: report.score / 100),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      color: color,
                    ),
                  ),
                  Center(
                    child: Text('${report.score}',
                        style: AppTextStyles.numberLarge),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vault score', style: AppTextStyles.h3),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    report.isHealthy
                        ? 'All ${report.analyzedCount} passwords look '
                            'strong and fresh.'
                        : '${report.issueCount} thing'
                            '${report.issueCount == 1 ? '' : 's'} to fix '
                            'across ${report.analyzedCount} passwords.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: scheme.onSurfaceVariant),
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

class _IssueSection extends StatelessWidget {
  const _IssueSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.entries,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<VaultEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTextStyles.h3),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Text(
                '${entries.length}',
                style: AppTextStyles.numberSmall.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle,
            style: AppTextStyles.bodySmall
                .copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in entries)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: Icon(categoryIcon(entry.category),
                  color: scheme.onSurfaceVariant),
              title: Text(entry.title, style: AppTextStyles.h4),
              subtitle: entry.username.isEmpty
                  ? null
                  : Text(entry.username, maxLines: 1),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.entryDetail(entry.id)),
            ),
          ),
      ],
    );
  }
}
