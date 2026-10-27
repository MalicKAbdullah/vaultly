import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/interfaces/credential_bridge.dart';
import 'package:vaultkey/src/features/passkeys/providers/credential_providers.dart';
import 'package:vaultkey/src/features/passkeys/services/passkey_vault.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Answers the Credential Manager request this launch was opened for, once
/// the vault is unlocked: confirms saving a new passkey, or completes a
/// sign-in straight away. Android closes Vaultly when the answer is sent.
class CredentialRequestScreen extends ConsumerWidget {
  const CredentialRequestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(credentialRequestProvider).valueOrNull;
    return switch (request) {
      PasskeyRegistrationRequest() => _SavePasskeyView(request: request),
      CredentialListingRequest() => _AutoAnswerView(
          message: 'Finding your sign-ins…',
          answer: (notifier) async {
            await notifier.answerListing(request);
            return true;
          },
        ),
      PasskeySignInRequest() => _AutoAnswerView(
          message: 'Signing in to ${request.rpId}…',
          answer: (notifier) => notifier.signIn(request),
          missing: 'This passkey is no longer in your vault.',
        ),
      PasswordSignInRequest() => _AutoAnswerView(
          message: 'Filling your password…',
          answer: (notifier) => notifier.fillPassword(request),
          missing: 'This password is no longer in your vault.',
        ),
      RejectedCredentialRequest() => _ProblemView(message: request.message),
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// "Save a passkey for github.com?" with the account it is for.
class _SavePasskeyView extends ConsumerStatefulWidget {
  const _SavePasskeyView({required this.request});

  final PasskeyRegistrationRequest request;

  @override
  ConsumerState<_SavePasskeyView> createState() => _SavePasskeyViewState();
}

class _SavePasskeyViewState extends ConsumerState<_SavePasskeyView> {
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(credentialRequestProvider.notifier)
          .savePasskey(widget.request);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? 'The passkey could not be created.';
      });
    }
  }

  Future<void> _cancel({bool excluded = false}) =>
      ref.read(credentialRequestProvider.notifier).cancel(excluded: excluded);

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final request = widget.request;
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const [];
    final excluded = PasskeyVault.holdsExcluded(entries, request);
    final replaces = PasskeyVault.sameAccount(entries, request) != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _cancel(excluded: excluded);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => _cancel(excluded: excluded),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xs,
            AppSpacing.gutter,
            AppSpacing.xxl,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconBadge(
                icon: Icons.key_rounded,
                color: c.accent,
                size: 56,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(
                excluded
                    ? 'Already saved in Vaultly'
                    : 'Save a passkey for ${request.rpName}?',
                style: AppTextStyles.h2.copyWith(color: c.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              excluded
                  ? 'Your vault already holds a passkey for this account, so '
                      'there is no need for another.'
                  : 'You will sign in to ${request.rpId} with your vault '
                      'unlock instead of a password. The passkey stays '
                      'encrypted in your vault.',
              style: AppTextStyles.body.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            RowGroup(
              separatorIndent: AppSpacing.md,
              children: [
                AppListRow(
                  dense: true,
                  title: 'Account',
                  trailing: _Value(request.userName),
                ),
                if (request.userDisplayName != request.userName)
                  AppListRow(
                    dense: true,
                    title: 'Name',
                    trailing: _Value(request.userDisplayName),
                  ),
                AppListRow(
                  dense: true,
                  title: 'Website',
                  trailing: _Value(request.rpId),
                ),
                if (request.caller != request.rpId)
                  AppListRow(
                    dense: true,
                    title: 'Asked by',
                    trailing: _Value(request.caller),
                  ),
              ],
            ),
            if (replaces && !excluded) ...[
              const SizedBox(height: AppSpacing.smd),
              const AppBanner(
                title: 'Replaces the passkey already saved for this account.',
                kind: BannerKind.warning,
                icon: Icons.swap_horiz_rounded,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.smd),
              AppBanner(
                title: _error!,
                kind: BannerKind.error,
                icon: Icons.error_outline_rounded,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (excluded)
              VaultButton(
                label: 'Close',
                onPressed: () => _cancel(excluded: true),
              )
            else ...[
              VaultButton(
                label: 'Save passkey',
                icon: Icons.key_rounded,
                isLoading: _busy,
                onPressed: _busy ? null : _save,
              ),
              const SizedBox(height: AppSpacing.smd),
              VaultButton(
                label: 'Cancel',
                variant: VaultButtonVariant.secondary,
                onPressed: _busy ? null : _cancel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sign-in steps need no choice from the user once the vault is open:
/// answer immediately and show progress until Android closes Vaultly.
class _AutoAnswerView extends ConsumerStatefulWidget {
  const _AutoAnswerView({
    required this.message,
    required this.answer,
    this.missing = '',
  });

  final String message;

  /// Sends the answer; false when the chosen credential is gone.
  final Future<bool> Function(CredentialRequestNotifier notifier) answer;

  /// Shown when [answer] reports the credential is gone.
  final String missing;

  @override
  ConsumerState<_AutoAnswerView> createState() => _AutoAnswerViewState();
}

class _AutoAnswerViewState extends ConsumerState<_AutoAnswerView> {
  String? _problem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final answered =
          await widget.answer(ref.read(credentialRequestProvider.notifier));
      if (!answered && mounted) setState(() => _problem = widget.missing);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _problem = e.message ?? 'Something went wrong.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_problem != null) return _ProblemView(message: _problem!);
    final c = SuiteColors.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.message,
              style: AppTextStyles.body.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A request Vaultly will not answer, and why. Closing reports the
/// failure back to the asking site or app.
class _ProblemView extends ConsumerWidget {
  const _ProblemView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void close() => ref.read(credentialRequestProvider.notifier).cancel();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: AppEmptyState(
              icon: Icons.gpp_maybe_outlined,
              title: 'Vaultly can’t help with this request',
              message: message,
              action: VaultButton(
                label: 'Close',
                isFullWidth: false,
                onPressed: close,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: AppTextStyles.label.copyWith(
            color: SuiteColors.of(context).textSecondary,
          ),
        ),
      );
}
