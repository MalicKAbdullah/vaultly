import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/core/startup_timeline.dart';
import 'package:vaultkey/src/core/ui/sliver_row_group.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/backup/providers/backup_providers.dart';
import 'package:vaultkey/src/features/health/screens/health_screen.dart';
import 'package:vaultkey/src/features/health/services/vault_health_analyzer.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

/// Home tab: the search field, the vault at a glance (health, two-factor
/// coverage), filters, and the items grouped into favorites and the rest.
/// While a search or filter is active the summary steps aside for results.
class VaultListScreen extends ConsumerStatefulWidget {
  const VaultListScreen({super.key});

  @override
  ConsumerState<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends ConsumerState<VaultListScreen> {
  static final _eyebrowFormat = DateFormat('EEEE, d MMMM');

  late final TextEditingController _search =
      TextEditingController(text: ref.read(vaultQueryProvider).search);
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _copySensitive(String value, String what) async {
    final guard = ref.read(clipboardGuardProvider);
    await guard.copySensitive(value);
    if (!mounted) return;
    showCopiedSnack(context, what: what, clearsAfter: guard.clearAfter);
  }

  Future<void> _confirmDelete(VaultEntry entry) async {
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
            style: TextButton.styleFrom(
              foregroundColor: SuiteColors.of(context).negative,
            ),
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

  void _setSearch(String value) =>
      ref.read(vaultQueryProvider.notifier).setSearch(value);

  void _clearSearch() {
    _search.clear();
    _setSearch('');
  }

  /// Enter in the search field opens the best match, so a lookup is
  /// "type, Enter" without touching the list.
  void _openFirst() {
    final results = ref.read(filteredEntriesProvider);
    if (results.isEmpty) return;
    context.push(AppRoutes.entryDetail(results.first.id));
  }

  Widget _tile(VaultEntry entry) => EntryTile(
        key: ValueKey(entry.id),
        entry: entry,
        onTap: () => context.push(AppRoutes.entryDetail(entry.id)),
        onCopyPassword: () => _copySensitive(entry.password, 'Password'),
        onCopyUsername: () => _copySensitive(entry.username, 'Username'),
        onEdit: () => context.push(AppRoutes.editEntry(entry.id)),
        onDelete: () => _confirmDelete(entry),
      );

  List<Widget> _group(String title, String? subtitle, List<VaultEntry> list) {
    if (list.isEmpty) return const [];
    return _section(
      title,
      subtitle,
      SliverRowGroup(
        separatorIndent: 74,
        itemCount: list.length,
        itemBuilder: (_, i) => _tile(list[i]),
      ),
    );
  }

  List<Widget> _section(String title, String? subtitle, Widget group) => [
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(title: title, subtitle: subtitle),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          sliver: group,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final entries = ref.watch(filteredEntriesProvider);
    final vault = ref.watch(vaultEntriesProvider);
    final all = vault.valueOrNull ?? const [];
    final query = ref.watch(vaultQueryProvider);
    final banner = ref.watch(backupBannerProvider);
    final now = ref.watch(clockProvider).now();
    final browsing = query.search.trim().isEmpty &&
        query.category == null &&
        !query.favoritesOnly;

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: TabHeader(
          eyebrow: _eyebrowFormat.format(now),
          title: 'Vault',
          actions: [
            _SortButton(
              sort: query.sort,
              onSelected: (s) =>
                  ref.read(vaultQueryProvider.notifier).setSort(s),
            ),
          ],
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _SearchHeader(
          background: c.background,
          child: _VaultSearchField(
            controller: _search,
            focusNode: _searchFocus,
            hint: all.isEmpty
                ? 'Search your vault'
                : 'Search ${all.length} item${all.length == 1 ? '' : 's'}',
            onChanged: _setSearch,
            onSubmitted: (_) => _openFirst(),
            onClear: _clearSearch,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: _NotifyTrigger()),
      const SliverToBoxAdapter(child: _UpdateBannerCard()),
      if (banner != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: AppBanner(
              title: banner,
              kind: BannerKind.warning,
              icon: Icons.cloud_off_outlined,
            ),
          ),
        ),
      const SliverToBoxAdapter(child: _FilterChips()),
    ];

    if (vault.hasError) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xl,
              AppSpacing.gutter,
              120,
            ),
            child: AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Your vault could not be opened',
              message: 'The vault file did not decrypt. Lock Vaultly and '
                  'unlock it again, or restore a backup.',
            ),
          ),
        ),
      );
    } else if (!vault.hasValue) {
      slivers.addAll(
        _section(
          'All items',
          query.sort.label,
          SliverRowGroup(
            separatorIndent: 74,
            itemCount: 8,
            itemBuilder: (_, __) => const _SkeletonTile(),
          ),
        ),
      );
    } else if (all.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xl,
              AppSpacing.gutter,
              120,
            ),
            child: AppEmptyState(
              icon: Icons.key_rounded,
              title: 'Your vault is empty',
              message: 'Add your first password to get started. '
                  'Everything you save stays encrypted on this phone.',
              action: VaultButton(
                label: 'Add a password',
                icon: Icons.add_rounded,
                isFullWidth: false,
                onPressed: () => context.push(AppRoutes.newEntry),
              ),
            ),
          ),
        ),
      );
    } else if (entries.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xl,
              AppSpacing.gutter,
              120,
            ),
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matches your search.',
              message: 'Try a site name, a username, or part of an '
                  'email address.',
            ),
          ),
        ),
      );
    } else if (browsing) {
      slivers
        ..add(
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              0,
            ),
            sliver: SliverToBoxAdapter(child: _Overview()),
          ),
        )
        ..addAll(
          _group(
            'Favorites',
            null,
            [
              for (final e in entries)
                if (e.favorite) e
            ],
          ),
        )
        ..addAll(
          _group(
            entries.any((e) => e.favorite) ? 'Everything else' : 'All items',
            query.sort.label,
            [
              for (final e in entries)
                if (!e.favorite) e
            ],
          ),
        );
    } else {
      slivers.addAll(
        _group(
          '${entries.length} result${entries.length == 1 ? '' : 's'}',
          query.search.trim().isEmpty ? null : 'Press Enter to open the first',
          entries,
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));
    if (!kReleaseMode && vault.hasValue) {
      StartupTimeline.markOnceAfterFrame('first vault frame');
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.slash):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: Scaffold(
        floatingActionButton: all.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => context.push(AppRoutes.newEntry),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New entry'),
              ),
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: slivers,
          ),
        ),
      ),
    );
  }
}

/// The pill search field: tall, filled, accent edge on focus.
class _VaultSearchField extends StatelessWidget {
  const _VaultSearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          height: 56,
          decoration: ShapeDecoration(
            color: c.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: focused ? c.accent : c.border,
                width: focused ? 1.5 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Icon(
                Icons.search_rounded,
                size: 24,
                color: focused ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: AppTextStyles.body.copyWith(
                    color: c.textPrimary,
                    fontSize: 17,
                  ),
                  cursorWidth: 2,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppTextStyles.body.copyWith(
                      color: c.textTertiary,
                      fontSize: 17,
                    ),
                    filled: false,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: Icon(
                    Icons.cancel_rounded,
                    size: 20,
                    color: c.textTertiary,
                  ),
                )
              else
                const SizedBox(width: 20),
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }
}

class _SearchHeader extends SliverPersistentHeaderDelegate {
  _SearchHeader({required this.child, required this.background});

  final Widget child;
  final Color background;

  static const double _height = 56 + AppSpacing.smd * 2;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.smd,
        ),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(_SearchHeader old) =>
      old.child != child || old.background != background;
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSelected});

  final VaultSort sort;
  final ValueChanged<VaultSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return PopupMenuButton<VaultSort>(
      tooltip: 'Sort',
      initialValue: sort,
      onSelected: onSelected,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(48),
        backgroundColor: c.surface,
        side: BorderSide(color: c.hairline),
      ),
      icon: Icon(Icons.swap_vert_rounded, color: c.textPrimary),
      itemBuilder: (context) => [
        for (final s in VaultSort.values)
          PopupMenuItem(value: s, child: Text(s.label)),
      ],
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tally = ref.watch(vaultTallyProvider);
    if (tally.total == 0) return const SizedBox.shrink();
    final query = ref.watch(vaultQueryProvider);
    final notifier = ref.read(vaultQueryProvider.notifier);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: 6,
        ),
        children: [
          AppChip(
            label: 'Favorites',
            icon: Icons.star_rounded,
            count: tally.favorites,
            selected: query.favoritesOnly,
            onTap: notifier.toggleFavoritesOnly,
          ),
          for (final category in EntryCategory.values) ...[
            const SizedBox(width: AppSpacing.sm),
            AppChip(
              label: category.label,
              icon: categoryIcon(category),
              count: tally.byCategory[category]!,
              selected: query.category == category,
              onTap: () => notifier.setCategory(
                query.category == category ? null : category,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The vault at a glance: the health score as the hero figure, then
/// password strength and two-factor coverage side by side.
class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    final tally = ref.watch(vaultTallyProvider);
    final analyzed = ref.watch(vaultHealthProvider).valueOrNull;
    // Until the first analysis lands, the figures it drives are laid out
    // with placeholder values and covered by skeletons, so the cards keep
    // their final size and nothing below them moves when it arrives.
    final loading = analyzed == null;
    final report = analyzed ??
        VaultHealthReport(
          score: 100,
          analyzedCount: tally.withPassword,
          strongCount: 0,
          weak: const [],
          reused: const [],
          old: const [],
        );
    Widget masked(Widget child) => loading ? _SkeletonOver(child) : child;

    final logins = tally.byCategory[EntryCategory.login]!;
    final twoFactor = tally.withTotp;
    final strong = report.strongCount;
    final withPassword = report.analyzedCount;
    final tone = healthTone(report.score, c);
    final caption = report.isHealthy
        ? 'All ${report.analyzedCount} passwords look good'
        : '${report.issueCount} to fix across '
            '${report.analyzedCount} passwords';
    final pill = StatusPill(label: healthLabel(report.score), color: tone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroMetricCard(
          label: 'Vault health',
          onTap: () => context.go(AppRoutes.health),
          trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          value: report.analyzedCount == 0
              ? Text(
                  'No passwords yet',
                  style: AppTextStyles.h2.copyWith(color: c.textPrimary),
                )
              : masked(HealthScoreFigure(score: report.score)),
          delta: report.analyzedCount == 0
              ? null
              : loading
                  // The pill and the caption line as one masked block: the
                  // caption is plain text the card would otherwise show.
                  ? _SkeletonOver(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          pill,
                          const SizedBox(width: AppSpacing.sm),
                          Text(caption, style: AppTextStyles.bodySmall),
                        ],
                      ),
                    )
                  : pill,
          deltaCaption: report.analyzedCount == 0 || loading ? null : caption,
          footer: [
            masked(
              StatTile(
                label: 'Weak',
                value: '${report.weak.length}',
                dotColor: c.negative,
              ),
            ),
            masked(
              StatTile(
                label: 'Reused',
                value: '${report.reused.length}',
                dotColor: c.warning,
              ),
            ),
            masked(
              StatTile(
                label: 'Old',
                value: '${report.old.length}',
                dotColor: c.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.smd),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Strong',
                  icon: Icons.verified_user_outlined,
                  value: masked(_Fraction(strong, withPassword)),
                  caption: 'passwords',
                  visual: masked(
                    AppProgressBar(
                      value: withPassword == 0 ? 0 : strong / withPassword,
                      color: c.positive,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.smd),
              Expanded(
                child: MetricCard(
                  label: 'Two-factor',
                  icon: Icons.pin_outlined,
                  value: _Fraction(twoFactor, logins),
                  caption: 'logins with codes',
                  visual: AppProgressBar(
                    value: logins == 0 ? 0 : (twoFactor / logins).clamp(0, 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lays [child] out invisibly and shows a skeleton of exactly its size.
class _SkeletonOver extends StatelessWidget {
  const _SkeletonOver(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Visibility.maintain(visible: false, child: child),
          const Positioned.fill(child: Skeleton(radius: AppSpacing.radiusXs)),
        ],
      );
}

/// A vault row while the vault loads: an [EntryTile]'s height and shape.
class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: EntryTile.minHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Skeleton(width: 44, height: 44, radius: 13),
              SizedBox(width: AppSpacing.smd + 2),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 140, height: 16),
                    SizedBox(height: 8),
                    Skeleton(width: 96, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Fraction extends StatelessWidget {
  const _Fraction(this.value, this.of);

  final int value;
  final int of;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value',
            style: AppTextStyles.numberLarge.copyWith(color: c.textPrimary),
          ),
          TextSpan(
            text: ' / $of',
            style: AppTextStyles.numberMedium.copyWith(
              color: c.textTertiary,
              fontSize: 20,
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
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
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

/// Fires the backup + vault-health notification checks once per app open.
/// Renders nothing.
class _NotifyTrigger extends ConsumerStatefulWidget {
  const _NotifyTrigger();

  @override
  ConsumerState<_NotifyTrigger> createState() => _NotifyTriggerState();
}

class _NotifyTriggerState extends ConsumerState<_NotifyTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(autoBackupControllerProvider).valueOrNull;
      // Ignored here so an analysis the digest never awaits (already sent
      // this month) cannot surface as an unhandled error.
      final health = ref.read(vaultHealthProvider.future)..ignore();
      ref.read(vaultNotifierProvider).checkOnOpen(
            config: config,
            health: health,
            now: DateTime.now(),
          );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
