import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_lock/core_lock.dart';
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
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _recovering = false;
  String? _error;
  int _failures = 0;
  Duration _cooldown = Duration.zero;
  Timer? _countdown;

  /// Persisted flag, resolved from storage (no hardware probe) so the
  /// fingerprint button appears as soon as the screen does.
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
    if (!isEnabled) {
      _passwordFocus.requestFocus();
      return;
    }

    final supported = await support;
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _supportProbed = true;
    });
    if (!supported) {
      _passwordFocus.requestFocus();
      return;
    }

    // Auto-trigger deterministically, but not during a lockout cooldown.
    if (!_autoPromptFired && _cooldown == Duration.zero) {
      _autoPromptFired = true;
      await _biometricUnlock();
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _passwordController.dispose();
    _passwordFocus.dispose();
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
        setState(() {
          _error = 'That password is not right.';
          _failures++;
        });
        if (cooldown != null) _startCooldown(cooldown);
      case UnlockCoolingDown(:final remaining):
        _startCooldown(remaining);
    }
    setState(() => _busy = false);
  }

  /// Runs the biometric prompt. A cancelled or failed prompt leaves the
  /// screen as it is: the system prompt gives its own feedback, and the
  /// master password stays ready underneath.
  Future<void> _biometricUnlock() async {
    if (_biometricBusy || _cooldown > Duration.zero) return;
    setState(() => _biometricBusy = true);
    await ref.read(sessionProvider.notifier).unlockWithBiometrics();
    if (!mounted) return;
    setState(() => _biometricBusy = false);
  }

  String get _cooldownLabel =>
      'Too many attempts. Try again in ${formatLockCountdown(_cooldown)}.';

  @override
  Widget build(BuildContext context) {
    // Shown from the persisted flag at once; hidden only when the hardware
    // probe reports the prompt cannot run on this device right now.
    final showBiometric =
        _biometricEnabled && !(_supportProbed && !_biometricSupported);
    final coolingDown = _cooldown > Duration.zero;

    final List<Widget> controls;
    if (_recovering) {
      controls = [
        _RecoveryForm(
          coolingDown: coolingDown,
          cooldownLabel: _cooldownLabel,
          onCooldown: _startCooldown,
          onBack: () => setState(() => _recovering = false),
        ),
      ];
    } else {
      controls = [
        LockShake(
          trigger: _failures,
          child: AppTextField(
            label: 'Master password',
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: true,
            errorText: coolingDown ? _cooldownLabel : _error,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _unlock(),
          ),
        ),
        const SizedBox(height: LockLayout.gap),
        VaultButton(
          label: 'Unlock',
          isLoading: _busy,
          onPressed: coolingDown ? null : _unlock,
        ),
        // Hidden while typing so the keyboard edge never cuts it in half on
        // small phones; it returns when the keyboard closes.
        if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
          const SizedBox(height: AppSpacing.sm),
          LockTextLink(
            label: 'Forgot password?',
            onPressed: _busy
                ? null
                : () => setState(() {
                      _error = null;
                      _recovering = true;
                    }),
          ),
        ],
      ];
    }

    return LockLayout(
      mark: const SuiteAppIcon(app: SuiteApp.vaultly, size: 64),
      title: 'Vaultly',
      message: _recovering ? 'Reset your master password' : null,
      bottom: showBiometric
          ? LockBiometricButton(
              onPressed:
                  (coolingDown || _biometricBusy) ? null : _biometricUnlock,
            )
          : null,
      children: controls,
    );
  }
}

/// "Forgot password?": recovery key + new master password. Wrong keys share
/// the unlock cooldown.
class _RecoveryForm extends ConsumerStatefulWidget {
  const _RecoveryForm({
    required this.coolingDown,
    required this.cooldownLabel,
    required this.onCooldown,
    required this.onBack,
  });

  final bool coolingDown;
  final String cooldownLabel;
  final ValueChanged<Duration> onCooldown;
  final VoidCallback onBack;

  @override
  ConsumerState<_RecoveryForm> createState() => _RecoveryFormState();
}

class _RecoveryFormState extends ConsumerState<_RecoveryForm> {
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final Future<bool> _hasKey =
      ref.read(masterAuthServiceProvider).hasRecoveryKey();
  bool _busy = false;
  String? _keyError;
  String? _passwordError;
  int _keyFailures = 0;
  int _passwordFailures = 0;

  @override
  void dispose() {
    _key.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || widget.coolingDown) return;
    if (RecoveryKey.normalize(_key.text) == null) {
      setState(() {
        _keyError = 'A recovery key has ${RecoveryKey.length} '
            'letters and numbers, like XXXX-XXXX-…';
        _keyFailures++;
      });
      return;
    }
    if (_password.text.length < MasterAuthService.minPasswordLength) {
      setState(() {
        _passwordError = 'Use at least '
            '${MasterAuthService.minPasswordLength} characters.';
        _passwordFailures++;
      });
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() {
        _passwordError = 'The passwords do not match.';
        _passwordFailures++;
      });
      return;
    }
    setState(() {
      _busy = true;
      _keyError = null;
      _passwordError = null;
    });
    final result =
        await ref.read(sessionProvider.notifier).resetWithRecoveryKey(
              recoveryKey: _key.text,
              newPassword: _password.text,
            );
    if (!mounted) return;
    switch (result) {
      case UnlockSuccess():
        break;
      case UnlockWrongPassword(:final cooldown):
        setState(() {
          _keyError = 'That recovery key is not right.';
          _keyFailures++;
        });
        if (cooldown != null) widget.onCooldown(cooldown);
      case UnlockCoolingDown(:final remaining):
        widget.onCooldown(remaining);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return FutureBuilder<bool>(
      future: _hasKey,
      builder: (context, snapshot) {
        final hasKey = snapshot.data;
        if (hasKey == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasKey
                  ? 'Enter the recovery key you saved, then choose a new '
                      'master password. Your vault stays as it is.'
                  : 'No recovery key was set up for this vault, so a '
                      'forgotten master password cannot be reset. If '
                      'biometric unlock works, use it, then create a recovery '
                      'key in Settings.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
            ),
            if (hasKey) ...[
              const SizedBox(height: AppSpacing.lg),
              LockShake(
                trigger: _keyFailures,
                child: AppTextField(
                  label: 'Recovery key',
                  controller: _key,
                  hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                  monospace: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  errorText: _keyError,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _keyError = null),
                ),
              ),
              const SizedBox(height: LockLayout.gap),
              AppTextField(
                label: 'New master password',
                controller: _password,
                obscureText: true,
                hint:
                    'At least ${MasterAuthService.minPasswordLength} characters',
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _passwordError = null),
              ),
              const SizedBox(height: LockLayout.gap),
              LockShake(
                trigger: _passwordFailures,
                child: AppTextField(
                  label: 'Confirm new master password',
                  controller: _confirm,
                  obscureText: true,
                  errorText: widget.coolingDown
                      ? widget.cooldownLabel
                      : _passwordError,
                  textInputAction: TextInputAction.go,
                  onChanged: (_) => setState(() => _passwordError = null),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: LockLayout.gap),
              VaultButton(
                label: 'Reset and unlock',
                isLoading: _busy,
                onPressed: widget.coolingDown ? null : _submit,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            LockTextLink(
              label: 'Back to unlock',
              onPressed: _busy ? null : widget.onBack,
            ),
          ],
        );
      },
    );
  }
}
