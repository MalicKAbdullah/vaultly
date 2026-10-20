import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';

/// Four-step strength meter with its verdict and, optionally, the estimated
/// entropy in bits.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({
    required this.password,
    this.showEntropy = true,
    super.key,
  });

  final String password;
  final bool showEntropy;

  static Color colorFor(StrengthLevel level, SuiteColors c) => switch (level) {
        StrengthLevel.weak => c.negative,
        StrengthLevel.fair => c.warning,
        StrengthLevel.good => c.info,
        StrengthLevel.strong => c.positive,
      };

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final strength = StrengthEstimator.estimate(password);
    final empty = password.isEmpty;
    final color = colorFor(strength.level, c);
    final filled = empty ? 0 : strength.level.index + 1;

    return Semantics(
      label: empty
          ? 'Password strength'
          : 'Password strength: ${strength.level.label}, '
              '${strength.bits.round()} bits',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < StrengthLevel.values.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AnimatedContainer(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    height: 6,
                    decoration: ShapeDecoration(
                      color: i < filled ? color : c.surfaceAlt,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                empty ? 'Strength' : strength.level.label,
                style: AppTextStyles.labelStrong.copyWith(
                  color: empty ? c.textTertiary : color,
                ),
              ),
              const Spacer(),
              if (showEntropy && !empty)
                Text(
                  '${strength.bits.round()} bits of entropy',
                  style: AppTextStyles.numberSmall.copyWith(
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
