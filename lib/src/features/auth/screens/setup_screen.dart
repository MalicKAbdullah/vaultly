import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';

/// First run: create the master password that protects the vault.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _passwordController.text.length >= MasterAuthService.minPasswordLength &&
      _passwordController.text == _confirmController.text;

  Future<void> _create() async {
    final password = _passwordController.text;
    if (password.length < MasterAuthService.minPasswordLength) {
      setState(
        () => _error = 'Use at least '
            '${MasterAuthService.minPasswordLength} characters.',
      );
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(sessionProvider.notifier).setup(password);
    // Router redirects to the vault when the session unlocks.
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                    child: Icon(Icons.shield_outlined,
                        size: 36, color: scheme.primary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Welcome to Vaultly',
                      style: AppTextStyles.h1, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Create a master password. It protects everything and '
                    'is never stored anywhere — make it one you will '
                    'remember.',
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
                    hint: 'At least 8 characters',
                    onChanged: (_) => setState(() => _error = null),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  StrengthMeter(password: _passwordController.text),
                  const SizedBox(height: AppSpacing.md),
                  VaultTextField(
                    label: 'Confirm password',
                    controller: _confirmController,
                    obscureText: true,
                    errorText: _error,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _create(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  VaultButton(
                    label: 'Create my vault',
                    isLoading: _busy,
                    onPressed: _isValid && !_busy ? _create : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Your passwords are stored only on this device, '
                    'protected by encryption.',
                    style: AppTextStyles.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
