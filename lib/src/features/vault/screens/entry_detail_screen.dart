import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/features/totp/widgets/totp_code_card.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/detail_field_card.dart';
import 'package:vaultkey/src/features/vault/widgets/entry_tile.dart';

/// Read-only view of one entry: reveal/copy fields, open the website, and
/// browse password history.
class EntryDetailScreen extends ConsumerStatefulWidget {
  const EntryDetailScreen({required this.entryId, super.key});

  final String entryId;

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  bool _revealed = false;

  Future<void> _copySensitive(String value, String what) async {
    await ref.read(clipboardGuardProvider).copySensitive(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what copied. It clears in 30 seconds.')),
    );
  }

  Future<void> _copyPlain(String value, String what) async {
    await ref.read(clipboardGuardProvider).copy(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$what copied.')));
  }

  Future<void> _openUrl(String raw) async {
    var url = raw.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that website.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(entryByIdProvider(widget.entryId));
    if (entry == null) {
      // Deleted while open — leave gracefully.
      return const Scaffold(body: SizedBox.shrink());
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title),
        actions: [
          IconButton(
            tooltip:
                entry.favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              entry.favorite ? Icons.star_rounded : Icons.star_outline,
              color: entry.favorite
                  ? AppColors.warning(Theme.of(context).brightness)
                  : null,
            ),
            onPressed: () => ref
                .read(vaultEntriesProvider.notifier)
                .toggleFavorite(entry.id),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(AppRoutes.editEntry(entry.id)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                ),
                child: Icon(categoryIcon(entry.category),
                    size: 22, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(entry.category.label,
                  style: AppTextStyles.label
                      .copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text(
                'Updated ${DateFormat.yMMMd().format(entry.updatedAt)}',
                style: AppTextStyles.caption
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (entry.username.isNotEmpty)
            DetailFieldCard(
              label: 'Username / email',
              value: entry.username,
              onCopy: () => _copySensitive(entry.username, 'Username'),
            ),
          if (entry.password.isNotEmpty)
            DetailFieldCard(
              label: 'Password',
              value: _revealed ? entry.password : '••••••••••••',
              valueStyle: _revealed ? AppTextStyles.code : null,
              onCopy: () => _copySensitive(entry.password, 'Password'),
              extraAction: IconButton(
                tooltip: _revealed ? 'Hide' : 'Reveal',
                icon: Icon(
                  _revealed ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _revealed = !_revealed),
              ),
            ),
          if (entry.totp != null) TotpCodeCard(config: entry.totp!),
          if (entry.url.isNotEmpty)
            DetailFieldCard(
              label: 'Website',
              value: entry.url,
              onCopy: () => _copyPlain(entry.url, 'Website'),
              extraAction: IconButton(
                tooltip: 'Open website',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openUrl(entry.url),
              ),
            ),
          if (entry.notes.isNotEmpty)
            DetailFieldCard(
              label: 'Notes',
              value: entry.notes,
              multiline: true,
              onCopy: () => _copyPlain(entry.notes, 'Notes'),
            ),
          if (entry.history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('Password history', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Previous passwords are kept in case you need one back.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final item in entry.history)
              _HistoryTile(
                item: item,
                onCopy: () => _copySensitive(item.password, 'Old password'),
              ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({required this.item, required this.onCopy});

  final PasswordHistoryEntry item;
  final VoidCallback onCopy;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _revealed ? widget.item.password : '••••••••••••',
                    style: AppTextStyles.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Used until '
                    '${DateFormat.yMMMd().format(widget.item.replacedAt)}',
                    style: AppTextStyles.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 20),
              onPressed: widget.onCopy,
            ),
          ],
        ),
      ),
    );
  }
}
