import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';

/// A labeled value card with a one-tap copy button, used on the entry
/// detail screen.
class DetailFieldCard extends StatelessWidget {
  const DetailFieldCard({
    required this.label,
    required this.value,
    required this.onCopy,
    this.valueStyle,
    this.extraAction,
    this.multiline = false,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final TextStyle? valueStyle;
  final Widget? extraAction;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
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
                    style: AppTextStyles.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      value,
                      key: ValueKey(value),
                      style: valueStyle ?? AppTextStyles.body,
                      maxLines: multiline ? null : 1,
                      overflow: multiline ? null : TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (extraAction != null) extraAction!,
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_outlined, size: 20),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}
