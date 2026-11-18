import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/health/services/fix_it.dart';
import 'package:vaultkey/src/features/autofill/providers/autofill_providers.dart';
import 'package:vaultkey/src/features/autofill/services/login_capture.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Asks whether to keep a login the user just submitted in another app or
/// a browser: save it, update the saved password, or leave it.
class SaveLoginScreen extends ConsumerStatefulWidget {
  const SaveLoginScreen({super.key});

  @override
  ConsumerState<SaveLoginScreen> createState() => _SaveLoginScreenState();
}

class _SaveLoginScreenState extends ConsumerState<SaveLoginScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    await action();
    await ref.read(pendingSaveProvider.notifier).finish(message: message);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final login = ref.watch(pendingSaveProvider).valueOrNull;
    final entries = ref.watch(vaultEntriesProvider).valueOrNull;
    if (login == null || entries == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final fix = ref.watch(fixTargetProvider);
    final fixId = fix != null &&
            fix.host == login.host &&
            fix.expiresAt.isAfter(ref.watch(clockProvider).now())
        ? fix.entryId
        : null;
    final decision = LoginCapture.decide(entries, login, fixEntryId: fixId);
    final site = login.host ?? login.package ?? 'this app';

    final (String title, String? action, String message) = switch (decision) {
      AlreadySaved() => ('Already saved', null, ''),
      UpdatePassword(:final entry) => (
          'Update ${entry.title}?',
          'Update',
          'Password updated',
        ),
      SaveNew() => ('Save password to Vaultly?', 'Save', 'Saved to Vaultly'),
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Not now',
          icon: const Icon(Icons.close),
          onPressed: _busy
              ? null
              : () => ref.read(pendingSaveProvider.notifier).finish(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTextStyles.h1),
              const SizedBox(height: AppSpacing.sm),
              Text(
                site,
                style:
                    AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              RowGroup(
                separatorIndent: AppSpacing.mdl,
                children: [
                  AppListRow(
                    title: 'Username',
                    subtitle: login.username.isEmpty ? '—' : login.username,
                  ),
                  const AppListRow(title: 'Password', subtitle: '••••••••'),
                ],
              ),
              const Spacer(),
              if (action != null) ...[
                VaultButton(
                  label: action,
                  onPressed: _busy
                      ? null
                      : () => _run(() => _apply(decision, login), message),
                ),
                const SizedBox(height: AppSpacing.smd),
              ],
              VaultButton(
                label: action == null ? 'Done' : 'Not now',
                variant: action == null
                    ? VaultButtonVariant.primary
                    : VaultButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => ref.read(pendingSaveProvider.notifier).finish(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _apply(CaptureDecision decision, CapturedLogin login) async {
    final vault = ref.read(vaultEntriesProvider.notifier);
    switch (decision) {
      case AlreadySaved():
        return;
      case UpdatePassword(:final entry):
        await vault.updatePassword(entry.id, login.password);
      case SaveNew(:final title, :final url):
        await vault.create(
          title: title,
          username: login.username,
          password: login.password,
          url: url,
          notes: '',
          category: EntryCategory.login,
        );
    }
  }
}
