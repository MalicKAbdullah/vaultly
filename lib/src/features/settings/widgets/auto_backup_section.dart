import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/features/backup/providers/backup_providers.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_policy.dart';
import 'package:vaultkey/src/features/backup/services/auto_backup_service.dart';
import 'package:vaultkey/src/features/backup/services/backup_codec.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// Settings block for scheduled encrypted backups: interval, folder,
/// passphrase, status line, and "Back up now".
class AutoBackupSection extends ConsumerWidget {
  const AutoBackupSection({super.key});

  Future<void> _setInterval(
    BuildContext context,
    WidgetRef ref,
    BackupInterval interval,
  ) async {
    final controller = ref.read(autoBackupControllerProvider.notifier);
    final config = ref.read(autoBackupControllerProvider).valueOrNull ??
        AutoBackupConfig.empty;

    if (interval != BackupInterval.off) {
      // First-time enable: make sure a passphrase and folder exist.
      if (!config.hasPassphrase) {
        final passphrase = await _askPassphrase(context);
        if (passphrase == null) return;
        await controller.setPassphrase(passphrase);
      }
      if (config.folderUri == null) {
        final picked = await controller.pickFolder();
        if (!picked) return;
      }
    }
    await controller.setInterval(interval);
  }

  static Future<String?> _askPassphrase(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const _PassphraseDialog(),
    );
  }

  Future<void> _backupNow(BuildContext context, WidgetRef ref) async {
    final entries = ref.read(vaultEntriesProvider).valueOrNull ?? const [];
    final result = await ref
        .read(autoBackupControllerProvider.notifier)
        .backupNow(entries);
    if (!context.mounted) return;
    final message = switch (result) {
      BackupWritten(:final fileName) => 'Backed up as $fileName.',
      BackupFailed(:final message) => message,
      BackupSkipped() => 'Nothing to back up right now.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _relative(DateTime time, DateTime now) {
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final config = ref.watch(autoBackupControllerProvider).valueOrNull ??
        AutoBackupConfig.empty;
    final controller = ref.read(autoBackupControllerProvider.notifier);
    final enabled = config.interval != BackupInterval.off;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SegmentedButton<BackupInterval>(
            segments: [
              for (final interval in BackupInterval.values)
                ButtonSegment(
                  value: interval,
                  label: Text(interval.label),
                ),
            ],
            selected: {config.interval},
            onSelectionChanged: (selection) =>
                _setInterval(context, ref, selection.first),
          ),
        ),
        if (enabled) ...[
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Backup folder'),
            subtitle: Text(
              config.folderName ?? 'Not chosen yet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: controller.pickFolder,
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Backup passphrase'),
            subtitle: Text(config.hasPassphrase ? 'Set' : 'Not set'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final passphrase = await _askPassphrase(context);
              if (passphrase != null) {
                await controller.setPassphrase(passphrase);
              }
            },
          ),
          ListTile(
            leading: Icon(
              config.lastError == null
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: config.lastError == null
                  ? null
                  : AppColors.warning(Theme.of(context).brightness),
            ),
            title: Text(
              config.lastBackupAt == null
                  ? 'No backup yet'
                  : 'Last backup: '
                      '${_relative(config.lastBackupAt!, DateTime.now())}'
                      '${config.folderName == null ? '' : ' • ${config.folderName}'}',
            ),
            subtitle: config.lastError == null
                ? null
                : Text(
                    config.lastError!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning(Theme.of(context).brightness),
                    ),
                  ),
            trailing: TextButton(
              onPressed: config.isReady ? () => _backupNow(context, ref) : null,
              child: const Text('Back up now'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              'On each unlock, Vaultly quietly writes an encrypted backup '
              'to your folder when one is due. Pick a Google Drive folder '
              'to keep backups synced to your Drive.',
              style: AppTextStyles.caption
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.length < BackupCodec.minPassphraseLength) {
      setState(() => _error =
          'Use at least ${BackupCodec.minPassphraseLength} characters.');
      return;
    }
    if (_controller.text != _confirmController.text) {
      setState(() => _error = 'The passphrases do not match.');
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Backups are encrypted with this passphrase. You will need it '
            'to restore — keep it somewhere safe.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Passphrase'),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Confirm passphrase',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
