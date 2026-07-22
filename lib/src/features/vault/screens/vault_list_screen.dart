import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/features/backup/providers/backup_providers.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

/// Home tab: searchable, filterable list of vault entries.
class VaultListScreen extends ConsumerWidget {
  const VaultListScreen({super.key});

  Future<void> _copySensitive(
    BuildContext context,
    WidgetRef ref,
    String value,
    String what,
  ) async {
    await ref.read(clipboardGuardProvider).copySensitive(value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what copied. It clears in 30 seconds.')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    VaultEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${entry.title}"?'),
        content: const Text(
          'This removes the entry and its password history. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(vaultEntriesProvider.notifier).delete(entry.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(filteredEntriesProvider);
    final query = ref.watch(vaultQueryProvider);
    final banner = ref.watch(backupBannerProvider);
    // Narrow watch: only the empty-vs-non-empty flip drives the empty state,
    // so entry edits don't rebuild the whole screen through this path.
    final isEmptyVault = ref.watch(
      vaultEntriesProvider.select((v) => (v.valueOrNull ?? const []).isEmpty),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          PopupMenuButton<VaultSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: query.sort,
            onSelected: (s) => ref.read(vaultQueryProvider.notifier).setSort(s),
            itemBuilder: (context) => [
              for (final sort in VaultSort.values)
                PopupMenuItem(value: sort, child: Text(sort.label)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newEntry),
        icon: const Icon(Icons.add),
        label: const Text('New entry'),
      ),
      body: Column(
        children: [
          const _UpdateBannerCard(),
          if (banner != null) _BackupBanner(message: banner),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              onChanged: (v) =>
                  ref.read(vaultQueryProvider.notifier).setSearch(v),
              decoration: const InputDecoration(
                hintText: 'Search title, username, or website',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                FilterChip(
                  label: const Text('Favorites'),
                  avatar: const Icon(Icons.star_outline, size: 16),
                  selected: query.favoritesOnly,
                  onSelected: (_) => ref
                      .read(vaultQueryProvider.notifier)
                      .toggleFavoritesOnly(),
                ),
                const SizedBox(width: AppSpacing.sm),
                for (final category in EntryCategory.values) ...[
                  FilterChip(
                    label: Text(category.label),
                    selected: query.category == category,
                    onSelected: (selected) => ref
                        .read(vaultQueryProvider.notifier)
                        .setCategory(selected ? category : null),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? VaultEmptyState(
                    icon: isEmptyVault ? Icons.lock_outline : Icons.search_off,
                    message: isEmptyVault
                        ? 'Your vault is empty.\nAdd your first password '
                            'to get started.'
                        : 'Nothing matches your search.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      96,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: EntryTile(
                            entry: entry,
                            onTap: () =>
                                context.push(AppRoutes.entryDetail(entry.id)),
                            onCopyPassword: () => _copySensitive(
                                context, ref, entry.password, 'Password'),
                            onCopyUsername: () => _copySensitive(
                                context, ref, entry.username, 'Username'),
                            onEdit: () =>
                                context.push(AppRoutes.editEntry(entry.id)),
                            onDelete: () => _confirmDelete(context, ref, entry),
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

class _BackupBanner extends StatelessWidget {
  const _BackupBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: brightness == Brightness.dark
            ? AppColors.warningContainerDark
            : AppColors.warningContainerLight,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 18, color: AppColors.warning(brightness)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.warning(brightness)),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Update available" card, shown when a newer GitHub release exists and the
/// user hasn't dismissed it this session.
class _UpdateBannerCard extends ConsumerWidget {
  const _UpdateBannerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateCheckProvider).valueOrNull;
    final dismissed = ref.watch(updateDismissedProvider);
    if (info == null || dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: UpdateBanner(
        info: info,
        onUpdate: () => ref.read(updateServiceProvider).openDownload(info),
        onDismiss: () =>
            ref.read(updateDismissedProvider.notifier).state = true,
      ),
    );
  }
}
