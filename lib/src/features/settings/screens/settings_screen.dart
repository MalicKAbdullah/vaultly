import 'package:core_backup/core_backup.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/app_info.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';
import 'package:vaultkey/src/features/settings/providers/settings_providers.dart';
import 'package:vaultkey/src/features/settings/widgets/autofill_section.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Settings: security, auto-backup, export/import, about, danger zone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _toggleBiometrics(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    final notifier = ref.read(biometricStateProvider.notifier);
    if (enable) {
      final ok = await notifier.enable();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric unlock was not enabled.'),
          ),
        );
      }
    } else {
      await notifier.disable();
    }
  }

  Future<void> _eraseAll(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase everything?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes every entry, your master '
              'password, and all settings on this device. Backups you '
              'exported are not touched.\n\nType DELETE to confirm.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim() == 'DELETE'),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed ?? false) {
      await ref.read(sessionProvider.notifier).eraseAll();
    }
  }

  String _autoLockLabel(Duration d) =>
      d.inMinutes == 1 ? '1 minute' : '${d.inMinutes} minutes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    final biometrics = ref.watch(biometricStateProvider).valueOrNull;
    final autoLock = ref.watch(autoLockProvider);
    final supported = biometrics?.supported ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            const TabHeader(eyebrow: 'Vaultly', title: 'Settings'),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Security'),
                  RowGroup(
                    separatorIndent: settingsRowIndent,
                    children: [
                      SettingsTile(
                        icon: Icons.fingerprint_rounded,
                        title: 'Biometric unlock',
                        subtitle: supported
                            ? 'Use fingerprint or face to unlock'
                            : 'Not available on this device',
                        trailing: Switch(
                          value: biometrics?.enabled ?? false,
                          onChanged: supported
                              ? (v) => _toggleBiometrics(context, ref, v)
                              : null,
                        ),
                      ),
                      PopupMenuButton<Duration>(
                        tooltip: 'Auto-lock',
                        initialValue: autoLock,
                        onSelected: (d) =>
                            ref.read(autoLockProvider.notifier).set(d),
                        itemBuilder: (context) => [
                          for (final choice in autoLockChoices)
                            PopupMenuItem(
                              value: choice,
                              child: Text(_autoLockLabel(choice)),
                            ),
                        ],
                        child: SettingsTile(
                          icon: Icons.timer_outlined,
                          title: 'Auto-lock',
                          subtitle:
                              'After ${_autoLockLabel(autoLock)} of inactivity',
                          trailing: Icon(
                            Icons.unfold_more_rounded,
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.password_rounded,
                        title: 'Change master password',
                        onTap: () =>
                            context.push(AppRoutes.changeMasterPassword),
                      ),
                    ],
                  ),
                  // Hides itself entirely on devices without autofill (iOS).
                  const AutofillSection(),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(
                    title: 'Auto-backup',
                    subtitle: 'An encrypted copy, saved on a schedule',
                  ),
                  _Panel(
                    child: AutoBackupSection(
                      service: ref.watch(autoBackupServiceProvider),
                      producer: ref.watch(vaultBackupProducerProvider),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Your data'),
                  RowGroup(
                    separatorIndent: settingsRowIndent,
                    children: [
                      SettingsTile(
                        icon: Icons.upload_rounded,
                        title: 'Export',
                        subtitle: 'Encrypted backup or CSV',
                        onTap: () => context.push(AppRoutes.export),
                      ),
                      SettingsTile(
                        icon: Icons.download_rounded,
                        title: 'Import',
                        subtitle: 'Restore a backup or bring passwords over',
                        onTap: () => context.push(AppRoutes.import),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Updates'),
                  const _UpdateSection(),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Danger zone'),
                  RowGroup(
                    children: [
                      SettingsTile(
                        icon: Icons.delete_forever_outlined,
                        iconColor: c.negative,
                        title: 'Erase all data',
                        subtitle: 'Deletes every entry on this device',
                        onTap: () => _eraseAll(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const _About(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Separator inset for a `SettingsTile` row (36 px badge).
const double settingsRowIndent = 66;

/// A card surface for a shared section that renders its own rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: child,
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Column(
      children: [
        const SuiteAppIcon(app: SuiteApp.vaultly, size: 56),
        const SizedBox(height: AppSpacing.smd),
        Text(
          AppInfo.name,
          style: AppTextStyles.h3.copyWith(color: c.textPrimary),
        ),
        Text(
          'Version ${AppInfo.version}',
          style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppSpacing.smd),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Your passwords are stored only on this device, protected '
            'by encryption. The only network use is the optional update '
            'check.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SuiteEndorsement(),
      ],
    );
  }
}

/// "Check for updates on open" toggle + a manual "Check now", backed by
/// core_update. On by default; the only network call the app makes.
class _UpdateSection extends ConsumerStatefulWidget {
  const _UpdateSection();

  @override
  ConsumerState<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends ConsumerState<_UpdateSection> {
  bool _checking = false;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final info = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _checking = false);
    final messenger = ScaffoldMessenger.of(context);
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Update available · v${info.version}'),
          action: SnackBarAction(
            label: 'Update',
            onPressed: () => ref.read(updateServiceProvider).openDownload(info),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoCheck = ref.watch(updateAutoCheckProvider).valueOrNull ?? true;
    return RowGroup(
      separatorIndent: settingsRowIndent,
      children: [
        SettingsTile(
          icon: Icons.system_update_alt_rounded,
          title: 'Check for updates on open',
          subtitle: 'Looks on GitHub. Nothing is uploaded.',
          trailing: Switch(
            value: autoCheck,
            onChanged: (v) async {
              await ref.read(secureStorageProvider).write(
                    key: updateAutoCheckKey,
                    value: v ? 'true' : 'false',
                  );
              ref.invalidate(updateAutoCheckProvider);
              ref.invalidate(updateCheckProvider);
            },
          ),
        ),
        SettingsTile(
          icon: Icons.refresh_rounded,
          title: 'Check now',
          trailing: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _checking ? null : _checkNow,
        ),
      ],
    );
  }
}
