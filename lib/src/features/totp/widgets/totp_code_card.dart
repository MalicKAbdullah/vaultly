import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
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
    final guard = ref.read(clipboardGuardProvider);
    await guard.copySensitive(code);
    if (!mounted) return;
    showCopiedSnack(context, what: 'Code', clearsAfter: guard.clearAfter);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);

    if (_broken) {
      return const AppBanner(
        title: 'Two-factor code unavailable',
        message: 'The two-factor secret saved for this entry is not readable. '
            'Edit the entry and set it up again.',
        kind: BannerKind.error,
      );
    }

    final code = _code;
    if (code == null) return const SizedBox.shrink();

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _copy,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.mdl,
            AppSpacing.md,
            AppSpacing.mdl,
            AppSpacing.md,
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
                          .copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: AppMotion.base,
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
                        style: AppTextStyles.numberLarge.copyWith(
                          color: c.textPrimary,
                          fontSize: 36,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to copy',
                      style:
                          AppTextStyles.caption.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
              // The ring repaints every animation frame; a RepaintBoundary
              // keeps that raster off the code text and the rest of the card.
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final remaining =
                        widget.config.period * (1 - _controller.value);
                    final urgent = remaining <= 5;
                    final ink = urgent ? c.negative : c.accent;
                    return Semantics(
                      label: '${remaining.ceil()} seconds left',
                      excludeSemantics: true,
                      child: SizedBox.square(
                        dimension: 56,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.square(
                              dimension: 56,
                              child: CircularProgressIndicator(
                                value: 1 - _controller.value,
                                strokeWidth: 4,
                                strokeCap: StrokeCap.round,
                                color: ink,
                                backgroundColor: c.surfaceAlt,
                              ),
                            ),
                            Text(
                              '${remaining.ceil()}',
                              style: AppTextStyles.number.copyWith(
                                  color: urgent ? ink : c.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
