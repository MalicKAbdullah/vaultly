import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/features/passkeys/providers/credential_providers.dart';

/// Settings card for Vaultly as the Android 14+ passkey and password
/// provider: whether it is on, and a button to the system screen where it
/// is turned on. Renders nothing before Android 14 and off Android.
class PasskeySettingsSection extends ConsumerStatefulWidget {
  const PasskeySettingsSection({super.key});

  @override
  ConsumerState<PasskeySettingsSection> createState() =>
      _PasskeySettingsSectionState();
}

class _PasskeySettingsSectionState extends ConsumerState<PasskeySettingsSection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings screen — re-check the state.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(passkeyProviderStatusProvider);
    }
  }

  Future<void> _openSettings() async {
    final opened = await ref.read(credentialBridgeProvider).openSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the system settings screen.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(passkeyProviderStatusProvider).valueOrNull;
    if (status == null || !status.supported) return const SizedBox.shrink();

    final c = SuiteColors.of(context);
    final enabled = status.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Passkeys'),
        RowGroup(
          separatorIndent: AppSpacing.md,
          children: [
            AppListRow(
              leading: IconBadge(
                icon: Icons.key_rounded,
                color: enabled ? c.positive : null,
                size: 36,
              ),
              title: 'Passkeys and sign-in sheet',
              subtitle: enabled ? 'On' : 'Off',
              trailing: enabled
                  ? Icon(Icons.check_circle_rounded, color: c.positive)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    enabled
                        ? 'Sites and apps can save passkeys in Vaultly, and '
                            'the sign-in sheet offers "Unlock Vaultly".'
                        : 'Turn Vaultly on under Passwords, passkeys and '
                            'accounts to save passkeys and sign in with them.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.smd),
                  VaultButton(
                    compact: true,
                    variant: enabled
                        ? VaultButtonVariant.secondary
                        : VaultButtonVariant.primary,
                    icon: Icons.open_in_new_rounded,
                    label: enabled
                        ? 'Manage in system settings'
                        : 'Turn on in system settings',
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
