import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';

/// A colored strength bar + label for a password.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({required this.password, super.key});

  final String password;

  static Color colorFor(StrengthLevel level, Brightness brightness) =>
      switch (level) {
        StrengthLevel.weak => AppColors.error(brightness),
        StrengthLevel.fair => AppColors.warning(brightness),
        StrengthLevel.good => AppColors.info(brightness),
        StrengthLevel.strong => AppColors.success(brightness),
      };

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final strength = StrengthEstimator.estimate(password);
    final color = colorFor(strength.level, brightness);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: password.isEmpty ? 0 : strength.ratio),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                color: color,
                backgroundColor: AppColors.surfaceAlt(brightness),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 4),
        SizedBox(
          width: 52,
          child: Text(
            password.isEmpty ? '' : strength.level.label,
            style: AppTextStyles.caption.copyWith(color: color),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
