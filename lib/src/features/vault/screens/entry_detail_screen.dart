import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';
import 'package:vaultkey/src/features/totp/widgets/totp_code_card.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/detail_field_card.dart';

/// One entry: who it is, the fields with reveal and copy, its two-factor
/// code, notes, dates and password history.
class EntryDetailScreen extends ConsumerStatefulWidget {
  const EntryDetailScreen({required this.entryId, super.key});

  final String entryId;

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  bool _revealed = false;

  Future<void> _copySensitive(String value, String what) async {
    final guard = ref.read(clipboardGuardProvider);
    await guard.copySensitive(value);
    if (!mounted) return;
    showCopiedSnack(context, what: what, clearsAfter: guard.clearAfter);
  }

  Future<void> _copyPlain(String value, String what) async {
    await ref.read(clipboardGuardProvider).copy(value);
    if (!mounted) return;
    showCopiedSnack(context, what: what);
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
    final c = SuiteColors.of(context);
    final now = ref.watch(clockProvider).now();
    final date = DateFormat('d MMM yyyy');

    final fields = <Widget>[
      if (entry.username.isNotEmpty)
        DetailFieldCard(
          label: 'Username',
          value: entry.username,
          onCopy: () => _copySensitive(entry.username, 'Username'),
        ),
      if (entry.password.isNotEmpty)
        DetailFieldCard(
          label: 'Password',
          value: _revealed ? entry.password : '•' * 14,
          monospace: _revealed,
          onCopy: () => _copySensitive(entry.password, 'Password'),
          below: StrengthMeter(password: entry.password),
          extraAction: IconButton(
            tooltip: _revealed ? 'Hide password' : 'Reveal password',
            icon: Icon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 22,
              color: c.textSecondary,
            ),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
        ),
      if (entry.url.isNotEmpty)
        DetailFieldCard(
          label: 'Website',
          value: entry.url,
          onCopy: () => _copyPlain(entry.url, 'Website'),
          extraAction: IconButton(
            tooltip: 'Open website',
            icon: Icon(
              Icons.open_in_new_rounded,
              size: 20,
              color: c.textSecondary,
            ),
            onPressed: () => _openUrl(entry.url),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip:
                entry.favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              entry.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: entry.favorite ? c.accent : null,
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
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xs,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          Row(
            children: [
              EntryAvatar(entry: entry, size: 64),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        entry.title,
                        style: AppTextStyles.h1.copyWith(
                          color: c.textPrimary,
                          fontSize: 28,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          categoryIcon(entry.category),
                          size: 15,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${entry.category.label} · Updated '
                            '${relativeAge(entry.updatedAt, now).toLowerCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.label.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.password.isNotEmpty || entry.url.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (entry.password.isNotEmpty)
                  Expanded(
                    child: VaultButton(
                      label: 'Copy password',
                      icon: Icons.copy_rounded,
                      onPressed: () =>
                          _copySensitive(entry.password, 'Password'),
                    ),
                  ),
                if (entry.password.isNotEmpty && entry.url.isNotEmpty)
                  const SizedBox(width: AppSpacing.smd),
                if (entry.url.isNotEmpty)
                  Expanded(
                    child: VaultButton(
                      label: 'Open site',
                      icon: Icons.open_in_new_rounded,
                      variant: VaultButtonVariant.secondary,
                      onPressed: () => _openUrl(entry.url),
                    ),
                  ),
              ],
            ),
          ],
          if (fields.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            RowGroup(separatorIndent: AppSpacing.mdl, children: fields),
          ],
          if (entry.totp != null) ...[
            const SizedBox(height: AppSpacing.smd),
            TotpCodeCard(config: entry.totp!),
          ],
          if (entry.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.smd),
            RowGroup(
              children: [
                DetailFieldCard(
                  label: 'Notes',
                  value: entry.notes,
                  multiline: true,
                  onCopy: () => _copyPlain(entry.notes, 'Notes'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Details'),
          RowGroup(
            separatorIndent: AppSpacing.md,
            children: [
              AppListRow(
                dense: true,
                title: 'Password changed',
                trailing: _MetaValue(relativeAge(entry.passwordChangedAt, now)),
              ),
              AppListRow(
                dense: true,
                title: 'Last updated',
                trailing: _MetaValue(date.format(entry.updatedAt)),
              ),
              AppListRow(
                dense: true,
                title: 'Created',
                trailing: _MetaValue(date.format(entry.createdAt)),
              ),
            ],
          ),
          if (entry.history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Password history',
              subtitle: 'Previous passwords are kept in case you need one '
                  'back.',
            ),
            RowGroup(
              separatorIndent: AppSpacing.mdl,
              children: [
                for (final item in entry.history)
                  _HistoryTile(
                    item: item,
                    onCopy: () => _copySensitive(item.password, 'Old password'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaValue extends StatelessWidget {
  const _MetaValue(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTextStyles.label.copyWith(
          color: SuiteColors.of(context).textSecondary,
        ),
      );
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
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.mdl,
        AppSpacing.smd,
        AppSpacing.xs,
        AppSpacing.smd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _revealed ? widget.item.password : '•' * 12,
                  style: AppTextStyles.code.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Used until '
                  '${DateFormat('d MMM yyyy').format(widget.item.replacedAt)}',
                  style: AppTextStyles.caption.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _revealed ? 'Hide' : 'Reveal',
            icon: Icon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: c.textSecondary,
            ),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
          IconButton(
            tooltip: 'Copy old password',
            icon: Icon(Icons.copy_rounded, size: 20, color: c.textSecondary),
            onPressed: widget.onCopy,
          ),
        ],
      ),
    );
  }
}
