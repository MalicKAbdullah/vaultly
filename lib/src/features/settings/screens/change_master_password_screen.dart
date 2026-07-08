import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';
import 'package:vaultkey/src/features/generator/widgets/strength_meter.dart';

/// Changes the master password and re-encrypts the vault under the new key.
class ChangeMasterPasswordScreen extends ConsumerStatefulWidget {
  const ChangeMasterPasswordScreen({super.key});

  @override
  ConsumerState<ChangeMasterPasswordScreen> createState() =>
      _ChangeMasterPasswordScreenState();
}

class _ChangeMasterPasswordScreenState
    extends ConsumerState<ChangeMasterPasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _currentError;
  String? _newError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_newController.text.length < MasterAuthService.minPasswordLength) {
      setState(() => _newError = 'Use at least '
          '${MasterAuthService.minPasswordLength} characters.');
      return;
    }
    if (_newController.text != _confirmController.text) {
      setState(() => _newError = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _currentError = null;
      _newError = null;
    });
    final result =
        await ref.read(sessionProvider.notifier).changeMasterPassword(
              oldPassword: _currentController.text,
              newPassword: _newController.text,
            );
    if (!mounted) return;
    switch (result) {
      case UnlockSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Master password changed. Biometric unlock, if you use it, '
              'needs to be turned on again.',
            ),
          ),
        );
        context.pop();
      case UnlockWrongPassword():
        setState(() => _currentError = 'Your current password is not right.');
      case UnlockCoolingDown(:final remaining):
        setState(() => _currentError =
            'Too many attempts. Try again in ${remaining.inSeconds}s.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Change master password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your vault is re-encrypted with the new password. The old '
              'password stops working immediately.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            VaultTextField(
              label: 'Current password',
              controller: _currentController,
              obscureText: true,
              autofocus: true,
              errorText: _currentError,
              onChanged: (_) => setState(() => _currentError = null),
            ),
            const SizedBox(height: AppSpacing.md),
            VaultTextField(
              label: 'New password',
              controller: _newController,
              obscureText: true,
              hint: 'At least 8 characters',
              onChanged: (_) => setState(() => _newError = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            StrengthMeter(password: _newController.text),
            const SizedBox(height: AppSpacing.md),
            VaultTextField(
              label: 'Confirm new password',
              controller: _confirmController,
              obscureText: true,
              errorText: _newError,
              onChanged: (_) => setState(() => _newError = null),
              onSubmitted: (_) => _change(),
            ),
            const SizedBox(height: AppSpacing.lg),
            VaultButton(
              label: 'Change password',
              isLoading: _busy,
              onPressed: _busy ? null : _change,
            ),
          ],
        ),
      ),
    );
  }
}
