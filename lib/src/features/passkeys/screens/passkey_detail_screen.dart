import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/widgets/detail_field_card.dart';

/// One passkey: the site and account it signs in to, when it was made and
/// last used, and delete. The private key has no reveal or copy anywhere.
class PasskeyDetailScreen extends ConsumerWidget {
  const PasskeyDetailScreen({required this.entry, super.key});

  /// A passkey entry ([VaultEntry.passkey] is set).
  final VaultEntry entry;

  Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    String value,
    String what,
  ) async {
    await ref.read(clipboardGuardProvider).copy(value);
    if (context.mounted) showCopiedSnack(context, what: what);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final rpId = entry.passkey!.rpId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this passkey?'),
        content: Text(
          'You will no longer be able to sign in to $rpId with it. '
          '$rpId still lists it until you remove it in that account’s '
          'security settings. This cannot be undone.',
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
    if (!(confirmed ?? false)) return;
    await ref.read(vaultEntriesProvider.notifier).delete(entry.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    final passkey = entry.passkey!;
    final now = ref.watch(clockProvider).now();
    final date = DateFormat('d MMM yyyy');

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
                          categoryIcon(EntryCategory.passkey),
                          size: 15,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Passkey',
                          style: AppTextStyles.label.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          RowGroup(
            separatorIndent: AppSpacing.mdl,
            children: [
              DetailFieldCard(
                label: 'Account',
                value: passkey.userName,
                onCopy: () => _copy(context, ref, passkey.userName, 'Account'),
              ),
              if (passkey.userDisplayName.isNotEmpty &&
                  passkey.userDisplayName != passkey.userName)
                DetailFieldCard(
                  label: 'Name',
                  value: passkey.userDisplayName,
                  onCopy: () =>
                      _copy(context, ref, passkey.userDisplayName, 'Name'),
                ),
              DetailFieldCard(
                label: 'Website',
                value: passkey.rpId,
                onCopy: () => _copy(context, ref, passkey.rpId, 'Website'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smd),
          AppBanner(
            title: 'Signs you in to ${passkey.rpId}',
            message: 'Choose Vaultly when the site or app asks for a passkey. '
                'The private key stays encrypted in your vault: it is never '
                'shown, copied or exported as plain text.',
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Details'),
          RowGroup(
            separatorIndent: AppSpacing.md,
            children: [
              AppListRow(
                dense: true,
                title: 'Last used',
                trailing: _MetaValue(
                  passkey.lastUsedAt == null
                      ? 'Never'
                      : relativeAge(passkey.lastUsedAt!, now),
                ),
              ),
              AppListRow(
                dense: true,
                title: 'Created',
                trailing: _MetaValue(date.format(entry.createdAt)),
              ),
              const AppListRow(
                dense: true,
                title: 'Key type',
                trailing: _MetaValue('ES256 (P-256)'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          VaultButton(
            label: 'Delete passkey',
            icon: Icons.delete_outline_rounded,
            variant: VaultButtonVariant.destructive,
            onPressed: () => _delete(context, ref),
          ),
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
