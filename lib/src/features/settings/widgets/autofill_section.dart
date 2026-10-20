import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/autofill/providers/autofill_providers.dart';

/// Settings card for the Android autofill feature: what it does, whether
/// it is on, and a button to the system screen where it is turned on.
/// Renders nothing on devices without autofill (e.g. iOS).
class AutofillSection extends ConsumerStatefulWidget {
  const AutofillSection({super.key});

  @override
  ConsumerState<AutofillSection> createState() => _AutofillSectionState();
}

class _AutofillSectionState extends ConsumerState<AutofillSection>
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
      ref.invalidate(autofillStatusProvider);
    }
  }

  Future<void> _openSettings() async {
    final opened = await ref.read(autofillBridgeProvider).openSettings();
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
    final status = ref.watch(autofillStatusProvider).valueOrNull;
    if (status == null || !status.supported) return const SizedBox.shrink();

    final c = SuiteColors.of(context);
    final enabled = status.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Autofill'),
        RowGroup(
          separatorIndent: AppSpacing.md,
          children: [
            AppListRow(
              leading: IconBadge(
                icon: Icons.edit_note_rounded,
                color: enabled ? c.positive : null,
                size: 36,
              ),
              title: 'Fill passwords in other apps',
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
                        ? 'Login forms offer "Unlock Vaultly to fill".'
                        : 'Turn it on to fill logins in apps and websites '
                            'without copying and pasting.',
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
