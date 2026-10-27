import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/features/importers/models/imported_item.dart';
import 'package:vaultkey/src/features/importers/services/import_planner.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Shows what an export contains and how it lands in the vault (counts,
/// duplicates with a skip / merge / keep-both choice, records that cannot be
/// imported), then writes it into the encrypted vault.
class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({required this.batch, super.key});

  final ImportBatch batch;

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  static const _uuid = Uuid();
  DuplicateAction _action = DuplicateAction.skip;
  bool _busy = false;

  ImportOutcome _plan({required bool dryRun}) {
    var n = 0;
    return ImportPlanner.apply(
      current: ref.read(vaultEntriesProvider).valueOrNull ?? const [],
      batch: widget.batch,
      action: _action,
      now: ref.read(clockProvider).now(),
      newId: dryRun ? () => 'preview-${n++}' : _uuid.v4,
    );
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final outcome = _plan(dryRun: false);
    await ref.read(vaultEntriesProvider.notifier).replaceAll(outcome.entries);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_doneMessage(outcome))),
    );
    context.go(AppRoutes.vault);
  }

  static String _plural(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  String _doneMessage(ImportOutcome o) {
    final parts = [
      if (o.added > 0) '${_plural(o.added, 'item', 'items')} added',
      if (o.merged > 0) '${o.merged} merged',
      if (o.totpAttached > 0)
        '${_plural(o.totpAttached, 'code', 'codes')} attached',
      if (o.totpCreated > 0) '${o.totpCreated} new code items',
    ];
    return parts.isEmpty ? 'Nothing new to import.' : '${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final batch = widget.batch;
    final outcome = _plan(dryRun: true);
    final duplicates = outcome.duplicates;

    return Scaffold(
      appBar: AppBar(title: const Text('Review import')),
      bottomNavigationBar: BottomActionBar(
        primary: VaultButton(
          label: outcome.changes == 0
              ? 'Nothing to import'
              : 'Import ${_plural(outcome.changes, 'change', 'changes')}',
          isLoading: _busy,
          onPressed: _busy || outcome.changes == 0 ? null : _import,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          Text(
            batch.source.label,
            style: AppTextStyles.overline.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            batch.isEmpty
                ? 'Nothing to import'
                : [
                    if (batch.items.isNotEmpty)
                      _plural(batch.items.length, 'item', 'items'),
                    if (batch.authenticators.isNotEmpty)
                      _plural(batch.authenticators.length, 'authenticator code',
                          'authenticator codes'),
                  ].join(' · '),
            style: AppTextStyles.h2.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AppSpacing.lg),
          RowGroup(
            separatorIndent: AppSpacing.gutter,
            children: [
              _CountRow(label: 'New items', value: outcome.added),
              if (batch.items.isNotEmpty)
                _CountRow(
                  label: 'Already in your vault',
                  value: duplicates.length,
                ),
              if (batch.authenticators.isNotEmpty) ...[
                _CountRow(
                  label: 'Codes added to existing logins',
                  value: outcome.totpAttached,
                ),
                _CountRow(
                  label: 'Codes saved as new items',
                  value: outcome.totpCreated,
                ),
                if (outcome.totpAlreadyPresent > 0)
                  _CountRow(
                    label: 'Codes you already have',
                    value: outcome.totpAlreadyPresent,
                  ),
              ],
            ],
          ),
          if (duplicates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Duplicates',
              subtitle: 'Same website and username as an item you have',
            ),
            AppSegmentedControl<DuplicateAction>(
              height: 44,
              segments: [
                for (final a in DuplicateAction.values)
                  AppSegment(value: a, label: a.label),
              ],
              selected: _action,
              onChanged: (a) => setState(() => _action = a),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _action.description,
              style: AppTextStyles.caption.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            RowGroup(
              separatorIndent: AppSpacing.gutter,
              children: [
                for (final d in duplicates.take(50))
                  AppListRow(
                    dense: true,
                    title: d.existing.title,
                    subtitle: d.existing.username.isEmpty
                        ? null
                        : d.existing.username,
                  ),
                if (duplicates.length > 50)
                  AppListRow(
                    dense: true,
                    title: 'and ${duplicates.length - 50} more',
                  ),
              ],
            ),
          ],
          if (batch.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppBanner(
              kind: BannerKind.warning,
              icon: Icons.info_outline_rounded,
              title: '${_plural(batch.warnings.length, 'record', 'records')} '
                  'need attention',
              message: batch.warnings.take(20).join('\n'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Imported items are encrypted into your vault. Vaultly keeps no '
            'copy of the export file; delete it from your device once you '
            'are done.',
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return AppListRow(
      dense: true,
      title: label,
      trailing: Text(
        '$value',
        style: AppTextStyles.number.copyWith(color: c.textPrimary),
      ),
    );
  }
}
