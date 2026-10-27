import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';

/// core_ui's `RowGroup` as a sliver: the same card (surface fill, large
/// radius, hairline edge, inset separators, ink clipped to the rounded
/// corners), but rows are built only as they scroll into view, so a
/// thousand-item vault costs a screenful of rows per frame.
class SliverRowGroup extends StatelessWidget {
  const SliverRowGroup({
    required this.itemCount,
    required this.itemBuilder,
    this.separatorIndent = 68,
    super.key,
  }) : assert(itemCount > 0, 'An empty group draws an empty card');

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Left inset of separators, aligning them with the row text.
  final double separatorIndent;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    const radius = Radius.circular(AppSpacing.radiusLg);
    final last = itemCount - 1;
    // Fill behind the rows, edge in front of them: RowGroup's Material paints
    // its border over its children the same way.
    return DecoratedSliver(
      decoration: ShapeDecoration(
        color: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(radius),
        ),
      ),
      sliver: DecoratedSliver(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(radius),
            side: BorderSide(color: c.hairline),
          ),
        ),
        sliver: SliverList.separated(
          itemCount: itemCount,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: separatorIndent,
            color: c.hairline,
          ),
          itemBuilder: (context, index) {
            // Each row carries its own ink surface; only the end rows touch
            // the rounded corners, so only they need a rounded clip.
            final row = Material(
              type: MaterialType.transparency,
              child: itemBuilder(context, index),
            );
            if (index != 0 && index != last) return row;
            return ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: index == 0 ? radius : Radius.zero,
                bottom: index == last ? radius : Radius.zero,
              ),
              child: row,
            );
          },
        ),
      ),
    );
  }
}
