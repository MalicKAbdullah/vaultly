import 'package:core_crypto/core_crypto.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';

/// The password generator UI: live preview, length slider, character-class
/// toggles, regenerate, copy, and an optional "use this password" action for
/// the entry editor.
class GeneratorPanel extends ConsumerStatefulWidget {
  const GeneratorPanel({this.onUse, super.key});

  /// When non-null, a "Use this password" button is shown.
  final ValueChanged<String>? onUse;

  @override
  ConsumerState<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends ConsumerState<GeneratorPanel> {
  double _length = 20;
  bool _uppercase = true;
  bool _numbers = true;
  bool _symbols = true;
  String _password = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      _password = PasswordGenerator.generate(
        length: _length.round(),
        includeUppercase: _uppercase,
        includeNumbers: _numbers,
        includeSymbols: _symbols,
      );
    });
  }

  Future<void> _copy() async {
    await ref.read(clipboardGuardProvider).copySensitive(_password);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password copied. It clears in 30 seconds.'),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: AppTextStyles.label),
      value: value,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) {
        onChanged(v);
        _regenerate();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLg),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  _password,
                  key: ValueKey(_password),
                  style: AppTextStyles.code.copyWith(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StrengthMeter(password: _password),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _regenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('Regenerate'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Length', style: AppTextStyles.labelStrong),
            Text('${_length.round()}', style: AppTextStyles.number),
          ],
        ),
        Slider(
          value: _length,
          min: 8,
          max: 64,
          divisions: 56,
          onChanged: (v) => setState(() => _length = v),
          onChangeEnd: (_) => _regenerate(),
        ),
        _toggle('Uppercase letters (A–Z)', _uppercase, (v) => _uppercase = v),
        _toggle('Numbers (0–9)', _numbers, (v) => _numbers = v),
        _toggle('Symbols (!@#…)', _symbols, (v) => _symbols = v),
        if (widget.onUse != null) ...[
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => widget.onUse!(_password),
            icon: const Icon(Icons.check),
            label: const Text('Use this password'),
          ),
        ],
      ],
    );
  }
}
