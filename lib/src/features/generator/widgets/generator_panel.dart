import 'package:core_crypto/core_crypto.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/generator/services/strength_estimator.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';

/// The password generator: the password large in mono with digits and
/// symbols picked out, its live entropy, length and character classes, and
/// an optional "Use this password" action for the entry editor.
class GeneratorPanel extends ConsumerStatefulWidget {
  const GeneratorPanel({this.onUse, super.key});

  /// When non-null, a "Use this password" button is shown.
  final ValueChanged<String>? onUse;

  @override
  ConsumerState<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends ConsumerState<GeneratorPanel> {
  int _length = 20;
  bool _uppercase = true;
  bool _numbers = true;
  bool _symbols = true;
  String _password = '';

  static const _minLength = 8;
  static const _maxLength = 64;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      _password = PasswordGenerator.generate(
        length: _length,
        includeUppercase: _uppercase,
        includeNumbers: _numbers,
        includeSymbols: _symbols,
      );
    });
  }

  Future<void> _copy() async {
    final guard = ref.read(clipboardGuardProvider);
    await guard.copySensitive(_password);
    if (!mounted) return;
    showCopiedSnack(context, what: 'Password', clearsAfter: guard.clearAfter);
  }

  Widget _toggle(String label, String example, bool value,
      ValueChanged<bool> onChanged) {
    return AppListRow(
      dense: true,
      title: label,
      subtitle: example,
      onTap: () {
        onChanged(!value);
        _regenerate();
      },
      trailing: Switch(
        value: value,
        onChanged: (v) {
          onChanged(v);
          _regenerate();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final strength = StrengthEstimator.estimate(_password);
    final tone = StrengthMeter.colorFor(strength.level, c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            side: BorderSide(color: c.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New password',
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: Semantics(
                      key: ValueKey(_password),
                      label: 'Generated password',
                      child: _ColoredPassword(_password),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${strength.bits.round()}',
                      style: AppTextStyles.numberLarge.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'bits of entropy',
                        style: AppTextStyles.label.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        strength.level.label,
                        style: AppTextStyles.labelStrong.copyWith(color: tone),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.smd),
                StrengthMeter(password: _password, showEntropy: false),
                const SizedBox(height: AppSpacing.mdl),
                Row(
                  children: [
                    Expanded(
                      child: VaultButton(
                        label: 'Regenerate',
                        icon: Icons.refresh_rounded,
                        variant: VaultButtonVariant.secondary,
                        onPressed: _regenerate,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.smd),
                    Expanded(
                      child: VaultButton(
                        label: 'Copy',
                        icon: Icons.copy_rounded,
                        variant: widget.onUse == null
                            ? VaultButtonVariant.primary
                            : VaultButtonVariant.secondary,
                        onPressed: _copy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.smd),
        VaultCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Length',
                    style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    '$_length',
                    style: AppTextStyles.numberMedium.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'characters',
                    style: AppTextStyles.label.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _length.toDouble(),
                min: _minLength.toDouble(),
                max: _maxLength.toDouble(),
                divisions: _maxLength - _minLength,
                label: '$_length',
                semanticFormatterCallback: (v) => '${v.round()} characters',
                onChanged: (v) {
                  if (v.round() == _length) return;
                  _length = v.round();
                  _regenerate();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.smd),
        RowGroup(
          separatorIndent: AppSpacing.md,
          children: [
            _toggle('Uppercase letters', 'A–Z', _uppercase,
                (v) => _uppercase = v),
            _toggle('Numbers', '0–9', _numbers, (v) => _numbers = v),
            _toggle('Symbols', '! @ # \$ % & *', _symbols,
                (v) => _symbols = v),
          ],
        ),
        if (widget.onUse != null) ...[
          const SizedBox(height: AppSpacing.mdl),
          VaultButton(
            label: 'Use this password',
            icon: Icons.check_rounded,
            onPressed: () => widget.onUse!(_password),
          ),
        ],
      ],
    );
  }
}

/// The password in large mono; digits take the accent and symbols the
/// secondary ink, so a password read aloud or retyped is unambiguous.
class _ColoredPassword extends StatelessWidget {
  const _ColoredPassword(this.password);

  final String password;

  static final _digit = RegExp('[0-9]');
  static final _letter = RegExp('[a-zA-Z]');

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final base = AppTextStyles.codeLarge.copyWith(
      color: c.textPrimary,
      height: 1.4,
      letterSpacing: 0.5,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final ch in password.split(''))
            TextSpan(
              text: ch,
              style: _digit.hasMatch(ch)
                  ? base.copyWith(color: c.accent)
                  : _letter.hasMatch(ch)
                      ? base
                      : base.copyWith(color: c.textSecondary),
            ),
        ],
      ),
      style: base,
    );
  }
}
