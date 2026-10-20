import 'package:core_lock/core_lock.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/app_info.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';

/// Shown by the router while [recoveryPromptProvider] is pending: either the
/// one-time offer to create a recovery key, or a freshly created key that
/// stays on screen until the user confirms saving it.
class RecoveryKeyScreen extends ConsumerStatefulWidget {
  const RecoveryKeyScreen({super.key});

  @override
  ConsumerState<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends ConsumerState<RecoveryKeyScreen> {
  String? _key;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(recoveryPromptProvider) == RecoveryPrompt.show) {
      Future.microtask(_create);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final key = await ref.read(sessionProvider.notifier).createRecoveryKey();
    if (mounted) setState(() => _key = key);
  }

  Future<void> _decline() async {
    await ref.read(masterAuthServiceProvider).markRecoveryOffered();
    _finish();
  }

  void _finish() =>
      ref.read(recoveryPromptProvider.notifier).state = RecoveryPrompt.none;

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final offer = ref.watch(recoveryPromptProvider) == RecoveryPrompt.offer;
    final Widget body;
    if (key != null) {
      body = RecoveryKeyView(
        recoveryKey: key,
        appName: AppInfo.name,
        onDone: _finish,
      );
    } else if (offer && !_creating) {
      body = _Offer(onCreate: _create, onDecline: _decline);
    } else {
      body = const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(canPop: false, child: body);
  }
}

class _Offer extends StatelessWidget {
  const _Offer({required this.onCreate, required this.onDecline});

  final VoidCallback onCreate;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.key_rounded, size: 40, color: c.accent),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Set up a recovery key',
                style: AppTextStyles.h2.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A recovery key lets you set a new master password if you '
                'forget yours and biometric unlock is not available. Without '
                'one, a forgotten master password means the vault is lost.',
                style: AppTextStyles.body.copyWith(color: c.textSecondary),
              ),
              const Spacer(),
              VaultButton(label: 'Create recovery key', onPressed: onCreate),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onDecline,
                child: Text(
                  'Not now — I can do this in Settings',
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
