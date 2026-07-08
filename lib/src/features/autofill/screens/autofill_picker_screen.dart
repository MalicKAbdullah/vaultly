import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/providers/autofill_providers.dart';
import 'package:vaultkey/src/features/autofill/services/autofill_matcher.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

/// Slim entry picker shown when another app asked Vaultly to fill a login
/// form. Pre-filtered by the requesting domain/app; searching switches to
/// the full list. Picking an entry hands the credentials back to Android.
class AutofillPickerScreen extends ConsumerStatefulWidget {
  const AutofillPickerScreen({super.key});

  @override
  ConsumerState<AutofillPickerScreen> createState() =>
      _AutofillPickerScreenState();
}

class _AutofillPickerScreenState extends ConsumerState<AutofillPickerScreen> {
  String _search = '';
  bool _busy = false;

  Future<void> _pick(VaultEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(autofillRequestProvider.notifier).complete(entry);
    // Android finishes the activity; nothing more to do here.
  }

  Future<void> _cancel() async {
    await ref.read(autofillRequestProvider.notifier).cancel();
  }

  String _targetLabel(AutofillFillRequest request) {
    final domain = (request.domain ?? '').trim();
    if (domain.isNotEmpty) return domain;
    final package = (request.package ?? '').trim();
    if (package.isNotEmpty) return package;
    return 'the app';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final request = ref.watch(autofillRequestProvider).valueOrNull ??
        const AutofillFillRequest();
    final all = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];

    final needle = _search.trim().toLowerCase();
    final List<VaultEntry> entries;
    final bool filtered;
    if (needle.isNotEmpty) {
      filtered = false;
      entries = [
        for (final e in all)
          if (e.title.toLowerCase().contains(needle) ||
              e.username.toLowerCase().contains(needle) ||
              e.url.toLowerCase().contains(needle))
            e,
      ];
    } else {
      final matches = AutofillMatcher.rank(all, request);
      filtered = matches.isNotEmpty;
      entries = filtered ? matches : all;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill a password'),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: _cancel,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: Text(
              'Choose what to fill into ${_targetLabel(request)}.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                hintText: 'Search all entries',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (filtered)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                'Best matches — search to see everything.',
                style: AppTextStyles.caption
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: entries.isEmpty
                ? const VaultEmptyState(
                    icon: Icons.search_off,
                    message: 'No entries found.\nSearch to look through '
                        'your whole vault.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: VaultCard(
                          onTap: () => _pick(entry),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm + 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.borderRadius),
                                ),
                                child: Icon(
                                  categoryIcon(entry.category),
                                  size: 20,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      style: AppTextStyles.h4,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (entry.username.isNotEmpty)
                                      Text(
                                        entry.username,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_right,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
