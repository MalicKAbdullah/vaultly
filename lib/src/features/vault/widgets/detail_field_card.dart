import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';

/// One labelled value on the entry detail screen, sized for a `RowGroup`:
/// caption label, the value (mono for secrets), optional content under it,
/// and trailing icon actions (reveal, open, copy).
class DetailFieldCard extends StatelessWidget {
  const DetailFieldCard({
    required this.label,
    required this.value,
    required this.onCopy,
    this.monospace = false,
    this.extraAction,
    this.multiline = false,
    this.below,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool monospace;
  final Widget? extraAction;
  final bool multiline;

  /// Extra content under the value (the password strength meter).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final valueStyle = monospace
        ? AppTextStyles.code.copyWith(color: c.textPrimary, fontSize: 17)
        : AppTextStyles.body.copyWith(color: c.textPrimary, fontSize: 17);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.mdl,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Text(
                    value,
                    key: ValueKey(value),
                    style: valueStyle,
                    maxLines: multiline ? null : 1,
                    overflow: multiline ? null : TextOverflow.ellipsis,
                  ),
                ),
                if (below != null) ...[
                  const SizedBox(height: AppSpacing.smd),
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.smd),
                    child: below!,
                  ),
                ],
              ],
            ),
          ),
          if (extraAction != null) extraAction!,
          IconButton(
            tooltip: 'Copy ${label.toLowerCase()}',
            icon: Icon(Icons.copy_rounded, size: 20, color: c.textSecondary),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
