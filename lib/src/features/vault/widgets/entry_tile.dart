import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// One vault item inside a `RowGroup`: avatar, title with its markers,
/// the username (or website), a one-tap password copy and an overflow menu.
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
    final c = SuiteColors.of(context);
    final subtitle = entry.username.isNotEmpty
        ? entry.username
        : entry.url.isNotEmpty
            ? entry.url
            : entry.category.label;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.smd,
            AppSpacing.xs,
            AppSpacing.smd,
          ),
          child: Row(
            children: [
              EntryAvatar(entry: entry),
              const SizedBox(width: AppSpacing.smd + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.h4.copyWith(
                              color: c.textPrimary,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        if (entry.favorite) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: c.accent,
                            semanticLabel: 'Favorite',
                          ),
                        ],
                        if (entry.totp != null) ...[
                          const SizedBox(width: 6),
                          const _Tag('2FA'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.password.isNotEmpty)
                IconButton(
                  tooltip: 'Copy password',
                  onPressed: onCopyPassword,
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_vert, color: c.textTertiary),
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
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ShapeDecoration(
        color: c.accentContainer,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: AppTextStyles.overline.copyWith(
          color: c.accent,
          letterSpacing: 0.4,
          height: 1.4,
        ),
      ),
    );
  }
}
