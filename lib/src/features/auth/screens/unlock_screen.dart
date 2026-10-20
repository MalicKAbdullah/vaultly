import 'dart:async';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';

/// Locked state: master password entry with optional biometric unlock and
/// an escalating-cooldown countdown after repeated failures.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Duration _cooldown = Duration.zero;
  Timer? _countdown;

  /// Persisted flag — the single source of truth for whether to show the
  /// biometric button. Resolved from storage (no hardware probe) so the
  /// button appears immediately when biometric unlock is switched on.
  bool _biometricEnabled = false;

  /// Whether the device can actually run a biometric prompt right now.
  /// Only meaningful once [_supportProbed] is true.
  bool _biometricSupported = true;
  bool _supportProbed = false;

  /// Latch so the prompt auto-fires exactly once per entry into this screen.
  bool _autoPromptFired = false;

  /// Guards against overlapping prompts (auto-trigger vs. a button tap).
  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  /// Reads the cooldown and the persisted "biometric enabled" flag while
  /// probing the hardware — all at once, since the prompt waits on every one
  /// of them — then auto-triggers the prompt once. Runs every time this
  /// locked screen is created: cold start, inactivity lock, or returning to
  /// a locked vault.
  Future<void> _init() async {
    final service = ref.read(biometricServiceProvider);
    final cooldown = ref.read(masterAuthServiceProvider).cooldownRemaining();
    final enabled = service.isEnabled();
    final support = service.isSupported();

    final remaining = await cooldown;
    if (!mounted) return;
    if (remaining > Duration.zero) _startCooldown(remaining);

    final isEnabled = await enabled;
    if (!mounted) return;
    setState(() => _biometricEnabled = isEnabled);
    if (!isEnabled) return;

    final supported = await support;
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _supportProbed = true;
    });

    // Auto-trigger deterministically, but only when the hardware is usable
    // and we are not in a lockout cooldown.
    if (supported && !_autoPromptFired && _cooldown == Duration.zero) {
      _autoPromptFired = true;
      await _biometricUnlock(auto: true);
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  void _startCooldown(Duration duration) {
    _countdown?.cancel();
    setState(() => _cooldown = duration);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final next = _cooldown - const Duration(seconds: 1);
      setState(() => _cooldown = next.isNegative ? Duration.zero : next);
      if (_cooldown == Duration.zero) timer.cancel();
    });
  }

  Future<void> _unlock() async {
    final password = _passwordController.text;
    if (password.isEmpty || _busy || _cooldown > Duration.zero) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).unlock(password);
    if (!mounted) return;
    switch (result) {
      case UnlockSuccess():
        _passwordController.clear();
      case UnlockWrongPassword(:final cooldown):
        setState(() => _error = 'That password is not right.');
        if (cooldown != null) _startCooldown(cooldown);
      case UnlockCoolingDown(:final remaining):
        _startCooldown(remaining);
    }
    setState(() => _busy = false);
  }

  /// Runs the biometric prompt. [auto] marks the once-per-lock automatic
  /// trigger, which stays quiet on cancel/failure; a manual tap surfaces a
  /// hint pointing at the master-password fallback.
  Future<void> _biometricUnlock({bool auto = false}) async {
    if (_biometricBusy || _cooldown > Duration.zero) return;
    setState(() => _biometricBusy = true);
    final ok = await ref.read(sessionProvider.notifier).unlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricBusy = false;
      if (!ok && !auto) {
        _error = 'Biometric unlock didn\'t work. Use your master password.';
      }
    });
  }

  String get _cooldownLabel {
    final m = _cooldown.inMinutes;
    final s = _cooldown.inSeconds % 60;
    final time =
        m > 0 ? '$m min ${s.toString().padLeft(2, '0')} sec' : '$s sec';
    return 'Too many attempts. Try again in $time.';
  }

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _greeting(int hour) => switch (hour) {
        < 5 => 'Good night',
        < 12 => 'Good morning',
        < 17 => 'Good afternoon',
        < 22 => 'Good evening',
        _ => 'Good night',
      };

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    // Persisted flag is the source of truth: once enabled the button is
    // always shown, never hidden behind the async hardware probe.
    final showBiometric = _biometricEnabled;
    final biometricUnavailable = _supportProbed && !_biometricSupported;
    final coolingDown = _cooldown > Duration.zero;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // The family mark, oversized and near-invisible, gives the screen
          // texture without showing anything from inside the vault.
          Positioned(
            right: -150,
            top: 72,
            child: ExcludeSemantics(
              child: SuiteMark(
                size: 460,
                color: c.accent.withValues(alpha: 0.04),
                accentColor: c.accent.withValues(alpha: 0.08),
                variant: SuiteMarkVariant.accent,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              children: [
                                const SuiteAppIcon(
                                  app: SuiteApp.vaultly,
                                  size: 40,
                                ),
                                const SizedBox(width: AppSpacing.smd),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Vaultly',
                                        style: AppTextStyles.h4.copyWith(
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Enter your master password to unlock.',
                                        style:
                                            AppTextStyles.bodySmall.copyWith(
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: c.textTertiary,
                                ),
                              ],
                            ),
                            const Spacer(flex: 2),
                            const _LockClock(),
                            if (showBiometric) ...[
                              const SizedBox(height: AppSpacing.xxl),
                              _BiometricTarget(
                                busy: _biometricBusy,
                                onPressed: (coolingDown ||
                                        biometricUnavailable ||
                                        _biometricBusy)
                                    ? null
                                    : () => _biometricUnlock(),
                              ),
                              if (biometricUnavailable) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Biometric hardware is not available right '
                                  'now. Enter your master password instead.',
                                  style: AppTextStyles.caption.copyWith(
                                    color: c.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                            const Spacer(flex: 2),
                            if (coolingDown) ...[
                              AppBanner(
                                title: _cooldownLabel,
                                kind: BannerKind.warning,
                                icon: Icons.timer_outlined,
                              ),
                              const SizedBox(height: AppSpacing.smd),
                            ],
                            AppTextField(
                              label: 'Master password',
                              controller: _passwordController,
                              obscureText: _obscure,
                              autofocus: !showBiometric,
                              errorText: _error,
                              textInputAction: TextInputAction.go,
                              autofillHints: const [AutofillHints.password],
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              onSubmitted: (_) => _unlock(),
                              suffixIcon: IconButton(
                                tooltip: _obscure ? 'Show' : 'Hide',
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.smd),
                            VaultButton(
                              label: 'Unlock',
                              isLoading: _busy,
                              onPressed: coolingDown ? null : _unlock,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            const Center(child: SuiteEndorsement()),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The large clock, greeting and date, re-rendered on each minute boundary.
class _LockClock extends ConsumerStatefulWidget {
  const _LockClock();

  @override
  ConsumerState<_LockClock> createState() => _LockClockState();
}

class _LockClockState extends ConsumerState<_LockClock> {
  Timer? _tick;
  late DateTime _now = ref.read(clockProvider).now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final next = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour,
      _now.minute,
    ).add(const Duration(minutes: 1));
    _tick = Timer(next.difference(_now), () {
      if (!mounted) return;
      setState(() => _now = ref.read(clockProvider).now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    final hour =
        use24h ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    final time = '${use24h ? hour.toString().padLeft(2, '0') : hour}:'
        '${_now.minute.toString().padLeft(2, '0')}';
    final date = '${_UnlockScreenState._days[_now.weekday - 1]}, '
        '${_now.day} ${_UnlockScreenState._months[_now.month - 1]}';
    return Column(
      children: [
        Text(
          time,
          style: AppTextStyles.heroXL.copyWith(
            fontSize: 88,
            letterSpacing: -4,
            fontWeight: FontWeight.w400,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${_UnlockScreenState._greeting(_now.hour)} · $date',
          style: AppTextStyles.label.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// The biometric unlock: a large fingerprint target on a soft accent disc
/// in a hairline ring, with its label underneath.
class _BiometricTarget extends StatelessWidget {
  const _BiometricTarget({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Unlock with biometrics',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Column(
          children: [
            Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: busy ? c.accent : c.border),
              ),
              child: AnimatedOpacity(
                duration: AppMotion.fast,
                opacity: enabled || busy ? 1 : 0.45,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: c.accentContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.fingerprint_rounded,
                    size: 44,
                    color: c.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.smd),
            Text(
              'Unlock with biometrics',
              style: AppTextStyles.labelStrong.copyWith(
                color: enabled ? c.textPrimary : c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
