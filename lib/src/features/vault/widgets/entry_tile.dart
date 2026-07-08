import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Icon for each entry category.
IconData categoryIcon(EntryCategory category) => switch (category) {
      EntryCategory.login => Icons.language,
      EntryCategory.card => Icons.credit_card,
      EntryCategory.identity => Icons.badge_outlined,
      EntryCategory.note => Icons.sticky_note_2_outlined,
    };

/// One row in the vault list.
class EntryTile extends StatelessWidget {
  const EntryTile({
    required this.entry,
    required this.onTap,
    required this.onCopyPassword,
    required this.onCopyUsername,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final VaultEntry entry;
  final VoidCallback onTap;
  final VoidCallback onCopyPassword;
  final VoidCallback onCopyUsername;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return VaultCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
            ),
            child: Icon(
              categoryIcon(entry.category),
              size: 22,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.title,
                        style: AppTextStyles.h4,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (entry.favorite) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(Icons.star_rounded,
                          size: 16,
                          color:
                              AppColors.warning(Theme.of(context).brightness)),
                    ],
                    if (entry.totp != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '2FA',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (entry.username.isNotEmpty)
                  Text(
                    entry.username,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
            onSelected: (action) => switch (action) {
              'copy-password' => onCopyPassword(),
              'copy-username' => onCopyUsername(),
              'edit' => onEdit(),
              'delete' => onDelete(),
              _ => null,
            },
            itemBuilder: (context) => [
              if (entry.password.isNotEmpty)
                const PopupMenuItem(
                  value: 'copy-password',
                  child: Text('Copy password'),
                ),
              if (entry.username.isNotEmpty)
                const PopupMenuItem(
                  value: 'copy-username',
                  child: Text('Copy username'),
                ),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
