import 'package:core_backup/core_backup.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultkey/src/core/app_info.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/router/app_router.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final biometrics = ref.watch(biometricStateProvider).valueOrNull;
    final autoLock = ref.watch(autoLockProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          const _SectionHeader('Security'),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            subtitle: Text(
              (biometrics?.supported ?? false)
                  ? 'Use fingerprint or face to unlock'
                  : 'Not available on this device',
            ),
            value: biometrics?.enabled ?? false,
            onChanged: (biometrics?.supported ?? false)
                ? (v) => _toggleBiometrics(context, ref, v)
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock'),
            subtitle: Text('After ${_autoLockLabel(autoLock)} of inactivity'),
            trailing: PopupMenuButton<Duration>(
              icon: const Icon(Icons.expand_more),
              initialValue: autoLock,
              onSelected: (d) => ref.read(autoLockProvider.notifier).set(d),
              itemBuilder: (context) => [
                for (final choice in autoLockChoices)
                  PopupMenuItem(
                    value: choice,
                    child: Text(_autoLockLabel(choice)),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change master password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.changeMasterPassword),
          ),
          // Hides itself entirely on devices without autofill (iOS).
          const AutofillSection(),
          const Divider(height: AppSpacing.lg),
          const _SectionHeader('Auto-backup'),
          AutoBackupSection(
            service: ref.watch(autoBackupServiceProvider),
            producer: ref.watch(vaultBackupProducerProvider),
          ),
          const Divider(height: AppSpacing.lg),
          const _SectionHeader('Your data'),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Export'),
            subtitle: const Text('Encrypted backup or CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.export),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import'),
            subtitle: const Text('Restore a backup or bring passwords over'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.import),
          ),
          const Divider(height: AppSpacing.lg),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text(AppInfo.name),
            subtitle: Text('Version ${AppInfo.version}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              'Your passwords are stored only on this device, protected '
              'by encryption. Vaultly never connects to the internet.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: AppSpacing.lg),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(
              'Erase all data',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () => _eraseAll(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.overline.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
