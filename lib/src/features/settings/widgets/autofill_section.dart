import 'package:core_theme/core_theme.dart';
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

    final scheme = Theme.of(context).colorScheme;
    final enabled = status.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            'AUTOFILL',
            style:
                AppTextStyles.overline.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.edit_note_outlined),
          title: const Text('Fill passwords in other apps'),
          subtitle: Text(
            enabled
                ? 'On — login forms offer "Unlock Vaultly to fill".'
                : 'Off — turn it on to fill logins in apps and websites '
                    'without copying and pasting.',
          ),
          trailing:
              enabled ? Icon(Icons.check_circle, color: scheme.primary) : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: OutlinedButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: Text(
              enabled
                  ? 'Manage in system settings'
                  : 'Turn on in system settings',
            ),
          ),
        ),
      ],
    );
  }
}
