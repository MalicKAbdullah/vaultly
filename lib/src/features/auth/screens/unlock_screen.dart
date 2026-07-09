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

  Future<void> _init() async {
    await _checkExistingCooldown();
    await _initBiometrics();
  }

  /// Loads the persisted "biometric enabled" flag (fast, no capability
  /// probe), shows the button, then probes hardware and auto-triggers the
  /// prompt once. Runs every time this locked screen is created — cold
  /// start, inactivity lock, or returning to a locked vault.
  Future<void> _initBiometrics() async {
    final service = ref.read(biometricServiceProvider);
    final enabled = await service.isEnabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
    if (!enabled) return;

    final supported = await service.isSupported();
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

  Future<void> _checkExistingCooldown() async {
    final remaining =
        await ref.read(masterAuthServiceProvider).cooldownRemaining();
    if (remaining > Duration.zero) _startCooldown(remaining);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Persisted flag is the source of truth: once enabled the button is
    // always shown, never hidden behind the async hardware probe.
    final showBiometric = _biometricEnabled;
    final biometricUnavailable = _supportProbed && !_biometricSupported;
    final coolingDown = _cooldown > Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.borderRadiusLg),
                    ),
                    child: Icon(Icons.lock_outline,
                        size: 36, color: scheme.primary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Vaultly',
                      style: AppTextStyles.h1, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enter your master password to unlock.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  VaultTextField(
                    label: 'Master password',
                    controller: _passwordController,
                    obscureText: _obscure,
                    autofocus: true,
                    errorText: _error,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _unlock(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  if (coolingDown) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.warningContainerDark
                            : AppColors.warningContainerLight,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.borderRadius),
                      ),
                      child: Text(
                        _cooldownLabel,
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.warning(
                            Theme.of(context).brightness,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  VaultButton(
                    label: 'Unlock',
                    isLoading: _busy,
                    onPressed: coolingDown ? null : _unlock,
                  ),
                  if (showBiometric) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: (coolingDown ||
                              biometricUnavailable ||
                              _biometricBusy)
                          ? null
                          : () => _biometricUnlock(),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock with biometrics'),
                    ),
                    if (biometricUnavailable) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Biometric hardware is not available right now. '
                        'Enter your master password instead.',
                        style: AppTextStyles.caption
                            .copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
