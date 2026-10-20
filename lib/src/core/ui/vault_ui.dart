import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

/// Confirms a copy. When [clearsAfter] is set the value was copied as a
/// secret and the clipboard guard wipes it after that delay, so the message
/// says so.
void showCopiedSnack(
  BuildContext context, {
  required String what,
  Duration? clearsAfter,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: _CopiedMessage(what: what, clearsAfter: clearsAfter),
      ),
    );
}

class _CopiedMessage extends StatelessWidget {
  const _CopiedMessage({required this.what, required this.clearsAfter});

  final String what;
  final Duration? clearsAfter;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).snackBarTheme.contentTextStyle ??
        AppTextStyles.bodyMedium;
    final clears = clearsAfter;
    return Row(
      children: [
        Icon(Icons.check_circle_rounded, size: 20, color: style.color),
        const SizedBox(width: AppSpacing.smd),
        Expanded(
          child: Text(
            clears == null
                ? '$what copied.'
                : '$what copied. It clears in ${clears.inSeconds} seconds.',
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Leading badge for a vault item: the first letter of its title on a
/// neutral tile, so a long list scans by name rather than by colour.
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({required this.entry, this.size = 44, super.key});

  final VaultEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final title = entry.title.trim();
    final letter = title.isEmpty ? '' : title.characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: c.hairline),
        ),
        child: letter.isEmpty
            ? Icon(
                categoryIcon(entry.category),
                size: size * 0.48,
                color: c.textSecondary,
              )
            : Text(
                letter,
                style: AppTextStyles.h3.copyWith(
                  fontFamily: AppTextStyles.displayFamily,
                  fontSize: size * 0.42,
                  height: 1,
                  color: c.textPrimary,
                ),
              ),
      ),
    );
  }
}

/// Icon for each entry category.
IconData categoryIcon(EntryCategory category) => switch (category) {
      EntryCategory.login => Icons.language_rounded,
      EntryCategory.card => Icons.credit_card_rounded,
      EntryCategory.identity => Icons.badge_outlined,
      EntryCategory.note => Icons.sticky_note_2_outlined,
    };

/// Large-title header of a tab: an eyebrow line over an h1, with optional
/// trailing actions.
class TabHeader extends StatelessWidget {
  const TabHeader({
    required this.title,
    this.eyebrow,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.smd,
        AppSpacing.mdl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Text(
                    eyebrow!,
                    style: AppTextStyles.label.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppTextStyles.h1.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A round, hairline-edged icon button used in tab headers.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(48),
          backgroundColor: c.surface,
          side: BorderSide(color: c.hairline),
        ),
        icon: Icon(icon, size: 22, color: c.textPrimary),
      ),
    );
  }
}

/// "Today", "Yesterday", "3 days ago", "5 months ago", "2 years ago".
String relativeAge(DateTime then, DateTime now) {
  final days = now.difference(then).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 30) return '$days days ago';
  final months = days ~/ 30;
  if (months < 12) return months == 1 ? '1 month ago' : '$months months ago';
  final years = days ~/ 365;
  return years == 1 ? '1 year ago' : '$years years ago';
}
