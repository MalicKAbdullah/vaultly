import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/providers/autofill_providers.dart';
import 'package:vaultkey/src/features/autofill/services/autofill_matcher.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';

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
    final c = SuiteColors.of(context);
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
              AppSpacing.gutter,
              AppSpacing.xs,
              AppSpacing.gutter,
              0,
            ),
            child: Text(
              'Choose what to fill into ${_targetLabel(request)}.',
              style: AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: AppSearchField(
              hint: 'Search all entries',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.gutter),
                    child: AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No entries found',
                      message: 'Search to look through your whole vault.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      AppSpacing.lg,
                    ),
                    children: [
                      SectionHeader(
                        title: filtered ? 'Best matches' : 'All entries',
                        subtitle: filtered
                            ? 'Search to see everything'
                            : '${entries.length} items',
                      ),
                      RowGroup(
                        separatorIndent: 72,
                        children: [
                          for (final entry in entries)
                            AppListRow(
                              leading: EntryAvatar(entry: entry, size: 42),
                              title: entry.title,
                              subtitle: entry.username.isEmpty
                                  ? null
                                  : entry.username,
                              showChevron: true,
                              onTap: () => _pick(entry),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
