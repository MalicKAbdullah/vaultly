import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/services/master_auth_service.dart';

/// Re-confirms the owner before a secret is shown or replaced: a fresh
/// biometric prompt when biometric unlock is on, otherwise (or when it fails)
/// the master password, under the unlock cooldown.
Future<bool> confirmVaultIdentity(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  if (await ref.read(biometricServiceProvider).isEnabled() &&
      await ref.read(biometricAuthenticatorProvider).authenticate(reason)) {
    return true;
  }
  if (!context.mounted) return false;
  final controller = TextEditingController();
  final password = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(reason),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Master password'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (password == null || password.isEmpty) return false;
  final result = await ref.read(masterAuthServiceProvider).unlock(password);
  if (result is UnlockSuccess) {
    result.key.fillRange(0, result.key.length, 0);
    return true;
  }
  if (!context.mounted) return false;
  switch (result) {
    case UnlockWrongPassword():
      _snack(context, 'That password is not right.');
    case UnlockCoolingDown(:final remaining):
      _snack(
          context, 'Too many attempts. Try again in ${remaining.inSeconds}s.');
    case UnlockSuccess():
      break;
  }
  return false;
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
