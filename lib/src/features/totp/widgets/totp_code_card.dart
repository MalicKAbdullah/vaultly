import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/totp/services/totp_generator.dart';

/// Live two-factor code for an entry: the current code in large grouped
/// digits, a smoothly draining countdown ring, and tap-to-copy with the
/// standard clipboard auto-clear.
class TotpCodeCard extends ConsumerStatefulWidget {
  const TotpCodeCard({required this.config, super.key});

  final TotpConfig config;

  @override
  ConsumerState<TotpCodeCard> createState() => _TotpCodeCardState();
}

class _TotpCodeCardState extends ConsumerState<TotpCodeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String? _code;
  bool _broken = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.config.period),
    )..addStatusListener((status) {
        // The period ended — roll to the next code and restart the ring.
        if (status == AnimationStatus.completed) _sync();
      });
    _sync();
  }

  @override
  void didUpdateWidget(TotpCodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _controller.duration = Duration(seconds: widget.config.period);
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Aligns the code and the ring with the wall clock, then lets the ring
  /// run ahead on its own until the period completes.
  void _sync() {
    final now = ref.read(clockProvider).now();
    String code;
    try {
      code = TotpGenerator.codeAt(widget.config, now);
    } on FormatException {
      setState(() => _broken = true);
      return;
    }
    setState(() {
      _broken = false;
      _code = code;
    });
    _controller
      ..stop()
      ..value = TotpGenerator.fractionElapsed(widget.config, now)
      ..forward();
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null) return;
    await ref.read(clipboardGuardProvider).copySensitive(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied. It clears in 30 seconds.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_broken) {
      return Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'The two-factor secret saved for this entry is not readable. '
            'Edit the entry and set it up again.',
            style: AppTextStyles.bodySmall.copyWith(color: scheme.error),
          ),
        ),
      );
    }

    final code = _code;
    if (code == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Two-factor code',
                      style: AppTextStyles.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        TotpGenerator.group(code),
                        key: ValueKey(code),
                        style: AppTextStyles.numberLarge
                            .copyWith(color: scheme.primary),
                      ),
                    ),
                    Text(
                      'Tap to copy',
                      style: AppTextStyles.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final remaining =
                      widget.config.period * (1 - _controller.value);
                  return SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            value: 1 - _controller.value,
                            strokeWidth: 4,
                            backgroundColor:
                                scheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        Text(
                          '${remaining.ceil()}',
                          style: AppTextStyles.numberSmall
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
